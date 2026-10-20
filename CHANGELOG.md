# Changelog

## Unreleased

- Use a standard root rockspec filename so bare `luarocks test` discovers it.

- Run SDK and TLS tests together through `luarocks test`, using LuaUnit.
- Use LuaUnit and native LuaRocks commands; remove custom tooling.
- Use dkjson directly as the sole JSON dependency; remove the SDK JSON module
  and public export. JSON values use the library's native representations.
- Preserve SSH integers outside the safe numeric range as decimal strings.

## 0.0.1

- Expose resource operations through `bibleit.new_client` and SSH helpers through
  `bibleit.new_ssh_client`, keeping transport implementations internal.
- Implement all 88 resource REST operations and metadata/constructors for 105 schemas.
- Add streaming HTTPS, structured errors, conditional/idempotent request options,
  lazy book pagination and versioned Live event polling.
- Add registered OAuth and official CLI browser credential exchange/revocation.
- Add validated SSH commands, finite response decoders and typed domain helpers.
- Add shared protocol fixtures and Lua 5.1–5.5/LuaJIT checks.
- Add LuaLS formatting, LuaRocks packaging and CLI publishing with temporary API keys.
