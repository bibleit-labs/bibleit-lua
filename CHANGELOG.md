# Changelog

## 0.0.2

- Separate owner-grant response `OAuthGrantedScope` from ordinary request
  `OAuthScope`. Response metadata includes MCP-only `live.queue.stage` and
  `live.rename`; ordinary request scope metadata remains unchanged.
- Refresh the pinned public contract and inventory to 89 REST bindings and 111
  schemas, including MCP issuer metadata and probe response definitions. Lua
  constructors retain the same wire table shape and do not confer permissions
  or perform runtime schema validation.
- Add reproducible Lua-native contract generation and an exact regeneration gate.
- Publish tagged source releases through GitHub Actions and expand the package
  description to describe Bibleit reading and sharing workflows.

## 0.0.1

- Use a standard root rockspec filename so bare `luarocks test` discovers it.
- Run SDK and TLS tests together through `luarocks test`, using LuaUnit.
- Use LuaUnit and native LuaRocks commands; remove custom tooling.
- Use dkjson directly as the sole JSON dependency; remove the SDK JSON module
  and public export. JSON values use the library's native representations.
- Preserve SSH integers outside the safe numeric range as decimal strings.
- Expose resource operations through `bibleit.new_client` and SSH helpers through
  `bibleit.new_ssh_client`, keeping transport implementations internal.
- Implement all 88 resource REST operations and metadata/constructors for 105 schemas.
- Add streaming HTTPS, structured errors, conditional/idempotent request options,
  lazy book pagination and versioned Live event polling.
- Add registered OAuth and official CLI browser credential exchange/revocation.
- Add validated SSH commands, finite response decoders and typed domain helpers.
- Add shared protocol fixtures and Lua 5.1–5.5/LuaJIT checks.
- Add LuaLS formatting, LuaRocks packaging and CLI publishing with temporary API keys.
