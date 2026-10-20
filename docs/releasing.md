# Release through LuaRocks CLI

The Lua SDK starts at **0.0.1**, independently of Go SDK versions.
Package: `bibleit`; Git tag: `v0.0.1`; LuaRocks version: `0.0.1-1`.

`bibleit-0.0.1-1.rockspec` is the package specification. LuaRocks requires the
`name-version-revision.rockspec` filename and discovers it at the repository
root. Users install `bibleit`. Use LuaRocks 3.13+ for development and releases.

## Prepare

1. Run `make check` (all SDK/TLS tests through LuaRocks) and the runtime CI matrix.
2. Review the changelog, notices, API inventory and public documentation.
3. Run `luarocks lint bibleit-0.0.1-1.rockspec`.
4. Commit the source and working specification. Tag the reviewed commit
   `v0.0.1` and push the commit and tag. The source tag must be publicly fetchable.
   Keep published tags immutable.

`make package` builds an installable `.all.rock` archive from the current checkout
for local testing. A release uses a `.src.rock` fetched from the published tag.
The archive contains only the modules/docs declared in the rockspec, with the
license included in the documentation.

## Publish

To publish from GitHub Actions, configure the repository secret
`LUAROCKS_API_KEY`, then push a version tag such as `v0.0.2`. The **Publish to
LuaRocks** workflow runs automatically. You can also run it manually with the
release version (without `v`). Both options check out the tag, run all tests,
and upload the source rock using the secret. Published versions cannot be
uploaded again; choose an unpublished version when running it manually.

Set `LUAROCKS_API_KEY` in the environment or a CI secret. An ignored `.env` file
can store the key locally; load it into your environment before running:

```sh
make publish VERSION=0.0.1
```

The target runs the checks, packs the public source tag, and calls the LuaRocks
CLI with `--temp-key` so the credential is not saved. Review the source archive
before upload. The SDK runtime never reads publishing credentials.

For manual CLI publishing, after reviewing and testing the archive:

```sh
mkdir -p dist
(cd dist && luarocks pack ../bibleit-0.0.1-1.rockspec)
luarocks upload bibleit-0.0.1-1.rockspec dist/bibleit-0.0.1-1.src.rock \
  --temp-key "$LUAROCKS_API_KEY"
```

The first upload creates the module if its name is available. Verify installation
from the registry afterward. Increment the rockspec revision for packaging-only
corrections; do not use `--force` to replace published releases.

## Future versions

Update the source `_VERSION`, rockspec filename/version/tag, Makefile default and
version references together. Generate artifacts with `VERSION=X.Y.Z`. Keep
Lua SDK versions independent; record upstream contract changes in the changelog.

References: [LuaRocks creation/upload guide](https://github.com/luarocks/luarocks/blob/main/docs/creating_a_rock.md),
[rockspec format](https://github.com/luarocks/luarocks/blob/main/docs/rockspec_format.md),
and [upload page](https://luarocks.org/upload).
