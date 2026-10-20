# Contributing

Keep SDK code and tests in Lua, using Lua 5.1-compatible syntax. Use
[LuaUnit](https://github.com/bluebird75/luaunit) for assertions, test execution
and fixture setup/cleanup. `make test-deps` installs it for development;
`make test` runs the SDK and TLS suites together through LuaUnit.

Use LuaRocks 3.13+ and run `make check` before submitting changes. It invokes `luarocks test` for all
SDK and TLS tests. TLS fixtures use
LuaSocket, LuaSec and OpenSSL with disposable certificates on loopback.
CI exercises Lua 5.1–5.5 and LuaJIT 2.1.

Format Lua in VS Code with the `sumneko.lua` language server, using the
checked-in EditorConfig and VS Code settings.

Keep the contract and operation/schema metadata in sync. The LuaUnit contract
coverage tests verify all operations and schemas against `contract/openapi.json`.
Update `docs/api-parity.md` when coverage changes.

SDK code must not read CLI/environment credentials, change pinned origins, retry
requests automatically, or persist tokens. Keep docs/examples suitable for a
public repository. Do not commit local environment files, credentials, absolute
workspace paths or private service diagnostics.

Use Conventional Commits, for example `feat: add a resource method`,
`fix: handle response errors` or `test: add pagination coverage`.

The Lua SDK versions independently from other language clients. Follow
[releasing](docs/releasing.md) for tagged source rocks and CLI uploads.
