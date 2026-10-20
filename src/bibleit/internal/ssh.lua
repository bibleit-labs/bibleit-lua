local command = require("bibleit.command")
local protocol = require("bibleit.protocol")
local context = require("bibleit.context")
local errors = require("bibleit.errors")
local util = require("bibleit.util")
local array_mt = { __jsontype = "array" }
local M = { max_command_bytes = 8192, max_request_bytes = 16384 }
local Client = {}; Client.__index = Client
function M.new_client(executor)
   if type(executor) ~= "function" then return nil, errors.invalid("an SSH command executor is required") end
   return setmetatable({ executor = executor }, Client)
end

function Client:execute(cmd, ctx)
   if not self.executor then
      return nil,
          errors.invalid("command HTTP transport has been removed; supply an SSH executor")
   end
   if not command.is_command(cmd) then return nil, errors.invalid("a validated command is required") end
   if cmd:streaming() then return nil, errors.invalid("streaming commands require a persistent SSH subscription") end
   if #cmd:string() > 8192 then
      return nil,
          errors.new("size",
             { message = "command exceeds 8192 bytes", part = "command", bytes = #cmd:string(), limit = 8192 })
   end
   local e = context.check(ctx); if e then return nil, e end
   local response; response, e = self.executor(cmd, ctx)
   if not response then return nil, e end
   if type(response) == "string" then return protocol.decode_command_response(cmd, response) end
   return response
end

local function run(self, builder, ctx, ...)
   local cmd, e = builder(...); if not cmd then error(e, 0) end
   local result; result, e = self:execute(cmd, ctx); if not result then error(e, 0) end; return result
end
local function single(r)
   util.assert(type(r) == "table" and r.records and #r.records == 1 and r.records[1].type == "ok",
      "expected a single OK response"); return r.records[1].fields
end
local function header(r)
   util.assert(type(r) == "table" and r.records and #r.records > 0 and r.records[1].type == "ok",
      "expected an OK response"); return r.records[1].fields
end
local function required(f, k)
   util.assert(util.required(f[k]), "missing response field " .. k); return f[k]
end
local function present(f, k)
   util.assert(f[k] ~= nil, "missing response field " .. k); return f[k]
end
local function number(f, k)
   local s = f[k]; util.assert(type(s) == "string" and s:match("^%+?%d+$"), "invalid numeric response field " .. k)
   s = s:gsub("^%+", ""):gsub("^0+", ""); if s == "" then s = "0" end
   util.assert(#s < 19 or #s == 19 and s <= "9223372036854775807", "response integer exceeds int64")
   local n = tonumber(s); if n > 9007199254740991 then return s end; return n
end
local function positive(f, k)
   local n = number(f, k); util.assert(tostring(n) ~= "0", "expected positive response field " .. k); return n
end
local function boolean(f, k)
   util.assert(f[k] == "true" or f[k] == "false", "invalid boolean response field " .. k); return f[k] == "true"
end
local function list(value)
   local out = setmetatable({}, array_mt); if value and value ~= "" then
      for v in (value .. ","):gmatch("(.-),") do
         out[#out + 1] =
             v
      end
   end; return
       out
end
local function optional(f, k, reader) if f[k] ~= nil then return reader(f, k) end end
local function counted(r, key, kind)
   local f = header(r); util.assert(number(f, key) == #r.records - 1, "response count does not match records")
   for i = 2, #r.records do util.assert(r.records[i].type == kind, "unexpected response record kind") end; return f
end
local function fields(f, required_keys, number_keys, boolean_keys, optional_numbers, optional_booleans)
   local out = { fields = f }
   -- Preserve protocol fields as typed table keys; unknown fields remain in fields/raw.
   for k, v in pairs(f) do out[k] = v end
   for key in (required_keys or ""):gmatch("%S+") do out[key] = required(f, key) end
   for key in (number_keys or ""):gmatch("%S+") do out[key] = number(f, key) end
   for key in (boolean_keys or ""):gmatch("%S+") do out[key] = boolean(f, key) end
   for key in (optional_numbers or ""):gmatch("%S+") do out[key] = optional(f, key, number) end
   for key in (optional_booleans or ""):gmatch("%S+") do out[key] = optional(f, key, boolean) end
   return out
end
local function raw(builder)
   return function(self, ...)
      local args = { ... }; local ctx = args[builder.n + 1]
      return errors.protect(function()
         local unpack_args = table.unpack or unpack
         return run(self, builder.fn, ctx, unpack_args(args, 1, builder.n))
      end)
   end
end
for name, spec in pairs({ ping = { fn = command.ping_command, n = 0 }, identity = { fn = command.identity_command, n = 0 }, list_translations = { fn = command.translation_list_command, n = 0 }, read = { fn = command.read_command, n = 1 }, search = { fn = command.search_command, n = 2 } }) do
   Client[name] =
       raw(spec)
end
function Client:get_server_info(ctx)
   return errors.protect(function()
      local r = run(self, command.server_info_command, ctx); local f = single(r)
      return {
         raw = r,
         protocol_version = number(f, "protocol_version"),
         version = required(f, "version"),
         capabilities =
             list(f.capabilities)
      }
   end)
end

function Client:help(topic, ctx)
   return errors.protect(function()
      local r = run(self, command.help_command, ctx, topic); local f = counted(r, "commands", "command"); local out = {
         raw =
             r,
         authenticated = boolean(f, "auth"),
         commands = setmetatable({}, array_mt)
      }
      for i = 2, #r.records do
         local x = fields(r.records[i].fields, "usage summary"); x.auth = x.auth or "none"; out.commands[#out.commands + 1] =
             x
      end; return out
   end)
end

function Client:get_account_info(ctx)
   return errors.protect(function()
      local r = run(self, command.account_info_command, ctx); local out = fields(single(r), "actor plan plan_source",
         "lives translations tokens keys plan_activated_at"); out.raw = r; return out
   end)
end

function Client:list_quotas(ctx)
   return errors.protect(function()
      local r = run(self, command.account_quotas_command, ctx); counted(r, "count", "quota"); local out = {
         raw = r,
         quotas =
             setmetatable({}, array_mt)
      }
      for i = 2, #r.records do
         local f = r.records[i].fields; local x = fields(f, "permission", "used")
         x.limit = { unlimited = f.limit == "unlimited", value = f.limit == "unlimited" and 0 or number(f, "limit") }; out.quotas[#out.quotas + 1] =
             x
      end; return out
   end)
end

function Client:get_identity(ctx)
   return errors.protect(function()
      local r = run(self, command.identity_command, ctx); local f = single(r); local out = fields(f, "actor", nil, "auth")
      out.authenticated = out.auth; out.auth = nil; out.roles = list(f.roles); out.permissions = list(f.permissions); out.raw =
          r; return out
   end)
end

local function verse_text(f)
   local out = fields(f); out.text = present(f, "text"); local n = 0
   for _, k in ipairs({ "book", "chapter", "verse" }) do
      if f[k] ~= nil then
         out[k] = positive(f, k); n = n + 1
      end
   end
   util.assert(n == 0 or n == 3, "incomplete verse coordinates"); out.book_id = out.book; out.book = nil; return out
end
local function reading(r, search)
   local f = header(r); local out = {
      translation = required(f, "translation"),
      raw = r,
      verses = setmetatable({},
         array_mt)
   }
   for _, k in ipairs({ "book", "chapter", "verse" }) do if f[k] ~= nil then out[k] = positive(f, k) end end
   util.assert(search or out.book ~= nil, "missing response field book")
   if not search and out.verse then
      util.assert(out.chapter ~= nil, "verse reply requires chapter"); out.verses[1] = verse_text(single(r)); return out
   end
   counted(r, search and "results" or "verses", "verse")
   for i = 2, #r.records do out.verses[#out.verses + 1] = verse_text(r.records[i].fields) end; return out
end
function Client:read_verses(ref, ctx)
   return errors.protect(function()
      return reading(
         run(self, command.read_command, ctx, ref), false)
   end)
end

function Client:search_verses(translation, query, ctx)
   return errors.protect(function()
      return reading(
         run(self, command.search_command, ctx, translation, query), true)
   end)
end

function Client:get_translation_info(slug, ctx)
   return errors.protect(function()
      local r = run(self, command.translation_info_command, ctx, slug); local out = fields(single(r),
         "short_name full_name"); out.raw = r; return out
   end)
end

function Client:get_translation_catalog(slug, ctx)
   return errors.protect(function()
      local r = run(self, command.translation_catalog_command, ctx, slug); local f = header(r)
      local out = { raw = r, translation = required(f, "translation"), books = setmetatable({}, array_mt) }
      local book, expected, seen_books, seen_chapters = nil, nil, {}, {}
      local function finish() if book then util.assert(#book.chapters == expected, "catalogue chapter count mismatch") end end
      for i = 2, #r.records do
         local record = r.records[i]; f = record.fields; local id = positive(f, "book")
         if record.type == "book" then
            finish(); util.assert(not seen_books[tostring(id)], "duplicate catalogue book"); seen_books[tostring(id)] = true
            expected = number(f, "chapters"); book = {
               id = id,
               name = required(f, "name"),
               chapters = setmetatable({}, array_mt),
               fields =
                   f
            }; out.books[#out.books + 1] = book; seen_chapters = {}
         elseif record.type == "chapter" then
            util.assert(book and tostring(book.id) == tostring(id), "catalogue chapter does not belong to current book")
            local chapter = positive(f, "chapter"); util.assert(not seen_chapters[tostring(chapter)],
               "duplicate catalogue chapter"); seen_chapters[tostring(chapter)] = true
            book.chapters[#book.chapters + 1] = { number = chapter, verses = positive(f, "verses"), fields = f }
         else
            errors.raise("unexpected catalogue record")
         end
      end
      finish(); util.assert(#out.books == number(header(r), "books"), "catalogue book count mismatch"); return out
   end)
end

function Client:list_tokens(ctx)
   return errors.protect(function()
      local r = run(self, command.account_tokens_command, ctx); local f = counted(r, "count", "token"); local out = {
         raw =
             r,
         actor = required(f, "actor"),
         tokens = setmetatable({}, array_mt)
      }; local seen = {}
      for i = 2, #r.records do
         f = r.records[i].fields; local x = fields(f, "id source", "issued_at", nil, "last_used_at expires_at",
            "retiring")
         util.assert(not seen[x.id], "duplicate token id"); seen[x.id] = true; if f.scopes ~= nil then
            x.scopes = list(f
               .scopes)
         end; out.tokens[#out.tokens + 1] = x
      end; return out
   end)
end

local function organization_entry(kind, f)
   local keys = kind == "application" and "application_id name domain state next_action verification_url" or
       "id handle name role verification status"
   local out = fields(f, keys); out.kind = kind; return out
end
function Client:list_organizations(cursor, ctx)
   return errors.protect(function()
      local r = run(self, command.organization_list_command, ctx, cursor); local f = header(r)
      util.assert(number(f, "count") == #r.records - 1, "directory count mismatch"); local out = {
         raw = r,
         next = f
             .next,
         entries = setmetatable({}, array_mt)
      }
      for i = 2, #r.records do
         local rec = r.records[i]; util.assert(rec.type == "application" or rec.type == "organization",
            "unexpected directory record"); out.entries[#out.entries + 1] = organization_entry(rec.type, rec.fields)
      end; return out
   end)
end

function Client:get_organization_application_status(id, ctx)
   return errors.protect(function()
      local r = run(self, command.organization_application_status_command, ctx, id); return {
         raw = r,
         application =
             organization_entry("application", single(r))
      }
   end)
end

local function live_state(f)
   local out = fields(f, "id status", nil, "paused", "created_at", "owned protected"); out.name = present(f, "name"); out.translations =
       list(f.translations); return out
end
local function live_result(r) return { raw = r, live = live_state(single(r)) } end
function Client:create_live(name, ctx)
   return errors.protect(function()
      return live_result(run(self,
         command.create_live_command, ctx, name))
   end)
end

function Client:get_live(id, ctx)
   return errors.protect(function()
      return live_result(run(self, command.live_command, ctx,
         id, "INFO"))
   end)
end

-- Values are a list; ctx is last so variadic values cannot consume it.
function Client:set_live(id, field, values, ctx)
   return errors.protect(function()
      util.assert(type(values) == "table", "values must be an array")
      local function builder() return command.set_live_command(id, field, (table.unpack or unpack)(values)) end
      return live_result(run(self, builder, ctx))
   end)
end

function Client:list_lives(ctx)
   return errors.protect(function()
      local r = run(self, command.live_list_command, ctx); counted(r, "count", "live"); local out = {
         raw = r,
         lives =
             setmetatable({}, array_mt)
      }; local seen = {}
      for i = 2, #r.records do
         local x = live_state(r.records[i].fields); util.assert(not seen[x.id], "duplicate Live id"); seen[x.id] = true; out.lives[#out.lives + 1] =
             x
      end; return out
   end)
end

function Client:get_live_stats(id, ctx)
   return errors.protect(function()
      local r = run(self, command.live_command, ctx, id, "STATS"); local f = counted(r, "connections", "connection")
      local out = fields(f, "id", "running_for_seconds revision stack_entries actor_connections anonymous_connections"); out.raw =
          r; out.connections = setmetatable({}, array_mt)
      util.assert(
         type(out.actor_connections) == "number" and type(out.anonymous_connections) == "number" and
         out.actor_connections + out.anonymous_connections == #r.records - 1, "inconsistent Live connection totals")
      for i = 2, #r.records do
         out.connections[#out.connections + 1] = fields(r.records[i].fields, "actor access",
            "connected_at connected_for_seconds")
      end; return out
   end)
end

local function live_verse(f)
   local out = fields(f, "translation"); out.text = present(f, "text"); return out
end
function Client:get_live_stack(id, ctx)
   return errors.protect(function()
      local r = run(self, command.live_stack_command, ctx, id, "INFO"); local f = counted(r, "count", "stack"); local out = {
         raw =
             r,
         id = required(f, "id"),
         entries = setmetatable({}, array_mt)
      }
      for i = 2, #r.records do
         f = r.records[i].fields; local x = live_verse(f); x.position = positive(f, "position"); util.assert(
            x.position == i - 1, "invalid stack position"); out.entries[#out.entries + 1] = x
      end; return out
   end)
end

local function live_verses(r)
   local f = header(r); local out = { raw = r, event = f.event, verses = setmetatable({}, array_mt) }
   if out.event == "clear" then
      single(r); return out
   end
   util.assert(out.event == "verse", "expected Live verse or clear event"); counted(r, "translations", "verse")
   for i = 2, #r.records do out.verses[#out.verses + 1] = live_verse(r.records[i].fields) end; return out
end
function Client:push_live(id, ref, ctx)
   return errors.protect(function()
      return live_verses(run(self,
         command.push_live_command, ctx, id, ref))
   end)
end

function Client:pop_live(id, count, ctx)
   return errors.protect(function()
      return live_verses(run(self,
         command.pop_live_command, ctx, id, count))
   end)
end

function Client:control_live(id, action, ctx)
   return errors.protect(function()
      util.assert(
         action == "START" or action == "STOP" or action == "PAUSE" or action == "RESUME" or action == "CLEAR" or
         action == "DELETE", "unsupported Live control action")
      local r = run(self, command.live_command, ctx, id, action); local f = single(r); local out = { raw = r }
      if action == "START" or action == "STOP" then
         out.state = live_state(f)
      elseif action == "PAUSE" or action == "RESUME" then
         out.paused = boolean(f, "paused")
      else
         local expected = action == "CLEAR" and "clear" or "deleted"; util.assert(f.event == expected,
            "unexpected Live control event"); out.event = expected
      end; return out
   end)
end

return M
