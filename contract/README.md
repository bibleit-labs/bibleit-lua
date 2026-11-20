# Shared public contract

`openapi.json` is the public Bibleit OpenAPI contract used by the Go SDK.
The Lua metadata covers the 110 operations marked with the REST server and
retains all 146 schema definitions. Browser/OAuth endpoints have separate
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

The current snapshot is the server workspace-read contract from merged Broadcast
commit `3f9739cf153ce263ca6ddd59c4ac701af85f017a`, SHA-256
`a4f30711e0b588a5d4f3344daefbbbc470fe5f8dd71c4698c93aa12101f01692`.
It adds `broadcast.get` only to MCP metadata and owner-grant response scopes,
plus the optional single-workspace probe projection and its bounded models.
Ordinary OAuth request scope metadata and all REST operation bindings stay
unchanged. Consumers performing strict validation against exported `model.schema`
metadata need this updated catalogue before processing expanded responses.
Representation-preserving constructors still perform no authorization or runtime
schema validation. Updating the package does not enable Broadcast or upgrade a grant.
