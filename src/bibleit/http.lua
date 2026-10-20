local json = require("dkjson")
local errors = require("bibleit.errors")
local context = require("bibleit.context")
local utf8 = require("bibleit.internal.utf8")
local M = {}

-- Translate the library's position/error returns at the HTTP decoding boundary.
function M.decode_body(data)
   if type(data) ~= "string" or not utf8.valid_utf8(data) then return nil, errors.invalid("invalid JSON response") end
   local ok, value, pos, err = pcall(json.decode, data, 1, json.null)
   if not ok then return nil, errors.invalid(tostring(value)) end
   if err then return nil, errors.invalid(err) end
   if not data:sub(pos):match("^[ \t\r\n]*$") then return nil, errors.invalid("trailing JSON response data") end
   return value
end

local Response = {}; Response.__index = Response
function M.string_body(value)
   local pos, closed = 1, false
   return {
      read = function(_, n)
         if closed then return nil, errors.invalid("body is closed") end
         if pos > #value then return nil end
         n = n or 16384; local s = value:sub(pos, pos + n - 1); pos = pos + #s; return s
      end,
      close = function()
         closed = true; return true
      end,
   }
end

function M.response(status, headers, body)
   local normalized = {}
   for k, v in pairs(headers or {}) do normalized[k:lower()] = v end
   if type(body) == "string" or body == nil then body = M.string_body(body or "") end
   return setmetatable({ status_code = status, headers = normalized, body = body }, Response)
end

function Response:close()
   if self.closed then return true end
   self.closed = true
   return self.body:close()
end

function Response:read(n) return self.body:read(n) end

function M.read_all(body, limit)
   local chunks, size = {}, 0
   while true do
      local chunk, err = body:read(math.min(16384, limit + 1 - size))
      if err then return nil, err end
      if chunk == nil then return table.concat(chunks) end
      if type(chunk) ~= "string" or #chunk == 0 then return nil, errors.invalid("body reader made no progress") end
      size = size + #chunk
      if size > limit then return nil, errors.new("size", { message = "response exceeds byte limit", limit = limit }) end
      chunks[#chunks + 1] = chunk
   end
end

function Response:decode()
   local data, err = M.read_all(self.body, 4194304)
   if not data then return nil, err end
   return M.decode_body(data)
end

function M.send(transport, req, ctx)
   local err = context.check(ctx); if err then return nil, err end
   local response
   if type(transport) == "function" then
      response, err = transport(req, ctx)
   else
      response, err = transport:request(req, ctx)
   end
   if not response then return nil, err or errors.new("transport", { message = "transport returned no response" }) end
   if type(response.status_code) ~= "number" then
      if response.close then response:close() end
      return nil, errors.invalid("transport returned an invalid status")
   end
   response = M.response(response.status_code, response.headers, response.body)
   err = context.check(ctx)
   if err then
      response:close(); return nil, err
   end
   return response
end

function M.transport(supplied, timeout)
   if supplied then
      if type(supplied) ~= "function" and (type(supplied) ~= "table" or type(supplied.request) ~= "function") then
         return nil, errors.invalid("transport must be a request function or object")
      end
      return supplied
   end
   return require("bibleit.transport").new({ timeout = timeout })
end

return M
