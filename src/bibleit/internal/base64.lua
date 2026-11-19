-- Small bitwise-free RFC 4648 codec for protocol envelopes. This module stays
-- portable across Lua 5.1–5.5 and LuaJIT without a native transport dependency.
local M = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local values = {}
for i = 1, #alphabet do values[alphabet:sub(i,i)] = i-1 end
function M.b64(bytes)
   if type(bytes) ~= "string" then return nil end
   local result = {}
   local function char(n) return alphabet:sub(n+1,n+1) end
   for i = 1, #bytes, 3 do
      local a,b,c = bytes:byte(i,i+2); local n = a*65536+(b or 0)*256+(c or 0)
      result[#result+1] = char(math.floor(n/262144)) .. char(math.floor(n/4096)%64)
         .. (b and char(math.floor(n/64)%64) or "=") .. (c and char(n%64) or "=")
   end
   return table.concat(result)
end
function M.unb64(text)
   if type(text) ~= "string" or #text%4 ~= 0 or text:find("[^A-Za-z0-9+/=]") then return nil end
   local result = {}
   for i = 1, #text, 4 do
      local a,b,c,d = text:sub(i,i),text:sub(i+1,i+1),text:sub(i+2,i+2),text:sub(i+3,i+3)
      if not values[a] or not values[b] or c == "=" and d ~= "="
         or (c == "=" or d == "=") and i+3 ~= #text then return nil end
      local n = values[a]*262144+values[b]*4096+(values[c] or 0)*64+(values[d] or 0)
      result[#result+1] = string.char(math.floor(n/65536))
         .. (c ~= "=" and string.char(math.floor(n/256)%256) or "")
         .. (d ~= "=" and string.char(n%256) or "")
   end
   local bytes = table.concat(result)
   if M.b64(bytes) ~= text then return nil end
   return bytes
end
return M
