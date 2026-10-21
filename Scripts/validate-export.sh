#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT="${1:?Usage: Scripts/validate-export.sh <out_dir>}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
trap 'xcodegen generate >/dev/null' EXIT
xcodegen generate > "$OUT/generate-app.log" 2>&1
COMMON=(-project Octoshot.xcodeproj -configuration Debug -derivedDataPath ./DerivedData
        -skipPackagePluginValidation -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO)
xcodebuild "${COMMON[@]}" -scheme Octoshot build > "$OUT/app-build.log" 2>&1
xcodebuild "${COMMON[@]}" -scheme octoshot-cli build > "$OUT/cli-build.log" 2>&1
xcodebuild "${COMMON[@]}" -scheme OctoshotCoreTests test > "$OUT/tests.log" 2>&1
if [[ "${OCTOSHOT_TEST_GPU:-0}" == 1 ]]; then
  OCTOSHOT_TEST_GPU=1 xcrun xctest -XCTest ExportPipelineTests \
    ./DerivedData/Build/Products/Debug/OctoshotCoreTests.xctest > "$OUT/gpu-tests.log" 2>&1
fi
xcodegen generate --spec project.ci.yml > "$OUT/generate-ci.log" 2>&1
xcodebuild "${COMMON[@]}" -scheme Octoshot build > "$OUT/ci-build.log" 2>&1
Scripts/export-bench.sh "$OUT/benchmark"
