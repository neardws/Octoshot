# Embedded MLX VLM memory bounds — local draft

Date: 2026-10-20 (Asia/Shanghai). Base: `dad1aec`; branch: `perf/mlx-vlm-bounds`.

**Status: implementation and both Debug builds complete; GPU memory acceptance and
the requested local commit are blocked by this execution sandbox. No push or PR.**

## Root cause

The original loader retained one `ChatSession` indefinitely and used default
`GenerateParameters`. In the resolved mlx-swift-lm **2.31.3**, `maxTokens` defaults
to `nil`: a model that repeats without EOS can keep generating and growing its KV
cache. The retained session also carries KV/history across unrelated screenshots.
No GPU buffer-cache budget, idle model unloading, or temporary-PNG deletion was
configured. These are separate lifetime problems; a buffer-cache limit alone does
not bound live KV tensors.

The dependency APIs were checked in the locally cached source, then copied into
this worktree's ignored `DerivedData/SourcePackages`. Resolved mlx-swift is
**0.31.4**. Its current APIs are `MLX.Memory.cacheLimit` and `Memory.clearCache()`;
`GPU.set(cacheLimit:)` is a deprecated forwarding API.

## Changes

- `MLXVLMLoader.respond` preserves existing calls and adds defaulted arguments:
  `maxTokens: 256`, `timeout: 120` seconds (`nil` disables the timer), and
  `idleUnloadDelay: 300` seconds. Invalid limits fail before loading a model.
- Only the loaded `ModelContainer` is reused. Every request creates a new
  `ChatSession` with temperature `0.1`, repetition penalty `1.1`, and repetition
  context `64`. Session KV is explicitly cleared on success and failure before
  clearing reusable GPU buffers.
- The loader is main-actor isolated. Overlapping requests fail with a busy error
  rather than multiplying model/session memory. Directory changes reload the
  container; a failed load no longer leaves a permanently failed cached load task.
- GPU buffer cache is limited to **256 MiB** before loading; unused buffers are
  cleared after requests and unloading. This is not a total-process memory cap.
- PNG writes are atomic; a `defer` removes each request's temporary PNG.
- Caller cancellation and a one-shot timeout cancel the owned request task.
  `ChatSession.clear()` uses its serialized cache access, which waits for active
  cache work. Cancellation is cooperative, not a GPU/process kill.
- `unload()` cancels active work and drops the loader's container reference. A
  one-shot, weakly capturing idle task invokes it five minutes after completion;
  a new request cancels that timer. There is no idle polling loop.
- A Metal-device preflight reports a normal error instead of letting MLX index an
  empty device array in environments that cannot access a GPU. `unload()` does not
  initialize MLX merely to clear an unused cache.
- `LocalVLMService` forwards optional benchmark token/timeout settings through the
  same loader and propagates stream termination into request cancellation. Its
  existing protocol entry point remains unchanged.
- Debug-only `vlm-bench` requires `--developer`; it reads an image file directly,
  registers the actual `LocalVLMService.shared` backend, and bypasses CLI AppKit
  application initialization. There is no `MLXEmbeddedVisionBackend` type in this
  checkout; `LocalVLMService` is the app implementation. No parallel benchmark-only
  inference implementation was introduced.
- Each successful call prints one JSON line with `call`, `elapsedSeconds`,
  `outputChars`, `maxTokens`, `physicalFootprintBytes`, and
  `processLifetimePeakFootprintBytes`. Peak comes from
  `task_vm_info.ledger_phys_footprint_peak`, not RSS or a post-call sample. It is a
  cumulative process-lifetime peak, **not** an independently reset per-call peak.
- Both project specs link the CLI and test bundle to the embedded framework and
  compile the shared service source. The benchmark implementation, command
  dispatch, and help text are all enclosed by `#if DEBUG`.
- Added loader tests for invalid limits and pre-cancelled requests, without loading
  a model or capturing any screen content; a disabled-MLX compatibility test is
  included for that build variant.

## Before / after evidence

| Measurement | Before (operator supplied) | After (this run) |
| --- | --- | --- |
| Looping synthetic Notes/Terminal workload | 3.9 → 8.1 GB over 112 s, watchdog kill | Not measurable: no Metal device available in this sandbox |
| Earlier six-window workload | 41.5 GB | Not rerun |
| Requested three-call Notes benchmark | Unbounded generation reported | 0 completed inference calls; clean exit 1 before model load |
| Successful-call latency / output length / peak | Not supplied | Unavailable; no JSON success rows emitted |

**No memory reduction percentage, successful three-call result, or timeout/idle
runtime acceptance is claimed.** The watchdog's `0MB` startup sample is not a
measurement of model peak footprint and must not be used as an after result.

The first watchdog attempt exposed an upstream MLX startup exception:
`NSRangeException`, empty `MTL::CopyAllDevices()` array in `load_device`, reached
through `Memory.cacheLimit`. It exited 134 before inference. After adding the
device preflight, the same watchdog command exited 1 with:

```text
Error: No Metal GPU is available to this process.
```

Final watchdog evidence:
`/Users/neardws/octoshot-codex/perf-20261020/raw/fix-verify.log` and its `.stdout` /
`.stderr` siblings. The initial crash stack is retained locally in
`DerivedData/benchmark-no-device-crash.log`.

## Build and tests

`xcodegen generate --spec project.yml` succeeded. The originally requested
`xcodebuild` command was attempted, but the restricted environment blocked writes
to global SwiftPM/module caches, nested manifest/macro sandbox creation, and
automatic Metal-toolchain discovery. Local-only adaptations were needed:

1. Copy the existing Xcode SourcePackages cache into `DerivedData/SourcePackages`.
2. Redirect HOME/CFFIXED_USER_HOME and compiler caches into `DerivedData`.
3. Use `-IDEPackageSupportDisableManifestSandbox=YES` and
   `OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'` for nested build
   helpers only. The outer execution sandbox remains in effect.
4. Register the already installed Metal toolchain with a symlink under the temporary
   HOME and select `-toolchain com.apple.dt.toolchain.Metal.32023.864`.

The exact local build wrapper is `DerivedData/build-local.sh` (ignored, not a
portable project change). With those adaptations and `CODE_SIGNING_ALLOWED=NO`:

- `octoshot-cli`, Debug: **BUILD SUCCEEDED** (`DerivedData/cli-build.log`).
- `Octoshot`, Debug: **BUILD SUCCEEDED** (`DerivedData/app-build.log`). The app was
  compiled, not launched or visually checked.
- `OctoshotCoreTests`, Debug: **TEST BUILD SUCCEEDED**
  (`DerivedData/core-tests-build.log`).
- Xcode test launching failed at `com.apple.testmanagerd.control` with sandbox
  restriction error 159 (`DerivedData/core-tests.log`).
- Direct `xcrun xctest` ran **108 tests**: 106 test cases passed; two existing test
  cases failed with three reported failures. These were
  `ImageFormatsTests.testCopyToPasteboardUsesPNGType` (two assertions) and
  `RedactionCompositorTests.testDetectedEmailIsCoveredWhereItAppears` (Vision
  `nilError`). No unrelated code or tests were changed to mask these failures.
  See `DerivedData/core-tests-direct.log`.
- Targeted direct execution of `OctoshotCoreTests.MLXVLMLoaderTests`: **2 tests,
  0 failures** (`DerivedData/loader-tests.log`). GPU generation, timeout draining,
  and idle unloading remain untested at runtime.
- Watchdog-wrapped missing-`--developer` and zero-token CLI checks both failed
  correctly before inference (`DerivedData/bench-*-guard.log*`).
- Release exclusion is established by source guards, not by a Release build/run.

## GPU-capable operator verification still required

From this worktree, build normally on the operator's machine:

```sh
xcodegen generate --spec project.yml
xcodebuild -scheme octoshot-cli -configuration Debug -derivedDataPath ./DerivedData build CODE_SIGNING_ALLOWED=NO
xcodebuild -scheme Octoshot -configuration Debug -derivedDataPath ./DerivedData build CODE_SIGNING_ALLOWED=NO
```

Then run **only under the watchdog**, using the existing installed model at
`~/Library/Application Support/Octoshot/Models/smolVLM2_500M_4bit`:

```sh
/Users/neardws/octoshot-codex/perf-20261020/watch_repro.sh \
  /Users/neardws/octoshot-codex/perf-20261020/raw/fix-verify.log 8000 240 -- \
  "$PWD/DerivedData/Build/Products/Debug/octoshot" vlm-bench --developer \
  --image /Users/neardws/octoshot-codex/perf-20261020/repro3/2025-10-17T09-20-00+08:00_Notes.png \
  --prompt 'Describe this screenshot.' --repeat 3
```

The default 256-token path is intentional. This prompt was selected for this run;
the operator's original exact prompt was not provided, so this is not yet a
matched-prompt performance comparison. The watchdog script returns its final
`echo` status: inspect `exit=...` / `KILL` in its log, not just its shell exit code.
Require three JSON rows, child exit 0, no watchdog kill, and a peak well below the
operator baseline before calling the fix memory-verified. Also test a deliberately
short `--timeout` under the watchdog, and check temp-file cleanup and idle model
release with a short `idleUnloadDelay` in a dedicated loader harness.

## Remaining risks and publication state

- Token limits can truncate table/LaTeX answers. Callers can explicitly request a
  larger positive bound; response-quality acceptance remains separate from memory
  safety. Temperature and repetition penalties change generated text.
- Prompt/image prefill, model weights, and in-flight kernels are not constrained by
  the reusable-buffer cache budget. Large inputs or caller-selected token limits
  can still need substantial memory.
- Timeout and unload cancellation must wait for cooperative loading/preprocessing
  and GPU work; they are not hard wall-clock guarantees. Active sessions may retain
  the model briefly after `unload()`. Keep the external watchdog for verification.
- The cache limit is process-global and would affect any future MLX consumers.
- Busy requests are rejected rather than queued. UI behavior and concurrent-request
  UX have not been exercised.
- No screen capture, ScreenCaptureKit, or CGWindowList image APIs were invoked.
  Only the supplied synthetic image file was used. No app launch or TCC permission
  request was performed.
- Local staging was attempted but denied:
  `Unable to create .../.git/worktrees/perf-mlxfix/index.lock: Operation not permitted`.
  This worktree's Git metadata lives under the read-only primary checkout. No
  commit could be created within the granted permissions; all changes remain in
  this worktree. No other checkout was edited, no permission escalation was
  attempted, and nothing was pushed or submitted as a PR.

After review and GPU verification, the operator can stage these eight files and
commit on the existing branch:

```sh
git add OctoshotEmbeddedMLX/MLXVLMLoader.swift \
  Octoshot/Services/AI/LocalVLMService.swift \
  octoshot-cli/OctoshotCLI.swift octoshot-cli/VLMBench.swift \
  OctoshotCoreTests/MLXVLMLoaderTests.swift project.yml project.ci.yml PERF_MLX_FIX.md
git commit -m "Bound embedded MLX vision generation and model lifetime"
```
