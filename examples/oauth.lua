local bibleit = require("bibleit")
-- Applications create a cryptographically random state and PKCE verifier,
-- derive its S256 challenge, and verify callback state before exchanging a code.
local function authorize(client_id, callback, state, challenge, scopes)
   return bibleit.authorization_url(client_id, callback, state, challenge, scopes)
end
local function exchange(client_id, callback, code, verifier)
   local oauth = assert(bibleit.new_oauth_client())
   return oauth:exchange_code(client_id, code, callback, verifier)
end
return { authorize = authorize, exchange = exchange }
