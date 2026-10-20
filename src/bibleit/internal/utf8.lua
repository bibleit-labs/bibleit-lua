local M = {}
function M.utf8(n)
   if n < 128 then return string.char(n) end
   if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
   if n < 65536 then return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64) end
   return string.char(240 + math.floor(n / 262144), 128 + math.floor(n / 4096) % 64, 128 + math.floor(n / 64) % 64,
      128 + n % 64)
end

function M.valid_utf8(s)
   local i = 1
   while i <= #s do
      local b = s:byte(i)
      local len, n, min = 1, b, 0
      if b >= 194 and b <= 223 then
         len, n, min = 2, b - 192, 128
      elseif b >= 224 and b <= 239 then
         len, n, min = 3, b - 224, 2048
      elseif b >= 240 and b <= 244 then
         len, n, min = 4, b - 240, 65536
      elseif b >= 128 then
         return false
      end
      for j = 1, len - 1 do
         local c = s:byte(i + j)
         if not c or c < 128 or c > 191 then return false end
         n = n * 64 + c - 128
      end
      if n < min or n > 1114111 or (n >= 55296 and n <= 57343) then return false end
      i = i + len
   end
   return true
end

return M
