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
   local topics = { ROOT = true, SERVER = true, ACCOUNT = true, AUTH = true, TRANSLATION = true, LIVE = true, ORGANIZATION = true }
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
