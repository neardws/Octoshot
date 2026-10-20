#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?Usage: Scripts/export-bench.sh <out_dir>}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
xcodegen generate --spec project.perf.yml > "$OUT/generate.log" 2>&1
xcodebuild -project OctoshotExportBench.xcodeproj -scheme octoshot-export-bench \
  -configuration Debug -derivedDataPath ./DerivedData-bench \
  CODE_SIGNING_ALLOWED=NO build > "$OUT/build.log" 2>&1
BIN=./DerivedData-bench/Build/Products/Debug/octoshot-export-bench
"$BIN" --developer export --out "$OUT"
"$BIN" --developer bench --out "$OUT" --iterations "${ITERATIONS:-20}"
