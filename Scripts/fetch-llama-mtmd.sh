#!/usr/bin/env bash
# Downloads a pinned llama.cpp macOS binary tarball and exposes llama-mtmd-cli for embedding.
set -euo pipefail

LLAMA_CPP_RELEASE="${LLAMA_CPP_RELEASE:-b11514}"
DEST="${1:-${PROJECT_DIR:-$(pwd)}/build/llama-mtmd}"

TARBALL="llama-${LLAMA_CPP_RELEASE}-bin-macos-arm64.tar.gz"

URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_CPP_RELEASE}/${TARBALL}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ARCHIVE="${LLAMA_TARBALL:-$TMP/archive.tar.gz}"
if [[ -z "${LLAMA_TARBALL:-}" ]]; then
  echo "Fetching ${URL}"
  curl -fsSL "$URL" -o "$ARCHIVE"
fi
mkdir -p "$TMP/extract" "$DEST"
tar -xzf "$ARCHIVE" -C "$TMP/extract"

CLI="$(find "$TMP/extract" -type f -name 'llama-mtmd-cli' | head -1)"
if [[ -z "$CLI" ]]; then
  echo "llama-mtmd-cli not found in archive" >&2
  exit 1
fi

BIN_DIR="$(dirname "$CLI")"
bash "$(dirname "$0")/install-llama-mtmd.sh" "$BIN_DIR" "$DEST/bin"

echo "Installed llama-mtmd-cli at $DEST/bin/llama-mtmd-cli"
