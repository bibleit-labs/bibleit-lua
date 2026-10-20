local vm = _VERSION:match("%d+%.%d+")
package.path = "./lua_modules/share/lua/" ..
    vm .. "/?.lua;./lua_modules/share/lua/" .. vm .. "/?/init.lua;" .. package.path
package.cpath = "./lua_modules/lib/lua/" .. vm .. "/?.so;" .. package.cpath
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path
local socket, lu = require("socket"), require("luaunit")
local bibleit = require("bibleit")
local http = require("bibleit.http")
local original_tcp = socket.tcp
local target_port
-- Test-only routing; the production transport still validates its pinned host.
socket.tcp = function()
   local raw = assert(original_tcp())
   return setmetatable({}, {
      __index = function(_, key)
         if key == "connect" then return function() return raw:connect("127.0.0.1", target_port) end end
         return function(_, ...) return raw[key](raw, ...) end
      end
   })
end
local transport = assert(bibleit.transport.new({ cafile = arg[2] }))
local function request(t, path, body, length, ctx)
   return http.send(t, {
      url = "https://api.bibleit.app/v1/" .. path,
      method = body and "POST" or "GET",
      headers = { Accept = "application/json" },
      body = body,
      content_length = length
   }, ctx)
end
TestTransport = {}
function TestTransport:setUp()
   target_port = tonumber(arg[1]); self.response = nil
end

function TestTransport:tearDown() if self.response then self.response:close() end end

function TestTransport:testContentLengthStreaming()
   self.response = assert(request(transport, "length"))
   lu.assertEquals(self.response:read(2), "he"); lu.assertEquals(self.response:read(3), "llo")
   lu.assertNil(self.response:read())
end

function TestTransport:testChunkedStreaming()
   self.response = assert(request(transport, "chunked")); lu.assertEquals(http.read_all(self.response.body, 100), "hello")
end

function TestTransport:testConnectionCloseStreaming()
   self.response = assert(request(transport, "close")); lu.assertEquals(http.read_all(self.response.body, 100), "hello")
end

function TestTransport:testRedirectIsReturned()
   self.response = assert(request(transport, "redirect")); lu.assertEquals(self.response.status_code, 302)
end

function TestTransport:testUpload()
   self.response = assert(request(transport, "upload", http.string_body("hello"), 5))
   lu.assertEquals(self.response:decode().received, 5)
end

function TestTransport.testAmbiguousFramingIsRejected()
   lu.assertNil(request(transport, "ambiguous")); lu.assertNil(request(transport, "duplicate"))
end

function TestTransport.testUntrustedCertificateIsRejected()
   lu.assertNil(request(assert(bibleit.transport.new()), "length"))
end

function TestTransport.testCancellationAndTimeout()
   local ctx = bibleit.context.new(); ctx:cancel(); lu.assertNil(request(transport, "length", nil, nil, ctx))
   lu.assertNil(request(assert(bibleit.transport.new({ cafile = arg[2], timeout = 0.01 })), "slow"))
end

function TestTransport.testWrongHostnameIsRejected()
   target_port = tonumber(arg[3]); lu.assertNil(request(assert(bibleit.transport.new({ cafile = arg[4] })), "length"))
end

os.exit(lu.LuaUnit.run("TestTransport"))
