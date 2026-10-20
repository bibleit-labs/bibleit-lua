local http = require("bibleit.http")
local json = require("dkjson")
local errors = require("bibleit.errors")
local util = require("bibleit.util")
local ENDPOINT = "https://bibleit.app"
local M = { endpoint = ENDPOINT }
local Client = {}; Client.__index = Client
function M.new_auth_client(transport)
   local t, e = http.transport(transport, 15); if not t then return nil, e end
   return setmetatable({ transport = t }, Client)
end

local function request(self, path, form, token, ctx)
   local headers = {}
   if token then headers.Authorization = "Bearer " .. token end
   local body
   if form then
      body = util.query(form)
      if #body > 16384 then
         return nil,
             errors.new("size",
                { message = "authorization form exceeds 16 KiB", part = "authorization form", bytes = #body, limit = 16384 })
      end
      headers["Content-Type"] = "application/x-www-form-urlencoded"
   end
   local res, e = http.send(self.transport,
      { method = "POST", url = ENDPOINT .. path, headers = headers, body = body, content_length = body and #body }, ctx)
   if not res then return nil, e end
   local data; data, e = http.read_all(res.body, 2097152); res:close(); if not data then return nil, e end
   if res.status_code ~= (token and 204 or 200) then
      local payload = http.decode_body(data); local code
      if type(payload) == "table" and payload ~= json.null then
         code = payload.error
      else
         local _, pe = require("bibleit.protocol").decode_response(data)
         if pe and pe.kind == "server" then
            code = pe.code; payload = pe.fields
         else
            payload = {}
         end
      end
      return nil, errors.new("http", { status = res.status_code, code = code, fields = payload })
   end
   if token then return true end
   local payload = http.decode_body(data)
   if type(payload) ~= "table" or not util.required(payload.actor) or not util.required(payload.access_token) or payload.access_token:find("[\r\n]") then
      return
          nil, errors.invalid("invalid authorization response")
   end
   local result = util.copy(payload); result.fields = payload; return result
end
function Client:exchange_code(exchange, ctx)
   exchange = exchange or {}
   if not util.required(exchange.code) or not util.required(exchange.verifier) then
      return nil,
          errors.invalid("authorization code and PKCE verifier are required")
   end
   local form = { code = exchange.code, code_verifier = exchange.verifier }
   if exchange.device_name and exchange.device_name ~= "" then form.device_name = exchange.device_name end
   return request(self, "/api/cli/token", form, nil, ctx)
end

function M.revoke_credential(token, transport, ctx)
   if not util.required(token) then return nil, errors.invalid("browser credential client required for revocation") end
   return request({ transport = transport }, "/api/cli/logout", nil, token, ctx)
end

return M
