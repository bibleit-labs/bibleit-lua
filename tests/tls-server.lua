local vm = _VERSION:match("%d+%.%d+")
package.path = "./lua_modules/share/lua/" ..
    vm .. "/?.lua;./lua_modules/share/lua/" .. vm .. "/?/init.lua;" .. package.path
package.cpath = "./lua_modules/lib/lua/" .. vm .. "/?.so;" .. package.cpath
-- Disposable loopback fixture, started and stopped by tests/https.lua.
local socket, ssl = require("socket"), require("ssl")
local listener = assert(socket.bind("127.0.0.1", 0))
local _, port = listener:getsockname(); local ready = assert(io.open(arg[3], "w")); ready:write(tostring(port)); ready
    :close()
while true do
   local raw = assert(listener:accept()); raw:settimeout(2)
   local connection = assert(ssl.wrap(raw, { mode = "server", protocol = "any", certificate = arg[1], key = arg[2] }))
   connection:settimeout(2)
   if connection:dohandshake() then
      pcall(function()
         local line = assert(connection:receive("*l"))
         local path = assert(line:match("^%S+%s+(%S+)")):match("([^/]+)$")
         local headers = {}
         while true do
            line = assert(connection:receive("*l"))
            if line == "" then break end
            local name, value = line:match("^([^:]+):%s*(.*)$"); headers[name:lower()] = value
         end
         local length = tonumber(headers["content-length"]) or 0
         if length > 0 then assert(connection:receive(length)) end
         if path == "slow" then socket.sleep(0.1) end
         local outputs = {
            chunked = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhe\r\n3\r\nllo\r\n0\r\n\r\n",
            close = "HTTP/1.1 200 OK\r\n\r\nhello",
            redirect = "HTTP/1.1 302 Found\r\nLocation: https://example.invalid\r\nContent-Length: 0\r\n\r\n",
            ambiguous = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n",
            duplicate = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n",
         }
         local result = outputs[path] or "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello"
         if path == "upload" then
            local body = '{"received":' .. length .. "}"
            result = "HTTP/1.1 200 OK\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body
         end
         assert(connection:send(result))
      end)
   end
   connection:close()
end
