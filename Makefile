LUA ?= lua
LUAROCKS ?= luarocks
VERSION ?= 0.0.1
ROCKSPEC = bibleit-$(VERSION)-1.rockspec

.PHONY: init test-deps test check package publish
init:
	$(LUAROCKS) --tree ./lua_modules init bibleit $(VERSION) --no-gitignore --output $(ROCKSPEC)

test-deps:
	$(LUAROCKS) --tree ./lua_modules show luaunit 3.5-1 > /dev/null 2>&1 || $(LUAROCKS) --tree ./lua_modules install luaunit 3.5-1

test:
	$(LUA) tests/sdk_test.lua $(TEST_ARGS)

check:
	$(LUAROCKS) lint $(ROCKSPEC)
	$(LUAROCKS) --tree ./lua_modules make $(ROCKSPEC)
	$(LUAROCKS) --tree ./lua_modules test

package: check
	mkdir -p dist
	$(LUAROCKS) --tree ./lua_modules pack bibleit $(VERSION)-1
	mv bibleit-$(VERSION)-1.*.rock dist/

# Load the ignored .env key into the environment before invoking this target.
publish: check
	@test -n "$$LUAROCKS_API_KEY" || (echo "Set LUAROCKS_API_KEY in the environment." >&2; exit 1)
	mkdir -p dist
	cd dist && $(LUAROCKS) pack ../$(ROCKSPEC)
	@$(LUAROCKS) upload $(ROCKSPEC) dist/bibleit-$(VERSION)-1.src.rock --temp-key "$$LUAROCKS_API_KEY"
