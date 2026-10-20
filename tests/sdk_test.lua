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

function TestSDK.testAll88RESTOperationsAnd105SchemasMatchContract()
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
   eq(operation_count, 88); eq(#b.operation_names(), 88)
   local count = 0
   for name, schema in pairs(spec.components.schemas) do
      count = count + 1
      local metadata = assert(b.models.schema(name))
      deep(metadata, schema)
      deep(assert(http.decode_body(json.encode(metadata))), schema)
      assert(type(b.models[name]) == "function")
   end
   eq(count, 105); eq(#b.models.names(), 105)
   operations.getLive.path = "/bad"; eq(b.operations().getLive.path, "/lives/{live_id}")
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

require("tests.https")
os.exit(lu.LuaUnit.run())
