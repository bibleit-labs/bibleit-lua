local json = require("dkjson")
local errors = require("bibleit.errors")
local M = {}
function M.is_array(v)
   if type(v) ~= "table" then return false end
   local mt = getmetatable(v)
   if mt and mt.__jsontype then return mt.__jsontype == "array" end
   return #v > 0
end

-- Compare decoded metadata independently of JSON object key order.
function M.equal(a, b, seen)
   if a == b then return true end
   if type(a) ~= "table" or type(b) ~= "table" or a == json.null or b == json.null then return false end
   if M.is_array(a) ~= M.is_array(b) then return false end
   seen = seen or {}
   if seen[a] then return seen[a] == b end
   seen[a] = b
   for key, value in pairs(a) do if not M.equal(value, b[key], seen) then return false end end
   for key in pairs(b) do if a[key] == nil then return false end end
   return true
end

function M.copy(v, seen)
   if type(v) ~= "table" or v == json.null then return v end
   seen = seen or {}; if seen[v] then return seen[v] end
   local out = setmetatable({}, getmetatable(v)); seen[v] = out
   for k, x in pairs(v) do out[k] = M.copy(x, seen) end
   return out
end

function M.snake(s) return (s:gsub("(%u)(%u%l)", "%1_%2"):gsub("(%l)(%u)", "%1_%2"):lower()) end

function M.escape(s, form)
   local value = tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)
   if form then value = value:gsub("%%20", "+") end
   return value
end

function M.query(q)
   local keys, out = {}, {}
   for k in pairs(q or {}) do keys[#keys + 1] = k end
   table.sort(keys)
   for _, k in ipairs(keys) do
      local values = type(q[k]) == "table" and q[k] or { q[k] }
      for _, v in ipairs(values) do out[#out + 1] = M.escape(k, true) .. "=" .. M.escape(v, true) end
   end
   return table.concat(out, "&")
end

function M.integer(v, min, max)
   return type(v) == "number" and v % 1 == 0 and v >= (min or 0) and v <= (max or 9007199254740991)
end

function M.header(v)
   return type(v) == "string" and not v:find("[%z\1-\8\10-\31\127]")
end

function M.required(s) return type(s) == "string" and s ~= "" end

function M.assert(ok, message) if not ok then errors.raise(message) end end

return M
