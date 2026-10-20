# Bibleit Lua client

Lua SDK for Bibleit REST resources, OAuth, browser authorization and SSH helpers.
Supports Lua 5.1–5.5 and LuaJIT 2.1.

```sh
luarocks install bibleit
```

Native dependencies require OpenSSL development headers.

```lua
local bibleit = require("bibleit")
local client = assert(bibleit.new_client(token))
local response, err = client:get_personal_identity()
if not response then error(tostring(err), 0) end
local identity, decode_err = response:decode()
response:close()
if not identity then error(tostring(decode_err), 0) end
print(identity.id)
```

Resource methods use snake_case names and positional path identifiers.
Close each response after reading it. See the
[API reference](docs/api.md), [parity inventory](docs/api-parity.md) and
[examples](examples).

From a checkout, use LuaRocks 3.13+ to run all tests, including TLS fixtures
(requires OpenSSL):

```sh
luarocks test
```

See [release packaging](docs/releasing.md) for building and publishing with the CLI.

Licensed under [MIT](LICENSE). See [third-party notices](docs/THIRD_PARTY_NOTICES).
