# Shared public contract

`openapi.json` is the public Bibleit OpenAPI contract used by the Go SDK.
The Lua metadata covers the 89 operations marked with the REST server and
retains all 111 schema definitions. Browser/OAuth endpoints have separate
handwritten clients.

The request and response fixtures in `fixtures/` are shared protocol examples
from [bibleit-go](https://github.com/bibleit-labs/bibleit-go). Actor IDs, tokens,
secrets and domains in fixtures are synthetic examples. Serialized server terms
are expectations only; clients never execute or evaluate them.

Update the metadata alongside contract changes and run `make check`. LuaUnit
verifies operation bindings and schema metadata against the checked-in contract.
Files remain independent of any sibling checkout.

The repository MIT license applies; see `docs/THIRD_PARTY_NOTICES`.

Run `make generate` after updating the pinned contract. The Lua-native generator
retains empty objects/arrays and JSON nulls, and `make check` verifies exact
regeneration. Grant response metadata references `OAuthGrantedScope`, which can
contain MCP-only staging/rename scopes; ordinary request `OAuthScope` remains
separate. Constructors preserve representation and do not confer permission or
perform runtime schema validation. Existing wire JSON and table shapes are unchanged.
