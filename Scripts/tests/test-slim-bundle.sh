#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="${1:-$ROOT/build/llama-mtmd/bin}"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
INSTALL="$ROOT/Scripts/install-llama-mtmd.sh"

bash "$INSTALL" "$SOURCE" "$TEMP/Helpers"
test "$(find "$TEMP/Helpers" -type f -name '*.dylib' | wc -l | tr -d ' ')" = 9
test "$(find "$TEMP/Helpers" -type l | wc -l | tr -d ' ')" = 18
test "$(readlink "$TEMP/Helpers/libggml.dylib")" = libggml.0.dylib
test "$(readlink "$TEMP/Helpers/libggml.0.dylib")" = libggml.0.26.0.dylib
test ! -e "$TEMP/Helpers/libllama-server-impl.dylib"

touch "$TEMP/Helpers/octoshot" "$TEMP/Helpers/libllama-server-impl.dylib"
rm "$TEMP/Helpers/libggml.dylib"
cp "$SOURCE/libggml.dylib" "$TEMP/Helpers/libggml.dylib"
bash "$INSTALL" "$SOURCE" "$TEMP/Helpers"
test -L "$TEMP/Helpers/libggml.dylib"
test ! -e "$TEMP/Helpers/libllama-server-impl.dylib"
test -f "$TEMP/Helpers/octoshot"

ditto "$SOURCE" "$TEMP/broken"
rm "$TEMP/broken/libggml.0.26.0.dylib"
if bash "$INSTALL" "$TEMP/broken" "$TEMP/Helpers" >"$TEMP/error" 2>&1; then
  echo "Missing dependency was accepted" >&2
  exit 1
fi
test -f "$TEMP/Helpers/libggml.0.26.0.dylib"
grep -q 'Missing library' "$TEMP/error"

cp "$SOURCE/libggml.0.26.0.dylib" "$TEMP/broken/"
ln -s libggml.0.26.0.dylib "$TEMP/broken/libggml-new-backend.dylib"
if bash "$INSTALL" "$TEMP/broken" "$TEMP/Helpers" >"$TEMP/error" 2>&1; then
  echo "Unreviewed dynamic backend was accepted" >&2
  exit 1
fi
grep -q 'Unreviewed dynamically loadable' "$TEMP/error"
rm "$TEMP/broken/libggml-new-backend.dylib" "$TEMP/broken/libggml.0.dylib"
ln -s libggml.dylib "$TEMP/broken/libggml.0.dylib"
if bash "$INSTALL" "$TEMP/broken" "$TEMP/Helpers" >"$TEMP/error" 2>&1; then
  echo "Cyclic symlink was accepted" >&2
  exit 1
fi

ditto -c -k --keepParent "$TEMP/Helpers" "$TEMP/Helpers.zip"
ditto -x -k "$TEMP/Helpers.zip" "$TEMP/unzip"
test -L "$TEMP/unzip/Helpers/libggml.dylib"
test -f "$TEMP/unzip/Helpers/libggml.dylib"
echo "PASS: closure, symlinks, incremental cleanup, missing dependency, new backend, cycle, zip round-trip"
