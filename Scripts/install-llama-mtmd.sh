#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?Usage: install-llama-mtmd.sh SOURCE_BIN DEST_BIN}"
DEST="${2:?Usage: install-llama-mtmd.sh SOURCE_BIN DEST_BIN}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

fail() { echo "error: $* (refresh with Scripts/fetch-llama-mtmd.sh)" >&2; exit 1; }

copy_library() {
  local name="$1" target
  case "$name" in
    */*|.|..) fail "Non-adjacent library: $name" ;;
  esac
  [ ! -e "$STAGE/$name" ] && [ ! -L "$STAGE/$name" ] || return 0
  if [ -L "$SOURCE/$name" ]; then
    target="$(readlink "$SOURCE/$name")"
    cp -P "$SOURCE/$name" "$STAGE/$name"
    copy_library "$target"
  elif [ -f "$SOURCE/$name" ]; then
    cp -P "$SOURCE/$name" "$STAGE/$name"
  else
    fail "Missing library: $name"
  fi
}

[ -x "$SOURCE/llama-mtmd-cli" ] || fail "Missing llama-mtmd-cli"
cp -P "$SOURCE/llama-mtmd-cli" "$STAGE/llama-mtmd-cli"
for library in libllama libllama-common libmtmd libggml libggml-base libggml-cpu libggml-blas libggml-metal libggml-rpc; do
  [ -L "$SOURCE/$library.dylib" ] || fail "Expected canonical symlink: $library.dylib"
  copy_library "$library.dylib"
done

for backend in "$SOURCE"/libggml-*.dylib; do
  [ -e "$STAGE/$(basename "$backend")" ] || fail "Unreviewed dynamically loadable ggml backend: $backend"
done

for item in "$STAGE"/*; do
  [ -e "$item" ] || fail "Broken or cyclic symlink: $item"
  [ ! -L "$item" ] || continue
  [ "$(lipo -archs "$item")" = arm64 ] || fail "Expected arm64-only Mach-O: $item"
  loads="$(otool -L "$item")"
  rpaths="$(otool -l "$item" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }')"
  [ "$rpaths" = '@loader_path' ] || fail "Unexpected runtime search path in $item: $rpaths"
  while IFS= read -r dependency; do
    case "$dependency" in
      @rpath/*|@loader_path/*)
        name="${dependency#*/}"
        case "$name" in */*) fail "Non-adjacent dependency: $dependency" ;; esac
        [ -f "$STAGE/$name" ] || fail "Unbundled dependency: $dependency in $item"
        ;;
      /usr/lib/*|/System/Library/*) ;;
      *) fail "Unexpected dependency: $dependency in $item" ;;
    esac
  done < <(printf '%s\n' "$loads" | sed '1d; s/^[[:space:]]*//; s/ (compatibility version.*//')
done

mkdir -p "$DEST"
find "$DEST" -maxdepth 1 \( -name 'libllama*.dylib' -o -name 'libggml*.dylib' -o -name 'libmtmd*.dylib' -o -name 'llama-mtmd-cli' \) \( -type f -o -type l \) -delete
cp -P "$STAGE"/* "$DEST/"
