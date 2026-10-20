# Shared public contract

`openapi.json` is the public Bibleit OpenAPI contract used by the Go SDK.
The Lua metadata covers the 88 operations marked with the REST server and
retains all 105 schema definitions. Browser/OAuth endpoints have separate
handwritten clients.

The request and response fixtures in `fixtures/` are shared protocol examples
from [bibleit-go](https://github.com/bibleit-labs/bibleit-go). Actor IDs, tokens,
secrets and domains in fixtures are synthetic examples. Serialized server terms
are expectations only; clients never execute or evaluate them.

Update the metadata alongside contract changes and run `make check`. LuaUnit
verifies operation bindings and schema metadata against the checked-in contract.
Files remain independent of any sibling checkout.

The repository MIT license applies; see `docs/THIRD_PARTY_NOTICES`.
