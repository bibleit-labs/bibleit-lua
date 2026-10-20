# Lua API

## Conventions and parity

Load `bibleit` and construct a resource client with `new_client` or a command
client with `new_ssh_client`. Transport implementations are internal. Go exported names
map to snake_case: `GetPersonalIdentity` becomes `get_personal_identity`.
Constructors return `client, err`; methods return `result, err`. Success-only
operations return `true`. Errors have a `kind` plus relevant metadata;
`tostring(err)` excludes untrusted server detail. `err:retry_after()` returns
seconds. Protocol fields and unknown server codes remain available.

Context is the final optional argument. For REST methods, options precede it:
`client:get_live(live_id, options, context)`. Path identifiers are strings.
`bibleit.context.new({deadline=unix_seconds})` creates a context;
`context:cancel()` cancels it. The synchronous default transport checks context
between I/O operations and applies remaining deadlines to blocking calls.
Cancellation does not interrupt an already blocking DNS/socket call immediately;
use an injected event-loop transport when immediate cooperative cancellation or
concurrent polling is needed. No background tasks are started.

## REST

`bibleit.new_client(token, transport)` creates a resource client. An empty
token permits public discovery. The endpoint is fixed to
`https://api.bibleit.app/v1`; changing the informational `endpoint` field does
not change request destinations.

`bibleit.operation_names()` and `bibleit.operations()` expose copies of the complete
operation directory. Every ID has a snake_case wrapper whose path parameters
follow their order in the URL. `get_open_api` covers both Go OpenAPI spellings.
For example:

```lua
local response, err = client:read_personal_verse(account_id, "web", "43", "3", "16")
```

Options are a table:

| Key | Meaning |
| --- | --- |
| `query` | Query values as strings or lists of strings |
| `json` | JSON body, including explicit `json.null` values |
| `body` | Raw string or reader with `read(max_bytes)` |
| `content_type`, `content_length` | Raw upload media type and exact byte count |
| `if_match` | Exact ETag from the previous response |
| `idempotency_key` | Explicit key where supported by the operation |
| `destination_token` | Additional destination service token for workspace moves |
| `range` | Binary response byte range |

`json` and `body` are mutually exclusive. Raw bodies require `content_length`.
Response objects expose `status_code`, lower-case `headers`, `body`,
`read(max_bytes)`, `decode()` and `close()`. `decode()` reads at most 4 MiB.
Always close successful responses, including after decoding. Stream binary
responses with repeated `read()` calls; `nil` without an error means EOF.
HTTP failures close their bodies and return `kind="problem"` errors preserving
`status`, `code`, `request_id`, `headers` and optional `detail`.

`read_personal_book_pages(account_id, slug, book_id, options, context)` and
`read_book_pages(organization_id, slug, book_id, options, context)` return lazy
closures. Call the closure repeatedly to receive `page, err`. On an error it
returns `nil, err` once, then finishes; normal completion is `nil, nil`.
Do not use a generic `for` loop, which would discard a `nil, err` failure.
They default to 50 verses and accept a 1–500 limit; copy caller options; close
bodies before returning pages; and reject malformed, looping or inconsistent
pages. Stopping calls stops fetching. A failed traversal is incomplete.

`poll_live_events(live_id, after, wait, context)` performs one request with a
0–25 second wait and validates event version, resource, cursor and data presence.
It returns snapshots or heartbeats without a retry loop. Poll on a separate
execution context/transport from mutations.

## JSON and models

The SDK uses [dkjson](https://dkolf.de/dkjson-lua/documentation) directly.
LuaRocks installs it as a dependency. Applications can `require("dkjson")`;
the SDK does not expose a JSON module or custom JSON value types.

Use `dkjson.null` for explicit nulls; missing keys are omitted. Decoded arrays
and objects carry dkjson's `__jsontype` metatable. To specify an empty request
object or array explicitly, use the library's native representation:

```lua
local json = require("dkjson")
local object = setmetatable({}, { __jsontype = "object" })
local array = setmetatable({}, { __jsontype = "array" })
```

Unmarked tables follow dkjson's encoding rules, including empty tables becoming
arrays. Model constructors mark their object/array representation automatically.
`response:decode()` preserves nulls, false values and unknown fields, checks
UTF-8 and rejects trailing input. Library parse errors use the SDK's normal
`nil, error` return convention.

JSON numbers use dkjson's native Lua numbers, with the active runtime's precision
and formatting. Lua 5.1/LuaJIT cannot represent every integer above 2^53 exactly.
For an alternate numeric representation, read the response body and decode it
with an application-selected library, or supply a pre-encoded raw request body.
SSH int64 metadata outside the cross-runtime safe range is returned as decimal
strings to preserve the exact value.

`models.names()` lists all schemas; `models.schema(name)` returns copied OpenAPI
metadata. `models.SchemaName(value)` / `models.new(name, value)` copy a wire value
into its Lua representation. Like the Go structs, these do not replace server
validation. Enums and constraints are available in schema metadata.

Union helpers `models.as(union_name, member, value)`, `models.from(...)` and
`models.merge(union_name, member, current, patch)` select a referenced schema
name or a 1-based inline variant. Merge uses JSON Merge Patch semantics; null
patch members delete keys. These conversions do not introduce wrapper fields.
Use the contract discriminator to choose the variant.

## OAuth and browser credentials

`bibleit.new_oauth_client(transport)` provides:

- `metadata(context)`
- `exchange_code(client_id, code, redirect_uri, verifier, context)`
- `refresh(client_id, refresh_token, scopes, context)`
- `revoke(client_id, token, context)`

`bibleit.authorization_url(client_id, redirect_uri, state, challenge, scopes)` builds
the S256 consent URL. Applications supply cryptographically random PKCE/state,
validate callback state and store/rotate credentials. OAuth errors have
`kind="oauth"`, `code`, `description`, `status` and `headers`. The fixed website
origin receives no REST bearer credentials or cookies. Exchanges make one attempt.

For official CLI browser codes, `bibleit.new_auth_client(transport)` exposes
`exchange_code({code=..., verifier=..., device_name=...}, context)`. Results retain
original JSON in `fields`, including the issued secret. `bibleit.new_client(token,
transport):revoke_credential(context)` revokes a CLI browser credential through
the website origin. This is the same resource client used for API operations;
it cannot execute SSH commands. The `new_*_with_http_client` aliases accept the
same Lua transport argument. CLI auth errors use `kind="http"` and retain status,
code and original fields. No credentials are read from environment or persisted.

## SSH protocol helpers

`bibleit.new_ssh_client(executor)` accepts `executor(command, context)`, returning
a parsed response or raw stdout plus an optional error. The application owns
SSH authentication, verified host keys and connection lifetime.

Command builders live in `bibleit.command` and are re-exported from `bibleit`.
They return validated objects with `string()` and `streaming()` methods; commands
are not implicitly stringified because their wire values can contain secrets.
Enums are in `live_action`, `live_field`, `secret_action` and `stack_action`.
Reference tables use `translation`, `book`, optional `chapter` and `verse`.
`set_live_command` accepts variadic strings; the typed client's `set_live` takes
a list of values followed by optional context.

`parse_record`, `decode_response` and `decode_command_response` preserve original
lines, fields and field order. Protocol record types are lower-case. Structured
SSH results retain `raw`, and entries retain original `fields`. Opaque compound
fields remain text. Finite executors reject streaming subscription commands;
persistent subscriptions require a caller-owned streaming connection.

Typed methods cover server/help/account/quotas/identity, reading/search,
translation metadata/catalogs, token metadata, organization directory/application
status, and Live state/list/stats/stack/push/pop/control. See the inventory for
all methods. Version-specific request and response escaping remains distinct.

## Transport injection

A transport is a function `request(request_table, context)` or an object with
`request(self, request_table, context)`. Requests expose `method`, fixed-origin
`url`, `headers`, `body`, and `content_length`. Return a table containing
`status_code`, `headers`, and `body` (string or reader), or `nil, err`.
Readers provide `read(max_bytes)` returning `chunk, err` and `close()` returning
`true, err`. Injection is a trusted application boundary: custom transports own
TLS verification, cancellation, concurrency and avoiding redirects/replays.

`bibleit.transport.new({timeout=40, cafile=..., capath=...})` configures the default
LuaSocket/LuaSec transport without changing origins. It uses common OS CA bundles
when available, verifies the certificate chain and DNS SAN hostname, and allows
TLS 1.2+. Supply a CA bundle explicitly on systems without a discoverable one.
