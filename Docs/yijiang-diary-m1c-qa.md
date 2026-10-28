# 一酱日记 M1c QA — optional local Ollama / #118

## Status and scope

PR #119 **stays draft**. Do not merge, mark ready, or release. Neil must review the
offscreen previews. This change replaces the unusable diary MLX MiniCPM-V-4.6 path
with an optional user-managed local Ollama HTTP client. It does not prove real-model
performance or acceptance: no Ollama installation/start, model pull, live inference,
TCC authorization, capture, or LaunchAgent is part of this QA.

## Runtime contract

- Default model: `openbmb/minicpm-v4.7:1b`, approximately 1.8GB Q4_K_M. Never default
  to `latest` (22GB 35B-A3B). Users may override the exact model/tag in Settings.
- Require Ollama ≥ `0.40.5` before chat; earlier releases lack the `minicpmv4_7`
  projector. Numeric semantic comparison handles suffixes: `0.40.5-rc1` is older
  than stable `0.40.5`; `0.40.6-rc1` is newer; build metadata does not affect ordering.
- `GET /api/version` then `GET /api/tags` distinguishes not-running, version-too-old
  (with found version), model-missing, ready, and malformed/HTTP-error states. Model
  matching is exact, including `:1b`; another tag is not silently selected.
- UserDefaults: `diary.ollama.baseURL`, `diary.ollama.model`; default base address
  `http://127.0.0.1:11434`. Only localhost/127.0.0.1/::1 HTTP(S) endpoints are accepted.
  Default ephemeral URLSession rejects redirects. No cloud fallback or credentials.
- `POST /api/chat`: `stream:false`, `think:false`, system constraints + bounded AX/OCR
  user skeleton, optional `images:[base64]`, `num_predict:64`, `temperature:0.7`,
  `keep_alive:"2m"`. HTTP timeout and per-window service deadline default to 30s.
  Cancellation is cooperative, not a process kill; queue waits preserve serialization.
  A single static chat queue covers settings tests and report clients. Status-only GET
  probes may run independently; they never trigger inference.
- Existing keyframes only: regular files directly under `Diary/frames`, no symlinks,
  ≤8MiB, resized to ≤448px JPEG. Missing frames use text only; no capture API is called.
- Facts only come from AX/OCR skeletons, never VLM output. After stripping complete
  `<think>...</think>` blocks, accept only a verbatim ≤14-character skeleton anchor
  plus an approved non-factual ending, one Chinese-dominant sentence ≤40 characters.
  Unclosed thinking, English, repeated, long, insulting/free-form or fabricated output
  is discarded. This conservative gate is not general hallucination detection.
- Failed output uses the existing rule-based placeholder provider; skeleton facts,
  durations, empty-day behavior and text/Markdown reporting are preserved. Rule-based
  placeholders are not model output and retain their existing length/style. Closing
  model roast stays nil. Three consecutive failures persist under
  `diary.ollama.failureState`; success clears the counter, next local day resets it.
- The existing `diary.minicpm.enabled` preference is intentionally retained so an
  existing opt-in survives; new users default off. Failure state is separate from MLX.
- Settings has Chinese translations and English fallback keys: status, address/model
  fields, install/download link, copyable default pull command, recheck, and synthetic
  “test one roast” (only ready, not busy, and not daily-disabled). No automatic pull.
- Removed diary MLX download/progress/delete UI and MLX inference adapter. Legacy
  catalog/download tests and architecture probe remain; SmolVLM2/Ask AI is unchanged.

## Reproduce — offline mocks, no TCC

From this worktree, use the cached packages in `DerivedData/SourcePackages`:

```sh
xcodegen generate
xcodebuild -project Octoshot.xcodeproj -scheme OctoshotCoreTests \
  -configuration Debug -derivedDataPath "$PWD/DerivedData" -destination 'platform=macOS' \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation test
xcodebuild -project Octoshot.xcodeproj -scheme Octoshot \
  -configuration Debug -derivedDataPath "$PWD/DerivedData" -destination 'platform=macOS' \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation build
mkdir -p "$PWD/build/diary-qa/previews"
OCTOSHOT_QA_SNAPSHOT_DIR="$PWD/build/diary-qa/previews" \
OCTOSHOT_QA_SNAPSHOT_DIARY=1 OCTOSHOT_QA_SNAPSHOT_LOCALE=zh-Hans \
  "$PWD/DerivedData/Build/Products/Debug/Octoshot.app/Contents/MacOS/Octoshot"
COPYFILE_DISABLE=1 /usr/bin/zip -j /tmp/m1c-ollama-preview.zip \
  build/diary-qa/previews/settings-ollama-*.png \
  build/diary-qa/previews/diary-report-{full,empty,fallback}.png
git diff --check
```

When replacing an existing zip, remove that exact archive first to avoid retaining
stale members. The harness exits before normal App lifecycle, notification requests,
AX/ScreenCaptureKit and Keychain reads. It renders synthetic SwiftUI views with an
offscreen NSHostingView, never captures the desktop. All HTTP uses an injected fake
transport, including full-report chat output and connection-failure fallback. Preview
settings suppress rechecks and mutation, use isolated coordinator defaults, and do not
persist opt-in. The test suite also exercises URLSession with a mock URLProtocol.

## Preview manifest

Output directory: `build/diary-qa/previews/`; archive: `/tmp/m1c-ollama-preview.zip`.

- `settings-ollama-not-running.png`
- `settings-ollama-version-too-old.png`
- `settings-ollama-model-missing.png`
- `settings-ollama-ready.png`
- `settings-ollama-disabled.png`
- `diary-report-full.png` — mock `/api/chat` output through real quality gate
- `diary-report-empty.png`
- `diary-report-fallback.png` — mock connection failures, daily breaker, rule roasts

Neil: check state wording, fixed `:1b` pull command, red AppIcon, per-window
facts vs. roast bubbles, empty-day copy, and daily-disable explanation.

## Verification receipt — 2026-10-28

- Full local Core XCTest suite: 256 executed, 254 passed, 2 skipped, 0 failures;
  includes 22 new `DiaryOllamaTests`, all passing. Skips are existing case-sensitive
  filesystem and opt-in GPU tests, not Ollama tests.
- Dependency-backed Debug `Octoshot` build (`EMBEDDED_MLX` enabled): passed.
- Offscreen harness: exit 0; all eight PNGs visually checked (four availability states,
  daily-disable reason, full mock report, empty day and fallback report).
- `git diff --check`: clean before commit.

GitHub CI results and final tip are recorded in
`/tmp/codex-m1c-ollama-result.md` and PR #119. Local logs live in
`build/diary-qa/ollama-tests.log` and `build/diary-qa/ollama-build.log` (ignored).
Real model memory, latency, real-output quality and interactive installation/pull
remain deliberately untested. A successful build or mock preview is not live-model
acceptance; keep the PR draft until separately reviewed.
