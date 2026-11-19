#!/usr/bin/env bash
# Ubuntu runners already provide gcc/make, OpenSSL headers and zip/unzip:
# https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md
# Build verified upstream sources privately; SDK/TLS/package coverage is unchanged.
set -euo pipefail
release="${1:?usage: ci-toolchain.sh <Lua release|luajit>}"
: "${RUNNER_TEMP:?GitHub runner temporary directory is required}"
prefix="$RUNNER_TEMP/bibleit-lua-$release"
work="$RUNNER_TEMP/bibleit-lua-source-$release"
mkdir -p "$prefix" "$work"
for tool in gcc make curl tar git sha256sum openssl zip unzip; do command -v "$tool" >/dev/null; done
[[ -r /usr/include/openssl/ssl.h ]]
fetch() { curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' "$1" -o "$2"; }
if [[ "$release" == luajit ]]; then
  # Immutable commit from the official LuaJIT v2.1 line, never a moving ref.
  revision=63c8f1a9b479ba5518cf6a170ff7729178bc3cfd
  git init "$work/luajit"
  git -C "$work/luajit" remote add origin https://github.com/LuaJIT/LuaJIT.git
  git -C "$work/luajit" fetch --depth=1 origin "$revision"
  git -C "$work/luajit" checkout --detach FETCH_HEAD
  [[ "$(git -C "$work/luajit" rev-parse HEAD)" == "$revision" ]]
  make -C "$work/luajit" -j2 PREFIX="$prefix"
  make -C "$work/luajit" install PREFIX="$prefix"
  ln -s luajit "$prefix/bin/lua"
  version=5.1
  include="$prefix/include/luajit-2.1"
else
  # SHA-256 values published at https://www.lua.org/ftp/.
  case "$release" in
    5.1.5) checksum=2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333 ;;
    5.2.4) checksum=b9e2e4aad6789b3b63a056d442f7b39f0ecfca3ae0f1fc0ae4e9614401b69f4b ;;
    5.3.6) checksum=fc5fd69bb8736323f026672b1b7235da613d7177e72558893a0bdcd320466d60 ;;
    5.4.8) checksum=4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae ;;
    5.5.1) checksum=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce ;;
    *) printf 'Unsupported Lua release: %s\n' "$release" >&2; exit 2 ;;
  esac
  archive="$work/lua.tar.gz"
  fetch "https://www.lua.org/ftp/lua-$release.tar.gz" "$archive"
  printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check -
  tar -xzf "$archive" -C "$work"
  # POSIX + dynamic modules, without an interactive readline dependency.
  make -C "$work/lua-$release/src" all -j2 \
    MYCFLAGS='-fPIC -DLUA_USE_POSIX -DLUA_USE_DLOPEN' MYLIBS=-ldl MYLDFLAGS=-Wl,-E
  make -C "$work/lua-$release" install INSTALL_TOP="$prefix"
  version="${release%.*}"
  include="$prefix/include"
fi
# Published source archive; checksum also recorded by Homebrew's official formula.
archive="$work/luarocks.tar.gz"
fetch https://luarocks.org/releases/luarocks-3.13.0.tar.gz "$archive"
printf '%s  %s\n' 245bf6ec560c042cb8948e3d661189292587c5949104677f1eecddc54dbe7e37 "$archive" | sha256sum --check -
tar -xzf "$archive" -C "$work"
(cd "$work/luarocks-3.13.0" && ./configure --prefix="$prefix" --with-lua="$prefix" \
  --lua-version="$version" --with-lua-interpreter=lua --with-lua-include="$include" && make && make install)
printf '%s\n' "$prefix/bin" >> "$GITHUB_PATH"
printf 'LUA=%s/bin/lua\nLUAROCKS=%s/bin/luarocks\n' "$prefix" "$prefix" >> "$GITHUB_ENV"
"$prefix/bin/lua" -v
"$prefix/bin/luarocks" --version
