local vm = _VERSION:match("%d+%.%d+")
package.path = "./lua_modules/share/lua/" ..
    vm .. "/?.lua;./lua_modules/share/lua/" .. vm .. "/?/init.lua;" .. package.path
package.cpath = "./lua_modules/lib/lua/" .. vm .. "/?.so;" .. package.cpath
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path
local b = require("bibleit")
local json = require("dkjson")
local function array(v) return setmetatable(v or {}, { __jsontype = "array" }) end
local function object(v) return setmetatable(v or {}, { __jsontype = "object" }) end
local http = require("bibleit.http")
local util = require("bibleit.util")
local lu = require("luaunit")
TestSDK = {}
local eq, deep = lu.assertIs, lu.assertEquals
local function load_json(path)
   local f = assert(io.open(path)); local data = f:read("*a"); f:close(); return assert(http.decode_body(data))
end
local function response(status, body, headers) return http.response(status, headers or {}, body or "") end
local function fails(fn, kind)
   local value, e = fn(); eq(value, nil); assert(e, "expected error"); if kind then eq(e.kind, kind) end; return e
end
local fixture_requests = load_json("contract/fixtures/requests-v1.json")
local fixture_responses = load_json("contract/fixtures/responses-v1.json")
local spec = load_json("contract/openapi.json")

function TestSDK.testHTTPDecodingUsesDkjsonAndTheSDKExposesNoJSONModule()
   eq(b.json, nil)
   assert(not pcall(require, "bibleit.json"))
   local value = assert(response(200, '{"array":[],"object":{},"nothing":null,"flag":false}'):decode())
   eq(value.nothing, json.null); eq(value.flag, false)
   eq(getmetatable(value.array).__jsontype, "array")
   eq(getmetatable(value.object).__jsontype, "object")
   for _, bad in ipairs({ "[", "true false", '"\255"' }) do
      fails(function() return response(200, bad):decode() end, "validation")
   end
   local c = assert(b.new_client("", function() error("invalid JSON must not be sent") end))
   local cycle = {}; cycle.self = cycle
   fails(function() return c:get_personal_identity({ json = cycle }) end, "validation")
end

function TestSDK.testAllSharedSSHResponseFixtures()
   for _, fixture in ipairs(fixture_responses) do
      local result, e = b.decode_response(fixture.wire)
      if fixture.invalid then
         assert(not result and e, fixture.name)
      elseif fixture.error_code then
         eq(result, nil, fixture.name); eq(e.code, fixture.error_code, fixture.name); deep(e.fields,
            fixture.error_fields or {})
      else
         assert(result, tostring(e) .. " " .. fixture.name)
         eq(#result.records, #fixture.records, fixture.name)
         for i, record in ipairs(fixture.records) do
            eq(result.records[i].type, record.type); deep(result.records[i].fields, record.fields)
         end
      end
   end
end

function TestSDK.testSSHCommandQuotingValidationEnumsAndFiniteFraming()
   local expected = {}
   for _, f in ipairs(fixture_requests) do expected[f.name] = f.wire end
   local commands = {
      ping = b.ping_command(),
      ["server-info"] = b.server_info_command(),
      ["account-info"] = b
          .account_info_command(),
      ["account-quotas"] = b.account_quotas_command(),
      translations = b.translation_list_command(),
      ["read-multiword"] = assert(b.read_command({ translation = "web", book = "Song of Songs", chapter = 2, verse = 1 })),
      ["search-backslash"] = assert(b.search_command("web", "love \\ peace")),
      ["live-name"] = assert(b
         .create_live_command("Sunday Service")),
      ["secret-authenticate"] = assert(b.live_secret_command("abc", "",
         "audience-secret")),
      ["secret-create"] = assert(b.live_secret_command("abc", "CREATE", "")),
      ["secret-rotate"] =
          assert(b.live_secret_command("abc", "ROTATE", "")),
      ["stack-positive-pop"] = assert(b.pop_live_command("abc", 2))
   }
   for name, cmd in pairs(commands) do eq(cmd:string(), expected[name], name) end
   for _, bad in ipairs({ "x\ny", "x\ry", "x\0y", '"' }) do fails(function() return b.search_command("web", bad) end) end
   eq(assert(b.search_command("web", "a \\")):string(), 'SEARCH web "a \\"')
   fails(function() return b.live_command("x", "INJECT") end)
   fails(function() return b.live_secret_command("x", "", "CREATE") end)
   fails(function() return b.live_secret_command("x", "SET", "value") end)
   fails(function() return b.set_live_command("x", "NAME", "a", "b") end)
   fails(function() return b.pop_live_command("x", 2147483648) end)
   fails(function() return b.read_command({ translation = "web", book = "1", verse = 1 }) end)
   local wire = "OK count=1 translations=web\n"
   assert(b.decode_command_response(b.translation_list_command(), wire))
   fails(function() return b.decode_response(wire) end)
   assert(b.decode_response("OK notifications=#{enabled => true,\n nested => [a,b]}\n"))
   fails(function() return b.decode_response("OK x=1 x=2\n") end)
   fails(function() return b.decode_response("OK\nEND\nOK\n") end)
   fails(function() return b.decode_response('OK text="' .. string.rep("x", 2097152) .. '"\n') end)
end

function TestSDK.testAllRESTOperationsAndSchemasMatchContract()
   local operations = b.operations(); local operation_count = 0
   for path, item in pairs(spec.paths) do
      for method, op in pairs(item) do
         if type(op) == "table" and op["x-fern-server-name"] == "rest" then
            operation_count = operation_count + 1
            local got = assert(operations[op.operationId]); eq(got.path, path); eq(got.method, method:upper())
            local params, args = {}, {}
            for _, key in ipairs(got.parameters) do
               params[key] = "resource"; args[#args + 1] = "resource"
            end
            local calls = 0
            local client = assert(b.new_client("svc_fixture", function(req)
               calls = calls + 1; eq(req.method, method:upper()); eq(req.url,
                  b.endpoint .. path:gsub("{[^}]+}", "resource")); eq(req.headers.Authorization,
                  "Bearer svc_fixture")
               return response(204)
            end))
            local result = assert(client[util.snake(op.operationId)](client, (table.unpack or unpack)(args))); assert(
               result:close()); eq(calls, 1)
         end
      end
   end
   eq(operation_count, 110); eq(#b.operation_names(), operation_count)
   local count = 0
   for name, schema in pairs(spec.components.schemas) do
      count = count + 1
      local metadata = assert(b.models.schema(name))
      deep(metadata, schema)
      deep(assert(http.decode_body(json.encode(metadata))), schema)
      assert(type(b.models[name]) == "function")
   end
   eq(count, 139); eq(#b.models.names(), count)
   operations.getLive.path = "/bad"; eq(b.operations().getLive.path, "/lives/{live_id}")
end

function TestSDK.testGrantResponseScopesUseSeparateMetadata()
   local grant = assert(b.models.schema("OAuthGrant"))
   eq(grant.properties.scopes.items["$ref"], "#/components/schemas/OAuthGrantedScope")
   local granted, ordinary = {}, {}
   for _, scope in ipairs(assert(b.models.schema("OAuthGrantedScope")).enum) do granted[scope] = true end
   for _, scope in ipairs(assert(b.models.schema("OAuthScope")).enum) do ordinary[scope] = true end
   for _, scope in ipairs({"live.queue.stage", "live.rename"}) do
      eq(granted[scope], true); eq(ordinary[scope], nil)
   end
   eq(granted["future.unknown"], nil)
   local wire = '{"id":"00000000000000000000000000000000","client_id":"synthetic-response-client","client_name":"Synthetic response only","scopes":["identity.read","live.queue.stage","live.rename"],"expires_at":1}'
   local decoded = assert(response(200, wire):decode())
   local typed = assert(b.models.OAuthGrant(decoded))
   deep(typed.scopes, array({"identity.read", "live.queue.stage", "live.rename"}))
   deep(assert(http.decode_body(json.encode(typed))), decoded)
end

function TestSDK.testRESTExactHeadersStreamingEncodingAndBoundedDecode()
   local closed = 0
   local body = {
      read = function() return nil end,
      close = function()
         closed = closed + 1; return true
      end
   }
   local client = assert(b.new_client("svc_fixture", function(req)
      eq(req.headers["If-Match"], '"live:7"'); eq(req.headers["Idempotency-Key"], "one"); eq(
         req.headers["X-Destination-Service-Token"], "svc_destination"); eq(req.headers.Range, "bytes=0-1")
      eq(req.url, b.endpoint .. "/lives/x?after=opaque+%2F+%2B&limit=2"); eq(req.body, "{}")
      return { status_code = 206, headers = { ETag = '"same"' }, body = body }
   end))
   local r = assert(client:get_live("x",
      {
         query = { after = "opaque / +", limit = "2" },
         json = object(),
         if_match = '"live:7"',
         idempotency_key =
         "one",
         destination_token = "svc_destination",
         range = "bytes=0-1"
      })); eq(r.headers.etag, '"same"'); eq(r.body,
      body); r:close(); r:close(); eq(closed, 1)
   local calls = 0
   client = assert(b.new_client("",
      function(req)
         calls = calls + 1; eq(req.body, body); eq(req.content_length, 8); return response(200, "{}")
      end))
   local r2 = assert(client:call("getLive", { live_id = "x" },
      { body = body, content_length = 8, content_type = "application/octet-stream" })); r2:close(); eq(calls, 1)
   fails(function() return client:get_live("x", { json = {}, body = body, content_length = 0 }) end)
   fails(function() return client:get_live("x", { body = body }) end)
   fails(function() return client:get_live("x", { if_match = "bad\r\nheader" }) end)
   local huge = response(200, string.rep("x", 4194305)); fails(function() return huge:decode() end, "size"); huge:close()
end

function TestSDK.testRESTErrorsFixedOriginCancellationAndNoRetries()
   local calls, closed = 0, 0
   local client = assert(b.new_client("bt_fixture", function()
      calls = calls + 1
      local result = response(412, '{"code":"precondition_failed","detail":"untrusted detail"}',
         { ["Retry-After"] = "2", ["X-Request-Id"] = "request" })
      local old = result.body.close; result.body.close = function(self)
         closed = closed + 1; return old(self)
      end
      return result
   end))
   local e = fails(function() return client:get_live("x") end, "problem"); eq(e.status, 412); eq(e.request_id, "request"); eq(
      e:retry_after(), 2); assert(not tostring(e):find("untrusted", 1, true)); eq(closed, 1); eq(calls, 1)
   for _, bad in ipairs({ "..", "x/y", "x\\y", "x\ny", "" }) do fails(function() return client:get_live(bad) end) end
   fails(function() return client:call("getLive", { live_id = "x", unexpected = "x" }) end); eq(calls, 1)
   fails(function() return b.new_client(" token") end)
   local ctx = b.context.new(); ctx:cancel(); fails(function() return client:get_live("x", nil, ctx) end, "cancelled"); eq(
      calls, 1)
   local rclient = assert(b.new_client("fixture",
      function()
         calls = calls + 1; return response(302, "", { Location = "https://example.invalid" })
      end))
   fails(function() return rclient:get_live("x") end, "problem"); eq(calls, 2)
end

local function page(verse, cursor, rights)
   return {
      translation = "web",
      rights = { edition = rights or "fixture" },
      verses = array({ { book_id = 19, chapter = 1, verse = verse, text = "fixture" } }),
      next_cursor =
          cursor or json.null
   }
end
function TestSDK.testBookIteratorsLazyOptionsCopiedBodiesClosedBeforeYield()
   for _, personal in ipairs({ true, false }) do
      local calls, closed = 0, 0; local opts = { query = { limit = "1" } }
      local client = assert(b.new_client("", function(req)
         calls = calls + 1
         if calls == 2 then assert(req.url:find("after=opaque+%2F+%2B", 1, true)) end
         local r = response(200, assert(json.encode(page(calls, calls == 1 and "opaque / +" or json.null))))
         r.body.close = function()
            closed = closed + 1; return true
         end; return r
      end))
      local iter = personal and client:read_personal_book_pages("account", "web", "19", opts) or
          client:read_book_pages("org", "web", "19", opts)
      eq(calls, 0); opts.query.limit = "999"
      eq(assert(iter()).verses[1].verse, 1); eq(closed, 1); eq(assert(iter()).verses[1].verse, 2); eq(closed, 2); eq(
         iter(), nil); eq(calls, 2); eq(opts.query.after, nil)
   end
end

function TestSDK.testBookIteratorComparesMetadataIndependentlyOfKeyOrderAndCallerMutations()
   local calls = 0
   local client = assert(b.new_client("", function()
      calls = calls + 1
      local p = page(calls, calls == 1 and "next" or json.null)
      p.rights = setmetatable({ edition = "fixture", attribution = "credit" }, {
         __jsonorder = calls == 1 and { "edition", "attribution" } or { "attribution", "edition" },
      })
      return response(200, json.encode(p))
   end))
   local iter = client:read_book_pages("org", "web", "19")
   local first = assert(iter()); first.rights.edition = "changed by caller"
   eq(assert(iter()).verses[1].verse, 2); eq(iter(), nil)
end

function TestSDK.testBookIteratorMalformedPagesStaleEditionsCursorsAndCancellation()
   local bad = {
      { translation = "web", rights = {},        verses = array() },
      page(1, ""), page(0, json.null), page(1, 8),
      { translation = "web", rights = {},        verses = array(), next_cursor = "next" },
      { translation = "web", rights = json.null, verses = array(), next_cursor = json.null },
   }
   for _, p in ipairs(bad) do
      local c = assert(b.new_client("", function() return response(200, assert(json.encode(p))) end))
      local iter = c:read_book_pages("org", "web", "19"); fails(iter, "invalid_book_page"); eq(iter(), nil)
   end
   for _, change in ipairs({ "coordinates", "rights", "cursor" }) do
      local calls = 0
      local c = assert(b.new_client("", function()
         calls = calls + 1
         return response(200,
            assert(json.encode(page(change == "coordinates" and 1 or calls, "repeat",
               change == "rights" and tostring(calls) or nil))))
      end))
      local iter = c:read_book_pages("org", "web", "19"); assert(iter()); fails(iter, "invalid_book_page"); eq(calls, 2)
   end
   local calls = 0; local ctx = b.context.new()
   local c = assert(b.new_client("",
      function()
         calls = calls + 1; return response(200, assert(json.encode(page(1, "next"))))
      end))
   local iter = c:read_book_pages("org", "web", "19", nil, ctx); assert(iter()); ctx:cancel(); fails(iter, "cancelled"); eq(
      calls, 1)
   for _, query in ipairs({ { limit = "0" }, { limit = { "1", "2" } }, { after = "" }, { limit = "501" } }) do
      fails(c
         :read_book_pages("org", "web", "19", { query = query }))
   end
   calls = 0
   c = assert(b.new_client("", function()
      calls = calls + 1; return response(409, '{"code":"stale_cursor"}')
   end))
   fails(c:read_book_pages("org", "web", "19"), "problem"); eq(calls, 1)
end

function TestSDK.testSingleLiveEventPollAndVersionResourceValidation()
   local event = {
      schema_version = 1,
      type = "live.snapshot",
      resource_type = "live",
      resource_id = "live",
      sequence = 1,
      cursor =
      "opaque",
      data = {}
   }
   local calls = 0
   local c = assert(b.new_client("",
      function(req)
         calls = calls + 1; assert(req.url:find("wait=25", 1, true)); return response(200, assert(json.encode(event)))
      end))
   eq(assert(c:poll_live_events("live", "", 25)).cursor, "opaque"); eq(calls, 1)
   event.schema_version = 2; fails(function() return c:poll_live_events("live", "", 25) end)
   event.schema_version = 1; event.type = "stream.heartbeat"; fails(function() return c:poll_live_events("live", "", 25) end)
   event.data = json.null; assert(c:poll_live_events("live", "", 25))
   fails(function() return c:poll_live_events("live", "", 26) end)
end

function TestSDK.testOAuthConsentCodeExchangeRefreshRevocationAndOriginIsolation()
   local url = assert(b.authorization_url("client", "http://127.0.0.1/cb", "state", string.rep("a", 43),
      { "read", "write" }))
   assert(url:find("code_challenge_method=S256", 1, true)); assert(url:find("scope=read+write", 1, true))
   fails(function() return b.authorization_url("x", "x", "x", "bad", { "read" }) end)
   local calls = 0
   local oauth = assert(b.new_oauth_client(function(req)
      calls = calls + 1; assert(req.url:find("https://bibleit.app/", 1, true) == 1); eq(req.headers.Authorization, nil); eq(
         req.headers.Cookie, nil)
      if req.url:find("/oauth/token", 1, true) then
         eq(req.method, "POST"); assert(req.body:find("client_id=client", 1, true))
      end
      return response(200, '{"access_token":"fixture","future":true}')
   end))
   assert(oauth:metadata()); assert(oauth:exchange_code("client", "code", "http://127.0.0.1/cb", string.rep("v", 43))); assert(
      oauth:refresh("client", "refresh", { "read" })); assert(oauth:revoke("client", "refresh")); eq(calls, 4)
   fails(function() return oauth:exchange_code("client", "code", "uri", "short") end); eq(calls, 4)
   oauth = assert(b.new_oauth_client(function()
      calls = calls + 1; return response(400, '{"error":"invalid_grant","error_description":"untrusted"}')
   end))
   local e = fails(function() return oauth:refresh("client", "fixture") end, "oauth"); eq(e.code, "invalid_grant"); assert(not
      tostring(e):find("untrusted", 1, true)); eq(calls, 5)
end

function TestSDK.testCLIAuthExchangeFieldsRevocationAndNoRetries()
   local auth = assert(b.new_auth_client(function(req)
      eq(req.url, "https://bibleit.app/api/cli/token"); eq(req.headers.Authorization, nil); assert(req.body:find(
         "code_verifier=verifier", 1, true))
      return response(200, '{"actor":"fixture","access_token":"fixture","future":true}')
   end))
   local result = assert(auth:exchange_code({ code = "code", verifier = "verifier", device_name = "Lua app" })); eq(
      result.actor, "fixture"); eq(result.fields.future, true)
   local c = assert(b.new_client("fixture",
      function(req)
         eq(req.url, "https://bibleit.app/api/cli/logout"); eq(req.headers.Authorization, "Bearer fixture"); return
             response(204)
      end)); assert(c:revoke_credential())
   eq(auth.revoke_credential, nil)
   local bad = assert(b.new_auth_client(function() return response(400, "ERR future_code retry_after_ms=500\n") end))
   eq(fails(function() return bad:exchange_code({ code = "code", verifier = "verifier" }) end, "http").code,
      "future_code")
end

local function ssh(wire) return assert(b.new_ssh_client(function() return wire end)) end
function TestSDK.testSSHExecutorOwnershipAndRequestLimits()
   fails(function() return b.new_ssh_client(nil) end)
   fails(function() return ssh("OK\n"):execute({}) end)
   fails(function() return ssh("OK\n"):execute(assert(b.live_command("x", "SUBSCRIBE"))) end)
   fails(function() return ssh("OK\n"):execute(assert(b.search_command("web", string.rep("x", 8192)))) end, "size")
   local ctx = b.context.new(); ctx:cancel(); fails(function() return ssh("OK\n"):ping(ctx) end, "cancelled")
end

function TestSDK.testSSHTypedDiscoveryIdentityAccountQuotasAndReading()
   local x = assert(ssh("OK protocol_version=1 version=v1 capabilities=a,b\n"):get_server_info()); eq(x.protocol_version,
      1); eq(#x.capabilities, 2)
   x = assert(ssh("OK commands=1 auth=true\nCOMMAND usage=PING summary=ping\nEND\n"):help("")); eq(x.commands[1].auth,
      "none"); eq(x.authenticated, true)
   x = assert(ssh("OK actor=fixture auth=true roles=a,b permissions=x,y future=kept\n"):get_identity()); eq(
      x.authenticated, true); eq(x.fields.future, "kept")
   x = assert(ssh(
         "OK actor=fixture plan=free plan_source=default plan_activated_at=0 lives=0 translations=1 tokens=0 keys=0\n")
      :get_account_info()); eq(x.translations, 1)
   x = assert(ssh("OK count=1\nQUOTA permission=read limit=unlimited used=1\nEND\n"):list_quotas()); eq(
      x.quotas[1].limit.unlimited, true)
   x = assert(ssh('OK translation=web book=43 chapter=3 verse=16 text="legacy display" content="plain"\n'):read_verses({
      translation =
      "web",
      book = "43",
      chapter = 3,
      verse = 16
   })); eq(x.verses[1].content, "plain"); eq(x.verses[1].book_id, 43)
   x = assert(ssh('OK translation=web results=1\nVERSE text="a verse"\nEND\n'):search_verses("web", "verse")); eq(
      x.verses[1].book_id, nil)
   fails(function() return ssh("OK translation=web results=1\nVERSE text=x chapter=1\nEND\n"):search_verses("web", "x") end)
end

function TestSDK.testSSHTypedCatalogsTokensAndOrganizationsPreserveMetadata()
   local x = assert(ssh('OK short_name=web full_name="World English Bible" future=x\n'):get_translation_info("web")); eq(
      x.short_name, "web")
   x = assert(ssh(
         "OK translation=web books=1\nBOOK book=19 name=Psalms chapters=1\nCHAPTER book=19 chapter=119 verses=176\nEND\n")
      :get_translation_catalog("web")); eq(x.books[1].id, 19); eq(x.books[1].chapters[1].number, 119)
   fails(function()
      return ssh("OK translation=web books=1\nBOOK book=19 name=Psalms chapters=2\nEND\n")
          :get_translation_catalog("web")
   end)
   x = assert(ssh(
         'OK actor=fixture count=1\nTOKEN id=t source=future issued_at=9223372036854775807 scopes="" retiring=false\nEND\n')
      :list_tokens()); eq(type(x.tokens[1].issued_at), "string"); eq(x.tokens[1].issued_at, "9223372036854775807"); eq(
      x.tokens[1].retiring, false); eq(
      #x.tokens[1].scopes, 0)
   x = assert(ssh(
         "OK count=1 next=opaque\nORGANIZATION id=o handle=h name=n role=member verification=future status=active\nEND\n")
      :list_organizations("")); eq(x.next, "opaque"); eq(x.entries[1].verification, "future")
   x = assert(ssh(
         'OK application_id=a name=n domain=example.invalid state=pending next_action=wait verification_url="https://example.invalid/status"\n')
      :get_organization_application_status("a")); eq(x.application.kind, "application")
end

function TestSDK.testSSHTypedLiveStateListsStatsStackAndMutationAcknowledgements()
   local wire = 'OK id=l name="" status=future paused=false owned=true\n'
   eq(assert(ssh(wire):create_live("")).live.name, ""); eq(assert(ssh(wire):get_live("l")).live.owned, true); assert(ssh(
      wire):set_live("l", "NAME", { "name" }))
   local x = assert(ssh("OK count=1\nLIVE id=l name=n status=ready paused=true\nEND\n"):list_lives()); eq(
      x.lives[1].paused, true)
   x = assert(ssh(
         "OK id=l running_for_seconds=1 revision=1 stack_entries=1 actor_connections=1 anonymous_connections=0 connections=1\nCONNECTION actor=a access=owner connected_at=1 connected_for_seconds=1\nEND\n")
      :get_live_stats("l")); eq(#x.connections, 1)
   x = assert(ssh("OK id=l count=1\nSTACK position=1 translation=web text=verse\nEND\n"):get_live_stack("l")); eq(
      x.entries[1].position, 1)
   x = assert(ssh("OK event=verse translations=1\nVERSE translation=web text=verse\nEND\n"):push_live("l",
      { book = "19" })); eq(
      x.verses[1].text, "verse")
   eq(assert(ssh("OK event=clear\n"):pop_live("l", 0)).event, "clear")
   eq(assert(ssh("OK paused=false\n"):control_live("l", "RESUME")).paused, false)
   eq(assert(ssh("OK event=deleted\n"):control_live("l", "DELETE")).event, "deleted")
   eq(assert(ssh(wire):control_live("l", "START")).state.id, "l")
   fails(function() return ssh(wire):control_live("l", "SUBSCRIBE") end)
   fails(function() return ssh("OK id=l count=1\nSTACK position=2 translation=web text=x\nEND\n"):get_live_stack("l") end)
end

function TestSDK.testTLSHostnameChecksRequireDNSSANAndRestrictWildcardScope()
   local function cert(names) return { extensions = function() return { ["2.5.29.17"] = { dNSName = names } } end } end
   assert(b.transport.matches_hostname(cert({ "api.bibleit.app" }), "api.bibleit.app"))
   assert(b.transport.matches_hostname(cert({ "*.bibleit.app" }), "api.bibleit.app"))
   assert(not b.transport.matches_hostname(cert({ "*.bibleit.app" }), "deep.api.bibleit.app"))
   assert(not b.transport.matches_hostname(cert({ "api.bibleit.app\0.invalid" }), "api.bibleit.app"))
   assert(not b.transport.matches_hostname(cert({}), "api.bibleit.app"))
end

function TestSDK.testModelConstructionUnionConversionsAndMergeSemantics()
   local value = assert(b.models.PresentationTextElement({ type = "text", future = true }))
   local member = assert(b.models.as("PresentationElement", "PresentationTextElement", value))
   eq(member.type, "text"); eq(member.future, true)
   local merged = assert(b.models.merge("PresentationElement", "PresentationTextElement", member,
      { future = json.null, text = "updated" }))
   eq(merged.future, nil); eq(merged.text, "updated"); eq(member.future, true)
   assert(b.models.from("ReplaceDisplay", 1, { type = "empty" }))
   fails(function() return b.models.as("PresentationElement", "Missing", {}) end)
   assert(type(b.new_oauth_client) == "function")
   local credential = assert(b.new_client("fixture", function() error("unexpected HTTP call") end))
   eq(credential.ping, nil)
end

function TestSDK.testRootConstructorsExposeDistinctResourceSSHAndAuthorizationClients()
   eq(b.rest, nil)
   eq(b.auth, nil)
   eq(b.oauth, nil)
   local resource = assert(b.new_client("fixture", function(req)
      if req.url == "https://bibleit.app/api/cli/logout" then return response(204) end
      eq(req.url, "https://api.bibleit.app/v1/me")
      return response(200, '{"id":"fixture"}')
   end))
   local result = assert(resource:get_personal_identity())
   eq(result:decode().id, "fixture")
   result:close()
   assert(resource:revoke_credential())
   eq(resource.execute, nil)
   eq(resource.read_verses, nil)
   local command_client = ssh("OK pong=true\n")
   assert(command_client:ping())
   eq(command_client.call, nil)
   eq(command_client.get_personal_identity, nil)
   eq(command_client.revoke_credential, nil)
   eq(assert(b.new_auth_client()).execute, nil)
   eq(assert(b.new_auth_client()).get_personal_identity, nil)
   eq(assert(b.new_oauth_client()).get_personal_identity, nil)
   local alias = assert(b.new_client_with_http_client(""))
   assert(type(alias.get_personal_identity) == "function")
end

function TestSDK.testBroadcastBuildersAndCallerOwnedExecutor()
   local id = "2495e5de-3083-4963-959c-f632254c58b4"
   local hash = string.rep("a", 64)
   local cases = {
      {"setup_list", {id}, "setup list"},
      {"setup_list", {id, 99, id}, "setup list 99 " .. id},
      {"setup_get", {id,id}, "setup " .. id .. " get"},
      {"setup_document", {id,id,"9223372036854775807",0}, "setup " .. id .. " document 9223372036854775807 0"},
      {"write_intent", {id,"create","new",0,2,hash}, "write intent create new 0 2 " .. hash},
      {"write_intent", {id,"save",id,1,2,hash}, "write intent save " .. id .. " 1 2 " .. hash},
      {"write_begin", {id,"ticket"}, "write begin ticket"},
      {"write_status", {id,"ticket"}, "write status ticket"},
      {"write_inspect", {id,id}, "write inspect " .. id},
      {"write_abort", {id,id}, "write abort " .. id},
      {"write_chunk", {id,id,0,"e30="}, "write chunk " .. id .. " 0 e30="},
      {"write_commit", {id,"ticket",id}, "write commit ticket " .. id},
      {"event_create", {id,id,"e30="}, "event create " .. id .. " e30="},
      {"event_attach", {id,id,"YouTube_id-1"}, "event attach " .. id .. " YouTube_id-1"},
      {"event_transition", {id,id,"go-live",1,id}, "event " .. id .. " go-live 1 " .. id},
      {"publisher_stop", {id,id,1}, "publisher " .. id .. " stop 1"},
   }
   for _, name in ipairs({"profiles","channel","preflight","events","publishers","takeover"}) do
      cases[#cases+1] = {name,{id},name}
   end
   for _, name in ipairs({"event","publisher","operation"}) do
      cases[#cases+1] = {name .. "_get",{id,id},name .. " " .. id .. " get"}
   end
   local calls, expected = 0
   local client = assert(b.new_ssh_client(function(cmd)
      calls = calls + 1; eq(cmd:string(), expected); return "OK accepted=true\n"
   end))
   for _, case in ipairs(cases) do
      expected = "broadcast " .. id .. " " .. case[3]
      eq(assert(b["broadcast_" .. case[1] .. "_command"]((table.unpack or unpack)(case[2]))):string(), expected)
      assert(client["broadcast_" .. case[1]](client, (table.unpack or unpack)(case[2])))
   end
   eq(calls, #cases)
   eq(assert(b.help_command("broadcast")):string(), "HELP BROADCAST")
   fails(function() return b.broadcast_channel_command(id:upper()) end, "validation")
   fails(function() return b.broadcast_setup_list_command(id,100) end, "validation")
   fails(function() return b.broadcast_setup_document_command(id,id,"9223372036854775808",0) end, "validation")
   fails(function() return b.broadcast_setup_document_command(id,id,9007199254740992,0) end, "validation")
   fails(function() return b.broadcast_write_intent_command(id,"create",id,0,2,hash) end, "validation")
   fails(function() return b.broadcast_write_intent_command(id,"save",id,0,2,hash) end, "validation")
   fails(function() return b.broadcast_write_chunk_command(id,id,0,"e31=") end, "validation")
   fails(function() return b.broadcast_write_chunk_command(id,id,0,require("bibleit.internal.base64").b64(string.rep("a",3073))) end, "validation")
   fails(function() return b.broadcast_write_status_command(id,"ticket\nPING") end, "validation")
   fails(function() return b.broadcast_event_attach_command(id,id,"https://youtube.com/id") end, "validation")
   fails(function() return b.broadcast_event_create_command(id,id,"W10=") end,"validation")
   fails(function() return b.broadcast_event_create_command(id,id,"bnVsbA==") end,"validation")
   fails(function() return b.broadcast_event_create_command(id,id,"bm90LWpzb24=") end,"validation")
   fails(function() return b.broadcast_event_transition_command(id,id,"start",1,id) end, "validation")
   local context = b.context.new(); context:cancel()
   fails(function() return client:broadcast_channel(id,context) end)
   eq(calls,#cases)
   local once = 0
   client = assert(b.new_ssh_client(function() once=once+1; return "ERR uncertain_outcome\n" end))
   local err = fails(function() return client:broadcast_write_commit(id,"ticket",id) end,"server")
   eq(err.code,"uncertain_outcome"); eq(once,1)
end

function TestSDK.testBroadcastLifecycleProjectionValidation()
   local function fields(value, kind)
      local bytes = json.encode({value=value})
      return "document_format=broadcast-lifecycle-json-v1 record_type=" .. (kind or "channel") ..
         " bytes=" .. #bytes .. " data_base64=" .. require("bibleit.internal.base64").b64(bytes)
   end
   local decoded = assert(b.decode_broadcast_lifecycle(assert(b.decode_response("OK " .. fields(json.null) .. "\n")),"channel"))
   eq(decoded.value,json.null)
   local wire = "OK count=1\nYOUTUBE_EVENT " .. fields({id="event",future_field=true},"event") .. "\nEND\n"
   decoded = assert(b.decode_broadcast_lifecycle(assert(b.decode_response(wire)),"event"))
   eq(decoded.values[1].future_field,true)
   fails(function() return b.decode_broadcast_lifecycle(assert(b.decode_response(wire)),"publisher") end,"validation")
   local response = assert(b.decode_response("OK " .. fields({id="event"},"event") .. "\n"))
   response.records[1].fields.bytes = "1000001"
   fails(function() return b.decode_broadcast_lifecycle(response,"event") end,"validation")
end

function TestSDK.testBroadcastRESTPreservesSignedBytesAndErrorSemantics()
   local id = "2495e5de-3083-4963-959c-f632254c58b4"
   local body = '{ "version": 1, "name": "Exact bytes" }\n'
   local calls = 0
   local client = assert(b.new_client("bt_fixture",function(req)
      calls=calls+1
      eq(req.method,"PUT"); eq(req.body,body); eq(req.content_length,#body)
      eq(req.headers["Idempotency-Key"],"original-ticket")
      eq(req.headers["If-Match"],'"setup-4"')
      eq(req.headers["Content-Type"],"application/json")
      return response(200,'{"request_id":"original-ticket","result_state":"applied","revision":5}')
   end))
   local result = assert(client:replace_broadcast_setup(id,id,{body=body,content_length=#body,
      content_type="application/json",if_match='"setup-4"',idempotency_key="original-ticket"}))
   eq(result:decode().revision,5); result:close(); eq(calls,1)
   for _, code in ipairs({"browser_required","operation_conflict","request_expired","uncertain_outcome"}) do
      calls=0
      client=assert(b.new_client("bt_fixture",function()
         calls=calls+1; return response(409,json.encode({code=code,request_id="retained"}))
      end))
      local err=fails(function() return client:request_broadcast_takeover(id,{json=object()}) end,"problem")
      eq(err.code,code); eq(calls,1)
   end
   local nullable=assert(b.models.schema("BroadcastChannelResult"))
   assert(nullable.anyOf)
   local codec=require("bibleit.internal.base64")
   for _, pair in ipairs({{"",""},{"f","Zg=="},{"fo","Zm8="},{"foo","Zm9v"},{"foob","Zm9vYg=="},{"fooba","Zm9vYmE="},{"foobar","Zm9vYmFy"}}) do
      eq(codec.b64(pair[1]),pair[2]); eq(codec.unb64(pair[2]),pair[1])
   end
   for _, bad in ipairs({"Zg=","Zg===","Zg==AAAA","Zh==","Zm9=","Zg==\n","===="}) do eq(codec.unb64(bad),nil) end
end

require("tests.https")
os.exit(lu.LuaUnit.run())
