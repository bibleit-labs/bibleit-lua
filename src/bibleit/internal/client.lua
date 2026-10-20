local errors = require("bibleit.errors")
local util = require("bibleit.util")
local json = require("dkjson")
local http = require("bibleit.http")
local context = require("bibleit.context")
local operations = require("bibleit.internal.operations_generated")
local ENDPOINT = "https://api.bibleit.app/v1"
local M = { endpoint = ENDPOINT }
local Client = {}; Client.__index = Client
local credentials = setmetatable({}, { __mode = "k" })
function M.new_client(token, transport)
   token = token or ""
   if type(token) ~= "string" or token:find("[%z\r\n]") or token:match("^%s") or token:match("%s$") then
      return nil,
          errors.invalid("invalid bearer token")
   end
   local t, e = http.transport(transport, 40); if not t then return nil, e end
   local client = setmetatable({ transport = t }, Client); credentials[client] = token; return client
end

function M.operations() return util.copy(operations) end

function M.operation_names()
   local names = {}; for name in pairs(operations) do names[#names + 1] = name end; table.sort(names); return names
end

function Client:call(name, params, options, ctx)
   return errors.protect(function()
      local op = operations[name]; util.assert(op, "unknown REST operation")
      params = params or {}; options = options or {}; local path = op.path
      for k, v in pairs(params) do
         util.assert(
            type(k) == "string" and type(v) == "string" and v ~= "" and v ~= "." and v ~= ".." and
            not v:find("[/\\%z\r\n]"),
            "invalid path parameter")
         util.assert(path:find("{" .. k .. "}", 1, true), "unexpected path parameter")
      end
      path = path:gsub("{([^}]+)}",
         function(k)
            util.assert(params[k], "missing path parameter"); return util.escape(params[k])
         end)
      util.assert(not (options.json ~= nil and options.body ~= nil), "JSON and raw body are mutually exclusive")
      local body = options.body
      local content_type = options.content_type
      local length = options.content_length
      if options.json ~= nil then
         local ok; ok, body = pcall(json.encode, options.json); if not ok then errors.raise(tostring(body)) end
         content_type = content_type or "application/json"; length = #body
      elseif body ~= nil then
         util.assert(type(body) == "string" or type(body) == "table" and type(body.read) == "function",
            "invalid raw body")
         util.assert(util.integer(length), "raw body requires an exact nonnegative content_length")
         if type(body) == "string" then util.assert(#body == length, "upload length mismatch") end
      end
      local query = util.query(options.query)
      local headers = { Accept = "application/json" }
      if credentials[self] ~= "" then headers.Authorization = "Bearer " .. credentials[self] end
      local values = {
         ["Content-Type"] = content_type,
         ["If-Match"] = options.if_match,
         ["Idempotency-Key"] = options.idempotency_key,
         ["X-Destination-Service-Token"] = options.destination_token,
         ["Range"] = options.range
      }
      for k, v in pairs(values) do
         if v ~= "" then
            util.assert(util.header(v), "invalid HTTP header value"); headers[k] = v
         end
      end
      local response, e = http.send(self.transport,
         {
            method = op.method,
            url = ENDPOINT .. path .. (query ~= "" and "?" .. query or ""),
            headers = headers,
            body =
                body,
            content_length = length
         }, ctx)
      if not response then return nil, e end
      if response.status_code < 200 or response.status_code >= 300 then
         local data, read_err = http.read_all(response.body, 4194304); response:close()
         if read_err then return nil, read_err end
         local problem = http.decode_body(data)
         if type(problem) ~= "table" or problem == json.null then problem = {} end
         problem.status = response.status_code; problem.headers = util.copy(response.headers)
         problem.request_id = problem.request_id or response.headers["x-request-id"]
         return nil, errors.new("problem", problem)
      end
      return response
   end)
end

for name, op in pairs(operations) do
   local id, params = name, op.parameters
   Client[util.snake(id)] = function(self, ...)
      local args = { ... }; local values = {}
      for i, key in ipairs(params) do values[key] = args[i] end
      return self:call(id, values, args[#params + 1], args[#params + 2])
   end
end
Client.get_open_api = Client.get_open_api or Client.get_open_a_p_i
function Client:poll_live_events(id, after, wait, ctx)
   if not util.integer(wait, 0, 25) then return nil, errors.invalid("event wait must be between 0 and 25 seconds") end
   local q = { wait = tostring(wait) }; if after and after ~= "" then q.after = after end
   local res, e = self:get_live_events(id, { query = q }, ctx); if not res then return nil, e end
   local event; event, e = res:decode(); local _, close_err = res:close(); if not event then return nil, e end; if close_err then
      return
          nil, close_err
   end
   if type(event) ~= "table" or event == json.null or event.schema_version ~= 1 then
      return nil,
          errors.invalid("unsupported Live event schema version")
   end
   if event.type ~= "live.snapshot" and event.type ~= "live.changed" and event.type ~= "stream.heartbeat" then
      return nil,
          errors.invalid("unsupported Live event type")
   end
   if event.resource_type ~= "live" or event.resource_id ~= id or not util.required(event.cursor) then
      return nil,
          errors.invalid("invalid Live event resource or cursor")
   end
   local empty = event.data == nil or event.data == json.null
   if (event.type == "stream.heartbeat") ~= empty or not empty and type(event.data) ~= "table" then
      return nil,
          errors.invalid("invalid Live event data")
   end
   return event
end

local function one(v)
   if type(v) == "table" then
      if #v ~= 1 then return nil end; return v[1]
   end
   return v
end
local function book_pages(self, operation, params, options, ctx)
   local opts = util.copy(options or {}); opts.query = opts.query or {}; if opts.query.limit == nil then
      opts.query.limit =
      "50"
   end
   local seen, done = {}, false
   local initial = one(opts.query.after); if initial then seen[initial] = true end
   local first_translation, first_rights, previous
   return function()
      if done then return nil end
      local page, e = errors.protect(function()
         local ce = context.check(ctx); if ce then error(ce, 0) end
         local limit = one(opts.query.limit)
         util.assert(type(limit) == "string" and limit:match("^%+?%d+$") and util.integer(tonumber(limit), 1, 500),
            "book page limit must be an integer between 1 and 500")
         limit = tonumber(limit)
         util.assert(opts.query.after == nil or util.required(one(opts.query.after)),
            "book page after must be a single nonempty cursor")
         local response, err = self:call(operation, params, opts, ctx)
         if not response then return nil, err end
         local p; p, err = response:decode(); local _, close_err = response:close()
         if not p then return nil, err end; if close_err then return nil, close_err end
         local function valid(ok)
            if not ok then
               error(
                  errors.new("invalid_book_page", { message = "invalid REST book page" }), 0)
            end
         end
         valid(type(p) == "table" and p ~= json.null and util.is_array(p.verses) and util.required(p.translation) and
            type(p.rights) == "table" and p.rights ~= json.null)
         local next_cursor = p.next_cursor
         valid(next_cursor == json.null or util.required(next_cursor))
         valid(#p.verses <= limit and (next_cursor == json.null or #p.verses > 0))
         local rights = util.copy(p.rights)
         if first_translation then
            valid(first_translation == p.translation and util.equal(first_rights, rights))
         else
            first_translation, first_rights = p.translation, rights
         end
         for _, verse in ipairs(p.verses) do
            valid(type(verse) == "table" and util.integer(verse.book_id, 1, 255) and util.integer(verse.chapter, 1, 152) and
               util.integer(verse.verse, 1, 255))
            if previous then
               valid(verse.book_id == previous.book_id and
                  (verse.chapter > previous.chapter or verse.chapter == previous.chapter and verse.verse > previous.verse))
            end
            previous = verse
         end
         if next_cursor ~= json.null then
            valid(not seen[next_cursor]); seen[next_cursor] = true; opts.query.after = next_cursor
         else
            done = true
         end
         return p
      end)
      if e then
         done = true; return nil, e
      end
      return page
   end
end
function Client:read_personal_book_pages(account_id, slug, book_id, options, ctx)
   return book_pages(self, "readPersonalBook", { account_id = account_id, slug = slug, book_id = book_id }, options, ctx)
end

function Client:read_book_pages(organization_id, slug, book_id, options, ctx)
   return book_pages(self, "readBook", { organization_id = organization_id, slug = slug, book_id = book_id }, options,
      ctx)
end

function Client:revoke_credential(ctx)
   return require("bibleit.internal.auth").revoke_credential(credentials[self], self.transport, ctx)
end

return M
