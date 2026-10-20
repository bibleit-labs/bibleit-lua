local M = {}
local mt = {}
mt.__index = mt
function mt:__tostring()
   if self.kind == "server" then return self.code end
   if self.kind == "oauth" then return "Bibleit OAuth: " .. (self.code or "") end
   if self.kind == "problem" then return "Bibleit REST HTTP " .. self.status .. ": " .. (self.code or "") end
   if self.kind == "http" then return "Bibleit HTTP " .. self.status .. (self.code and ": " .. self.code or "") end
   return self.message or self.code or "Bibleit request failed"
end

-- All durations exposed by the Lua API are in seconds.
function mt:retry_after()
   local value = self.kind == "server" and self.fields and self.fields.retry_after_ms
       or self.headers and self.headers["retry-after"]
   local n = tonumber(value)
   if not n or n < 0 or n == math.huge then return 0 end
   if self.kind == "server" then
      if not tostring(value):match("^%+?%d+$") or n > 9223372036854 then return 0 end
      return n / 1000
   end
   return n
end

function M.new(kind, fields)
   fields = fields or {}
   if fields.code ~= nil and type(fields.code) ~= "string" then fields.code = "" end
   fields.kind = kind
   return setmetatable(fields, mt)
end

function M.invalid(message) return M.new("validation", { message = message }) end

function M.protect(fn, ...)
   local ok, value, err = pcall(fn, ...)
   if ok then return value, err end
   if getmetatable(value) == mt then return nil, value end
   error(value, 0)
end

function M.raise(message) error(M.invalid(message), 0) end

return M
