local lu = require("luaunit")
local socket
local interpreter = arg[-1] or "lua"
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function command(args)
   local out = {}; for i, value in ipairs(args) do out[i] = quote(value) end; return table.concat(out, " ")
end
local function execute(cmd)
   local status = os.execute(cmd); lu.assertTrue(status == true or status == 0, "fixture command failed")
end
TestHTTPS = {}
function TestHTTPS:setUp()
   self.servers = {}
   socket = require("socket")
   local pipe = assert(io.popen("mktemp -d")); self.directory = assert(pipe:read("*l")); pipe:close()
end

function TestHTTPS:tearDown()
   for _, server in ipairs(self.servers) do os.execute("kill " .. server.pid .. " 2>/dev/null") end
   if self.directory then os.execute("rm -rf " .. quote(self.directory)) end
end

function TestHTTPS:testTransportAgainstDisposableCertificates()
   for _, entry in ipairs({ { "good", "api.bibleit.app" }, { "wrong", "example.invalid" } }) do
      local base = self.directory .. "/" .. entry[1]
      execute(command({ "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=" ..
         entry[2],
            "-addext", "subjectAltName=DNS:" .. entry[2], "-keyout", base .. ".key", "-out", base .. ".pem" }) ..
         " >/dev/null 2>&1")
      local pipe = assert(io.popen(command({ interpreter, "tests/tls-server.lua", base .. ".pem", base .. ".key", base ..
      ".port" }) .. " >" .. quote(base .. ".log") .. " 2>&1 & echo $!"))
      local server = { cert = base .. ".pem", pid = assert(pipe:read("*l")):match("^%d+$") }; pipe:close()
      lu.assertNotNil(server.pid); self.servers[#self.servers + 1] = server
      local deadline = socket.gettime() + 10
      repeat
         local file = io.open(base .. ".port")
         if file then
            server.port = file:read("*a"); file:close()
         else
            socket.sleep(0.02)
         end
      until server.port or socket.gettime() > deadline
      lu.assertNotNil(server.port, "TLS fixture did not start")
   end
   execute(command({ interpreter, "tests/transport_test.lua", self.servers[1].port, self.servers[1].cert,
      self.servers[2].port, self.servers[2].cert }))
end

return TestHTTPS
