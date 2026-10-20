-- Synchronous HTTP/1.1 over verified TLS. No redirects, cookies or retries.
local errors = require("bibleit.errors")
local context = require("bibleit.context")
local util = require("bibleit.util")
local M = {}
local Transport = {}; Transport.__index = Transport
function M.matches_hostname(cert, host)
   local ext = cert:extensions()
   local san = ext and ext["2.5.29.17"]
   for _, dns_name in ipairs(san and san.dNSName or {}) do
      local name = dns_name
      name = name:lower()
      if not name:find("%z") and (name == host or (name:sub(1, 2) == "*." and host:match("^[^.]+%.(.+)$") == name:sub(3))) then return true end
   end
   return false
end

function M.new(options)
   options = options or {}
   if options.timeout and (type(options.timeout) ~= "number" or options.timeout <= 0) then
      return nil,
          errors.invalid("timeout must be positive")
   end
   return setmetatable({ timeout = options.timeout or 40, cafile = options.cafile, capath = options.capath }, Transport)
end

local function ca_file()
   for _, path in ipairs({ "/etc/ssl/cert.pem", "/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt" }) do
      local f = io.open(path, "r"); if f then
         f:close(); return path
      end
   end
end
function Transport:request(req, ctx)
   local socket = require("socket")
   local ssl = require("ssl")
   local conn
   local result, err = errors.protect(function()
      local host, path = req.url:match("^https://([^/]+)(/.*)$")
      util.assert(host == "api.bibleit.app" or host == "bibleit.app", "transport origin is not allowed")
      util.assert(not path:find("[%z\r\n ]"), "invalid request path")
      local until_time = socket.gettime() + self.timeout
      local function ready()
         local e = context.check(ctx); if e then error(e, 0) end
         local remaining = until_time - socket.gettime()
         if ctx and ctx.deadline then remaining = math.min(remaining, ctx.deadline - ctx.clock()) end
         if remaining <= 0 then error(errors.new("deadline", { message = "request deadline exceeded" }), 0) end
         conn:settimeout(remaining)
      end
      local function io_check(value)
         if not value then error(errors.new("transport", { message = "TLS or network I/O failed" }), 0) end
         return value
      end
      conn = io_check(socket.tcp()); ready(); io_check(conn:connect(host, 443))
      local raw = conn
      local wrapped = ssl.wrap(raw, {
         mode = "client",
         protocol = "any",
         verify = "peer",
         options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1", "no_tlsv1_1" },
         cafile = self.cafile or ca_file(),
         capath = self.capath
      })
      if not wrapped then
         raw:close(); io_check(nil)
      end
      conn = wrapped; ready(); conn:sni(host); io_check(conn:dohandshake())
      local cert = conn:getpeercertificate()
      util.assert(cert and M.matches_hostname(cert, host), "TLS certificate hostname mismatch")
      local function send(data)
         local index = 1
         while index <= #data do
            ready(); local n = conn:send(data, index); index = io_check(n) + 1
         end
      end
      local headers = { "Host: " .. host, "Connection: close", "Accept-Encoding: identity" }
      for k, v in pairs(req.headers or {}) do
         util.assert(k:match("^[%w%-]+$") and util.header(v), "invalid HTTP header")
         util.assert(
            k:lower() ~= "host" and k:lower() ~= "connection" and k:lower() ~= "transfer-encoding" and
            k:lower() ~= "content-length" and k:lower() ~= "accept-encoding",
            "reserved HTTP header")
         headers[#headers + 1] = k .. ": " .. v
      end
      local length = req.content_length or 0
      util.assert(util.integer(length), "invalid content length")
      headers[#headers + 1] = "Content-Length: " .. string.format("%.0f", length)
      send(req.method .. " " .. path .. " HTTP/1.1\r\n" .. table.concat(headers, "\r\n") .. "\r\n\r\n")
      if req.body then
         if type(req.body) == "string" then
            util.assert(#req.body == length, "upload length mismatch"); send(req.body)
         else
            local sent = 0
            while sent < length do
               local chunk, e = req.body:read(math.min(16384, length - sent))
               if e then error(e, 0) end
               util.assert(type(chunk) == "string" and #chunk > 0 and sent + #chunk <= length, "upload length mismatch")
               send(chunk); sent = sent + #chunk
            end
         end
      else
         util.assert(length == 0, "missing upload body")
      end
      local header_bytes = 0
      local function line()
         local out = {}
         -- Bound line/header allocation rather than calling unbounded receive('*l').
         while true do
            ready(); local c = io_check(conn:receive(1)); header_bytes = header_bytes + 1
            util.assert(header_bytes <= 65536, "HTTP headers exceed 64 KiB")
            if c == "\n" then
               util.assert(out[#out] == "\r", "invalid HTTP line ending"); out[#out] = nil; return table.concat(out)
            end
            out[#out + 1] = c
         end
      end
      local status, headers_out
      for _ = 1, 6 do
         status = tonumber(line():match("^HTTP/1%.[01] (%d%d%d)"))
         util.assert(status and status >= 100, "invalid HTTP status")
         headers_out = {}
         while true do
            local value = line(); if value == "" then break end
            local k, v = value:match("^([%w%-]+):[ \t]*(.-)[ \t]*$")
            util.assert(k and util.header(v), "invalid HTTP response header"); k = k:lower()
            if headers_out[k] then
               util.assert(k ~= "content-length" and k ~= "transfer-encoding", "ambiguous HTTP framing")
               headers_out[k] = headers_out[k] .. ", " .. v
            else
               headers_out[k] = v
            end
         end
         if status >= 200 then break end
         util.assert(status ~= 101, "protocol switching is unsupported")
      end
      util.assert(status >= 200, "too many interim responses")
      local chunked = headers_out["transfer-encoding"]
      util.assert(not chunked or chunked:lower() == "chunked", "unsupported transfer encoding")
      local remaining = headers_out["content-length"]
      if remaining then
         util.assert(remaining:match("^%d+$") and tonumber(remaining) <= 9007199254740991, "invalid response length"); remaining =
             tonumber(remaining)
      end
      util.assert(not (chunked and remaining), "ambiguous HTTP framing")
      if status == 204 or status == 304 or req.method == "HEAD" then
         remaining = 0; chunked = nil
      end
      local stream = { closed = false }
      function stream:close()
         if not self.closed then
            self.closed = true; conn:close()
         end; return true
      end

      local chunk_remaining = 0
      function stream:read(n)
         if self.closed then return nil, errors.invalid("body is closed") end
         local value, e = errors.protect(function()
            if remaining == 0 then return nil end
            n = n or 16384; util.assert(util.integer(n, 1, 16777216), "invalid read size")
            if chunked then
               if chunk_remaining == 0 then
                  header_bytes = 0
                  local size, extension = line():match("^(%x+)(.*)$")
                  util.assert(extension == "" or extension and extension:sub(1, 1) == ";", "invalid chunk extension")
                  util.assert(size and #size <= 12, "invalid chunk size"); chunk_remaining = tonumber(size, 16)
                  if chunk_remaining == 0 then
                     while line() ~= "" do end
                     remaining = 0; return nil
                  end
               end
               n = math.min(n, chunk_remaining)
            elseif remaining then
               n = math.min(n, remaining)
            end
            ready(); local data, reason, partial = conn:receive(n)
            if not data then
               if not remaining and not chunked and reason == "closed" then
                  data = partial; remaining = 0
               else
                  io_check(nil)
               end
            end
            if chunked then
               chunk_remaining = chunk_remaining - #data
               if chunk_remaining == 0 then
                  ready(); util.assert(io_check(conn:receive(2)) == "\r\n", "invalid chunk terminator")
               end
            elseif remaining and remaining ~= 0 then
               remaining = remaining - #data
            end
            if #data == 0 then return nil end
            return data
         end)
         if e then self:close() end
         return value, e
      end

      return { status_code = status, headers = headers_out, body = stream }
   end)
   if not result and conn then conn:close() end
   return result, err
end

return M
