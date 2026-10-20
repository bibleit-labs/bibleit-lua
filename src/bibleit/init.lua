local command = require("bibleit.command")
local protocol = require("bibleit.protocol")
local auth = require("bibleit.internal.auth")
local client = require("bibleit.internal.client")
local oauth = require("bibleit.internal.oauth")
local M = {
   _VERSION = "0.0.1",
   command = command,
   protocol = protocol,
   models = require("bibleit.models"),
   context = require("bibleit.context"),
   transport = require("bibleit.transport"),
   errors = require("bibleit.errors"),
   new_client = client.new_client,
   new_client_with_http_client = client.new_client,
   new_auth_client = auth.new_auth_client,
   new_auth_client_with_http_client = auth.new_auth_client,
   operations = client.operations,
   operation_names = client.operation_names,
   endpoint = client.endpoint,
   new_oauth_client = oauth.new_client,
   authorization_url = oauth.authorization_url,
   new_ssh_client = require("bibleit.internal.ssh").new_client,
   max_command_bytes = 8192,
   max_request_bytes = 16384,
}
for name, value in pairs(command) do if name ~= "is_command" then M[name] = value end end
for name, value in pairs(protocol) do M[name] = value end
return M
