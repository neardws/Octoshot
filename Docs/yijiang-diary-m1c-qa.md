# 一酱日记 M1c QA — #118

## Status / merge gate

This draft implements optional model management, the bounded native MLX call path,
grounded per-window roast preparation, daily failure fallback, and offscreen UI QA.
**M1c is not fully accepted:** the resolved `mlx-swift-lm` 2.31.3 registry lacks
MiniCPM's `minicpmv4_6` architecture. The config-only loader test reproduces
`Unsupported model type: minicpmv4_6`, before any weights/tokenizer load. A native
model/processor implementation or a separately approved runtime is still required.
Do not merge until that blocker is resolved and Neil reviews the offscreen previews.
No real MiniCPM weights were downloaded; no live inference, peak-memory, or latency
claim is made. The ≤3GB peak / ≤3s hot-latency acceptance checks remain pending.

## Behavior and deliberate limits

- Diary opt-in does not require a model download. Settings offers text-only or
  MiniCPM (~2.2GB); the runtime limitation is visible before download. Existing
  users may opt in later. SmolVLM2's Ask AI defaults/caps are unchanged.
- Downloads use HF's paginated runtime-file listing, size checks, streamed SHA256
  for LFS files, a 512MiB free-space reserve, atomic per-file promotion and a final
  verified manifest. Resume skips verified complete files; partial files restart.
  Progress labels distinguish current-file bytes from overall verified-file progress.
- Prompts use bounded AX/OCR skeleton fields only. Optional already-existing local
  frames are restricted to `Diary/frames`, ≤8MiB, then downsampled to ≤448px; no
  capture API is called. Missing/deleted frames simply use text-only input.
- For enforceable grounding, the model must choose a verbatim skeleton anchor
  (≤14 characters) plus one of three non-factual snark endings. The gate only accepts
  that exact single Chinese-dominant sentence, ≤40 characters. This intentionally
  trades creative variety for auditable no-new-facts behavior; it is not a claim
  that regex can detect arbitrary hallucinations. Bad, repeated, English, insulting
  free-form, long, or invented output is dropped rather than rewritten.
- A serial service prepares `DiaryRoastProvider` values for the synchronous report
  builder. Text-only is the production fallback; the original placeholder provider
  remains available. Closing roast is deliberately nil, with no empty UI section.
- Every inference gets a fresh session, 64-token cap, shared loader's 256MiB GPU
  cache cap, 30s deadline and 300s idle unload. Reusing the loader's one-request guard
  avoids retaining separate Ask AI/diary model containers. Deletion does not cancel
  an active Ask AI call. Timeouts are cooperative: cancellation waits for the backend
  to unwind before another call; this is not a hard process/GPU kill or RSS bound.
- Three consecutive load/deadline/quality failures disable roasts for the local
  calendar day, persisted across app restarts. Success resets the counter; the next
  local day resets it. Settings explains the failure, and skeleton reports still build.

## Reproduce (offline fixtures; no TCC)

Run from this worktree. Reuse an already-cached Swift package checkout in
`DerivedData/SourcePackages`; no Hugging Face access or model weights are needed.

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
```

For focused tests, add `-only-testing:OctoshotCoreTests/DiaryMiniCPMTests`,
`-only-testing:OctoshotCoreTests/YijiangDiaryReportTests`, and
`-only-testing:OctoshotCoreTests/MLXVLMLoaderTests` to the test command.
The config-only architecture-blocker test deliberately records the current missing
implementation; replace that expectation when adding real MiniCPM support.

## Verification receipt — 2026-10-28

- XcodeGen and dependency-backed Debug app build passed (`EMBEDDED_MLX` enabled).
- Core XCTest suite: 234 executed, 232 passed, 2 skipped, 0 failures. Includes 23 new
  offline MiniCPM tests and the new config-only architecture rejection probe.
- An earlier full run caught missing localization wrappers in the new pane; fixed
  with English keys / Simplified Chinese translations, then the full suite passed.
- Harness exits before the normal App lifecycle, notification scheduling, recording,
  AX access, or Keychain reads. It renders synthetic SwiftUI content using offscreen
  view bitmap caching, not ScreenCaptureKit or desktop screenshots.
- PNGs are in `build/diary-qa/previews/`, copied to
  `/Users/neardws/octoshot-wt/diary-m1c-preview/`: `settings-diary.png`,
  `settings-diary-progress.png`, `settings-diary-installed.png`,
  `diary-report-full.png`, `diary-report-empty.png`. Settings variants are synthetic;
  report bubbles use synthetic model-style strings passed through the real gate.
- Neil: review the red AppIcon, tone, per-window facts/bubbles, text-only empty state,
  download/progress/delete controls, runtime warning and daily-disable explanation.
  Interactive downloads, deletion, enabling notifications and real model performance
  have not been exercised. Logs/previews/DerivedData are ignored, not committed.
