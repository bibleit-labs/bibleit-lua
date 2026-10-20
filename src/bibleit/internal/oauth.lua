local http = require("bibleit.http")
local json = require("dkjson")
local errors = require("bibleit.errors")
local util = require("bibleit.util")
local ENDPOINT = "https://bibleit.app"
local M = { endpoint = ENDPOINT }
local Client = {}; Client.__index = Client
function M.new_client(transport)
   local t, e = http.transport(transport, 40); if not t then return nil, e end
   return setmetatable({ transport = t }, Client)
end

function M.authorization_url(client_id, redirect_uri, state, challenge, scopes)
   if not util.required(client_id) or not util.required(redirect_uri) or not util.required(state) or type(challenge) ~= "string" or #challenge ~= 43 or challenge:find("[^%w%-%_]") or type(scopes) ~= "table" or #scopes == 0 then
      return nil, errors.invalid("client ID, callback, state, S256 challenge and explicit scopes are required")
   end
   return ENDPOINT ..
       "/oauth/authorize?" ..
       util.query({
          response_type = "code",
          client_id = client_id,
          redirect_uri = redirect_uri,
          state = state,
          code_challenge =
              challenge,
          code_challenge_method = "S256",
          scope = table.concat(scopes, " ")
       })
end

function Client:_request(method, path, form, ctx)
   local encoded = util.query(form)
   if #encoded > 16384 then return nil, errors.new("size", { message = "OAuth form exceeds 16 KiB" }) end
   local headers = { Accept = "application/json" }
   local body; if method == "POST" then
      body = encoded; headers["Content-Type"] = "application/x-www-form-urlencoded"
   end
   local res, e = http.send(self.transport,
      { method = method, url = ENDPOINT .. path, headers = headers, body = body, content_length = body and #body }, ctx)
   if not res then return nil, e end
   if res.status_code < 200 or res.status_code >= 300 then
      local data, read_err = http.read_all(res.body, 16384); res:close(); if not data then return nil, read_err end
      local payload = http.decode_body(data)
      if type(payload) ~= "table" or payload == json.null then payload = {} end
      return nil,
          errors.new("oauth",
             {
                code = payload.error or "",
                description = payload.error_description,
                status = res.status_code,
                headers =
                    res.headers
             })
   end
   return res
end

function Client:_decode(method, path, form, ctx)
   local res, e = self:_request(method, path, form, ctx); if not res then return nil, e end
   local v; v, e = res:decode(); local _, ce = res:close(); return v, e or ce
end

function Client:metadata(ctx) return self:_decode("GET", "/.well-known/oauth-authorization-server", nil, ctx) end

function Client:exchange_code(client_id, code, redirect_uri, verifier, ctx)
   if not util.required(client_id) or not util.required(code) or not util.required(redirect_uri) or type(verifier) ~= "string" or #verifier < 43 or #verifier > 128 then
      return
          nil, errors.invalid("client ID, code, callback and PKCE verifier are required")
   end
   return self:_decode("POST", "/oauth/token",
      {
         grant_type = "authorization_code",
         client_id = client_id,
         code = code,
         redirect_uri = redirect_uri,
         code_verifier =
             verifier
      }, ctx)
end

function Client:refresh(client_id, refresh_token, scopes, ctx)
   if not util.required(client_id) or not util.required(refresh_token) then
      return nil,
          errors.invalid("client ID and refresh token are required")
   end
   local form = { grant_type = "refresh_token", client_id = client_id, refresh_token = refresh_token }
   if scopes and #scopes > 0 then form.scope = table.concat(scopes, " ") end
   return self:_decode("POST", "/oauth/token", form, ctx)
end

function Client:revoke(client_id, token, ctx)
   if not util.required(client_id) or not util.required(token) then
      return nil,
          errors.invalid("client ID and token are required")
   end
   local res, e = self:_request("POST", "/oauth/revoke", { client_id = client_id, token = token }, ctx); if not res then
      return
          nil, e
   end
   return res:close()
end

return M
