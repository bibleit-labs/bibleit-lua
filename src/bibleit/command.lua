local errors = require("bibleit.errors")
local util = require("bibleit.util")
local M = {}
local mt = {}; mt.__index = mt
local state = setmetatable({}, { __mode = "k" })
function mt:string() return state[self].wire end

function mt:streaming() return state[self].streaming end

-- Do not implicitly stringify commands: they can contain caller-supplied secrets.
function M.is_command(v) return state[v] ~= nil end

local function build(prefix, args, streaming)
   for _, argument in ipairs(args or {}) do
      local value = argument
      util.assert(type(value) == "string" and value ~= "" and not value:find('[%z\r\n"]'),
         "arguments must be nonempty single lines without quotes or NUL")
      if value:find("[ \t]") then value = '"' .. value .. '"' end
      prefix = prefix .. " " .. value
   end
   local cmd = setmetatable({}, mt); state[cmd] = { wire = prefix, streaming = streaming or false }; return cmd
end
local function command(prefix, ...)
   local args = { ... }; for i = 1, select("#", ...) do
      if args[i] == nil then
         return nil,
             errors.invalid("missing command argument")
      end
   end
   return errors.protect(build, prefix, args)
end
local function fixed(wire) return function() return build(wire) end end
M.ping_command = fixed("PING"); M.server_info_command = fixed("SERVER INFO"); M.identity_command = fixed("AUTH INFO")
M.account_tokens_command = fixed("ACCOUNT TOKEN LIST"); M.translation_list_command = fixed("ACCOUNT TRANSLATION LIST")
M.live_list_command = fixed("LIVE LIST"); M.delete_all_lives_command = fixed("LIVE DELETE ALL")
M.account_info_command = fixed("ACCOUNT INFO"); M.account_quotas_command = fixed("ACCOUNT QUOTA LIST")
function M.add_translation_command(slug) return command("ACCOUNT TRANSLATION ADD", slug) end

function M.remove_translation_command(slug) return command("ACCOUNT TRANSLATION REMOVE", slug) end

function M.translation_info_command(slug) return command("TRANSLATION INFO", slug) end

function M.translation_catalog_command(slug) return command("TRANSLATION CATALOG", slug) end

local function reference(ref, require_translation)
   util.assert(type(ref) == "table", "reference must be a table")
   local chapter, verse = ref.chapter or 0, ref.verse or 0
   util.assert(util.integer(chapter, 0, 255) and util.integer(verse, 0, 255) and (verse == 0 or chapter ~= 0),
      "invalid chapter or verse")
   local args = {}
   if require_translation or ref.translation and ref.translation ~= "" then args[#args + 1] = ref.translation or "" end
   args[#args + 1] = ref.book or ""
   if chapter ~= 0 then args[#args + 1] = tostring(chapter) end
   if verse ~= 0 then args[#args + 1] = tostring(verse) end
   return args
end
function M.read_command(ref) return errors.protect(function() return build("READ", reference(ref, true)) end) end

function M.search_command(translation, query) return command("SEARCH", translation, query) end

function M.create_live_command(name)
   if name == nil or name == "" then return build("LIVE CREATE") end; return command("LIVE CREATE", name)
end

local actions = { INFO = true, STATS = true, START = true, STOP = true, PAUSE = true, RESUME = true, CLEAR = true, DELETE = true, SUBSCRIBE = true }
function M.live_command(id, action)
   return errors.protect(function()
      util.assert(actions[action], "unsupported Live action")
      return build(build("LIVE", { id or "" }):string() .. " " .. action, {}, action == "SUBSCRIBE")
   end)
end

function M.set_live_command(id, field, ...)
   local values = { ... }
   return errors.protect(function()
      util.assert(field == "NAME" or field == "REFERENCE" or field == "TRANSLATIONS", "unsupported Live field")
      util.assert(#values > 0 and (field == "TRANSLATIONS" or #values == 1), "invalid Live field values")
      return build(build("LIVE", { id or "" }):string() .. " SET " .. field, values)
   end)
end

function M.live_secret_command(id, action, value)
   action = action or ""; value = value or ""
   return errors.protect(function()
      local prefix = build("LIVE", { id or "" }):string() .. " SECRET"
      if action == "" then
         util.assert(
            type(value) == "string" and value:lower() ~= "create" and value:lower() ~= "rotate" and value:lower() ~=
            "delete", "secret conflicts with a protocol keyword")
         return build(prefix, { value })
      end
      util.assert(action == "CREATE" or action == "ROTATE" or action == "DELETE", "unsupported secret action")
      util.assert(value == "", "unexpected secret value"); return build(prefix .. " " .. action)
   end)
end

function M.live_stack_command(id, action)
   return errors.protect(function()
      util.assert(action == "INFO" or action == "CLEAR", "unsupported stack action")
      return build(build("LIVE", { id or "" }):string() .. " STACK " .. action)
   end)
end

function M.push_live_command(id, ref)
   return errors.protect(function()
      return build(build("LIVE", { id or "" }):string() .. " STACK PUSH",
         reference(ref, false))
   end)
end

function M.pop_live_command(id, count)
   count = count or 0
   return errors.protect(function()
      util.assert(util.integer(count, 0, 2147483647), "invalid pop count")
      return build(build("LIVE", { id or "" }):string() .. " STACK POP", count == 0 and {} or { tostring(count) })
   end)
end

function M.help_command(topic)
   if topic == nil or topic == "" then return build("HELP") end
   local topics = { ROOT = true, SERVER = true, ACCOUNT = true, AUTH = true, TRANSLATION = true, LIVE = true, ORGANIZATION = true, BROADCAST = true }
   if type(topic) ~= "string" or not topics[topic:upper()] then return nil, errors.invalid("unsupported help topic") end
   return command("HELP", topic:upper())
end

function M.organization_list_command(cursor)
   if cursor == nil or cursor == "" then return build("ORGANIZATION LIST") end
   return command("ORGANIZATION LIST", cursor)
end

function M.organization_application_status_command(id)
   return errors.protect(function() return build(build("ORGANIZATION APPLICATION", { id or "" }):string() .. " STATUS") end)
end

-- Broadcast commands deliberately do not manage credentials, persist request
-- tickets, retry mutations or establish captures. The caller owns the executor
-- and must keep one non-PTY SSH shell for begin/chunk/commit/abort.
local function broadcast_uuid(value)
   util.assert(type(value) == "string" and value:match("^[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+$")
      and #value == 36 and value:sub(9,9) == "-" and value:sub(14,14) == "-"
      and value:sub(19,19) == "-" and value:sub(24,24) == "-", "expected canonical workspace or resource UUID")
   return value
end
local function broadcast_number(value, minimum, maximum)
   if type(value) == "number" then
      util.assert(util.integer(value, minimum, 9007199254740991), "large integers must be decimal strings")
      value = string.format("%.0f", value)
   end
   util.assert(type(value) == "string" and value:match("^%d+$"), "expected decimal integer")
   value = value:gsub("^0+", ""); if value == "" then value = "0" end
   local max = tostring(maximum)
   util.assert((#value < #max or #value == #max and value <= max) and tonumber(value) >= minimum,
      "integer outside broadcast bounds")
   return value
end
local function broadcast_ticket(value)
   util.assert(type(value) == "string" and #value > 0 and #value <= 768, "invalid request ticket")
   return value
end
local function broadcast_base64(value, maximum)
   util.assert(type(value) == "string" and #value > 0 and #value <= 4096, "invalid base64 payload size")
   local mime = require("bibleit.internal.base64")
   local bytes = mime.unb64(value)
   util.assert(type(bytes) == "string" and #bytes > 0 and #bytes <= maximum and mime.b64(bytes) == value,
      "expected canonical bounded base64 payload")
   return value
end
local function broadcast_build(org, args)
   local wire = build("broadcast", { broadcast_uuid(org) }):string()
   local result = build(wire, args)
   util.assert(#result:string() <= 8192, "broadcast command exceeds 8192 bytes")
   return result
end
function M.broadcast_setup_list_command(org, limit, after)
   return errors.protect(function()
      local args = { "setup", "list" }
      if limit ~= nil or after ~= nil then args[#args+1] = broadcast_number(limit or 25, 1, "99") end
      if after ~= nil then args[#args+1] = broadcast_uuid(after) end
      return broadcast_build(org, args)
   end)
end
function M.broadcast_setup_get_command(org, id)
   return errors.protect(function() return broadcast_build(org, { "setup", broadcast_uuid(id), "get" }) end)
end
function M.broadcast_setup_document_command(org, id, revision, offset)
   return errors.protect(function()
      return broadcast_build(org, { "setup", broadcast_uuid(id), "document",
         broadcast_number(revision, 1, "9223372036854775807"), broadcast_number(offset, 0, "1048576") })
   end)
end
function M.broadcast_write_intent_command(org, operation, target, revision, bytes, sha256)
   return errors.protect(function()
      util.assert(operation == "create" or operation == "save" or operation == "duplicate" or operation == "delete",
         "unsupported Setup operation")
      local rev = broadcast_number(revision, operation == "create" and 0 or 1, "9223372036854775807")
      if operation == "create" then util.assert(target == "new" and rev == "0", "create requires new and revision zero")
      else broadcast_uuid(target) end
      util.assert(type(sha256) == "string" and #sha256 == 64 and sha256:match("^[a-f0-9]+$"), "invalid SHA-256")
      return broadcast_build(org, { "write", "intent", operation, target, rev,
         broadcast_number(bytes, 2, "1048576"), sha256 })
   end)
end
for _, action in ipairs({ "begin", "status" }) do
   local operation = action
   M["broadcast_write_" .. operation .. "_command"] = function(org, ticket)
      return errors.protect(function() return broadcast_build(org, { "write", operation, broadcast_ticket(ticket) }) end)
   end
end
for _, action in ipairs({ "inspect", "abort" }) do
   local operation = action
   M["broadcast_write_" .. operation .. "_command"] = function(org, id)
      return errors.protect(function() return broadcast_build(org, { "write", operation, broadcast_uuid(id) }) end)
   end
end
function M.broadcast_write_chunk_command(org, id, offset, payload)
   return errors.protect(function() return broadcast_build(org, { "write", "chunk", broadcast_uuid(id),
      broadcast_number(offset, 0, "1048576"), broadcast_base64(payload, 3072) }) end)
end
function M.broadcast_write_commit_command(org, ticket, id)
   return errors.protect(function() return broadcast_build(org, { "write", "commit", broadcast_ticket(ticket), broadcast_uuid(id) }) end)
end
for _, action in ipairs({ "profiles", "channel", "preflight", "events", "publishers", "takeover" }) do
   local operation = action
   M["broadcast_" .. operation .. "_command"] = function(org)
      return errors.protect(function() return broadcast_build(org, { operation }) end)
   end
end
for _, kind in ipairs({ "event", "operation", "publisher" }) do
   local resource = kind
   M["broadcast_" .. resource .. "_get_command"] = function(org, id)
      return errors.protect(function() return broadcast_build(org, { resource, broadcast_uuid(id), "get" }) end)
   end
end
function M.broadcast_event_create_command(org, request_id, metadata_base64)
   return errors.protect(function()
      broadcast_base64(metadata_base64, 3072)
      local metadata, err = require("bibleit.http").decode_body(require("bibleit.internal.base64").unb64(metadata_base64))
      if not metadata then error(err, 0) end
      util.assert(type(metadata) == "table" and metadata ~= require("dkjson").null and not util.is_array(metadata),
         "event metadata must be a JSON object")
      return broadcast_build(org, { "event", "create", broadcast_uuid(request_id), metadata_base64 })
   end)
end
function M.broadcast_event_attach_command(org, request_id, provider_id)
   return errors.protect(function()
      util.assert(type(provider_id) == "string" and #provider_id >= 1 and #provider_id <= 128
         and provider_id:match("^[A-Za-z0-9_-]+$"), "invalid YouTube broadcast identifier")
      return broadcast_build(org, { "event", "attach", broadcast_uuid(request_id), provider_id })
   end)
end
function M.broadcast_event_transition_command(org, id, action, revision, request_id)
   return errors.protect(function()
      util.assert(action == "test" or action == "go-live" or action == "end", "unsupported broadcast transition")
      return broadcast_build(org, { "event", broadcast_uuid(id), action,
         broadcast_number(revision, 1, "9223372036854775807"), broadcast_uuid(request_id) })
   end)
end
function M.broadcast_publisher_stop_command(org, id, revision)
   return errors.protect(function() return broadcast_build(org, { "publisher", broadcast_uuid(id), "stop",
      broadcast_number(revision, 1, "9223372036854775807") }) end)
end

M.live_action = {
   info = "INFO",
   stats = "STATS",
   start = "START",
   stop = "STOP",
   pause = "PAUSE",
   resume = "RESUME",
   clear =
   "CLEAR",
   delete = "DELETE",
   subscribe = "SUBSCRIBE"
}
M.live_field = { name = "NAME", reference = "REFERENCE", translations = "TRANSLATIONS" }
M.secret_action = { authenticate = "", create = "CREATE", rotate = "ROTATE", delete = "DELETE" }
M.stack_action = { info = "INFO", clear = "CLEAR" }
return M
