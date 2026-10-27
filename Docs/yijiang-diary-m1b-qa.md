# 一酱日记 M1b QA (#116)

M1b reads existing encrypted M1a skeletons. It never starts a recorder, requests
Accessibility/Screen Recording permission, downloads a model, or captures pixels
from the desktop. Placeholder roasts use app names and durations only.

Windows belong to the calendar day containing their start. Cross-midnight windows
are counted once, in full, rather than inventing per-app sub-window durations.
The report retains the builder's calendar/time zone for consistent display/export.
Markdown escapes source text and is **unencrypted**; exports require a save panel.
Store errors are shown explicitly, not misrepresented as an empty day.

Notifications are a repeating local hour/minute trigger, replaced when enabling,
disabling, changing settings, or launching. Permission is requested only on an
explicit off-to-on toggle. The `diaryDate: deliveryDate` userInfo key means the
actual `UNNotification.date`, not the date on which the repeating request was
created: clicking yesterday's delivered notification opens yesterday's report.
No diary facts are included in notification content. Reports are built on demand.
Retention selection persists M1a settings; this milestone does not start its janitor
or live recorder. Opening the menu works with diary disabled or notifications denied.

## Build and offscreen previews

```bash
cd /Users/neardws/octoshot-wt/diary-m1b
xcodegen generate
DERIVED="$PWD/.derivedData"
xcodebuild -derivedDataPath "$DERIVED" -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation -scheme Octoshot -configuration Debug build
mkdir -p /Users/neardws/octoshot-wt/diary-m1b-preview
OCTOSHOT_QA_SNAPSHOT_DIR=/Users/neardws/octoshot-wt/diary-m1b-preview \
OCTOSHOT_QA_SNAPSHOT_DIARY=1 OCTOSHOT_QA_SNAPSHOT_LOCALE=zh-Hans \
  "$DERIVED/Build/Products/Debug/Octoshot.app/Contents/MacOS/Octoshot"
```

If sandbox permissions restrict the sibling directory, use `$PWD/.diary-preview`
as the snapshot destination and copy it to the review directory outside the sandbox.
Do not launch without QA environment variables. The diary harness runs before the
app delegate and Quick Access harness, sets prohibited activation and aqua appearance,
uses only `NSHostingView` bitmap caching, then exits. All six windows are synthetic;
the settings pane uses in-memory defaults, with no store, Keychain or notification access.

Outputs: `diary-report-full.png` (900 × 1400 points), `diary-report-empty.png`
(900 × 900), `settings-diary.png` (780 × 700). Display scale may increase pixel size.
Existing Quick Access and settings flags retain their behavior. Neil should review
the full timeline, footer, icon, empty state and settings shot before merge.

Core tests use fixed clocks/calendars and fake keys/notifications. Interactive
permission, notification delivery/click, copy and save-panel behavior are not proved
by offscreen rendering and require a separately authorized interactive check.

## Verification receipt — 2026-10-27 restricted session

- `xcodegen generate`, `Scripts/ci-xcodegen.sh`, and `git diff --check` passed.
  The CI script's configuration change was restored; the final generated project
  uses `project.yml`. The project is ignored/untracked and is not part of the patch.
- All three required standard build/test commands stopped at dependency resolution:
  GitHub DNS/network access is unavailable for MLX/Sparkle.
- A disposable project under ignored `build/verify` compiled Core, CLI, the full
  XCTest bundle and app source. It used the existing MLX stub configuration and a
  temporary no-op updater instead of Sparkle. This is **not** a production build pass.
- Direct XCTest execution: 13 focused tests passed, 0 failed (11 new report/scheduler
  tests plus 2 localization tests). Full bundle: 204 executed, 197 passed, 5 failed
  cases with 8 failure assertions, 2 skipped. Failures are in unchanged pasteboard,
  Vision redaction and M1a backup-exclusion tests. The Xcode test runner separately
  failed to connect to `com.apple.testmanagerd.control` due to sandbox restrictions.
- The diary QA entrypoint was invoked with QA variables on the offline app, including
  after successful ad-hoc signature verification. It aborted with exit 134 before
  producing PNGs. No visual review is claimed. The requested sibling preview path
  is outside this session's writable roots; no PNG paths/sizes are available yet.
- Git staging/commit was blocked by `Operation not permitted` creating the worktree
  `index.lock` in the repository's external Git metadata directory. No commit or push
  was made. Build/log artifacts remain ignored under `build/verify`.

Before acceptance, rerun the standard dependency-backed builds, full suite and QA
recipe in a session with the necessary network, GUI and Git/directory access; inspect
the three PNGs and make the requested local commit. Interactive checks remain separate.
