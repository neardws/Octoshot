# 一酱日记 M1b QA (#116)

M1b reads existing encrypted M1a skeletons. It never starts a recorder, requests
Accessibility/Screen Recording permission, downloads a model, or captures pixels
from the desktop.

Neil 的评审要求：「要分析得更深入，如果只是时间长度意义不大」。
日报改为「今天在干嘛 → 各 App 都干了啥 → 时间线 → 一酱总结」，用时退为次要信息。
概览、每 App 文字归纳和规则吐槽仅绑定已有标题、文字片段、域名及 App 名，
不推断任务完成或真实操作，不调用模型。文字按指纹去重并分为窗口、片段、域名；
各类保留主要线索，完整条目仍在时间线。文字不足时明确说明，绝不补剧情。

焦点分析按时间窗起点排序、窗内保留条目顺序计算 App 变化和无序切换对，
同 App 相邻条目累计；跨窗口空档或空条目窗不延续最长连段。并列 App 用时及
切换对按 bundle ID 稳定排序。M1a 合并同窗条目并过滤短停留，因而这些数字只是
骨架估计，不是完整前台切换频率或实际连续专注证明；UI 和 Markdown 都明示此限制。

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
uses only `NSHostingView` bitmap caching, then exits. All eight windows are synthetic;
Cursor / Safari 有意交替，另含 Terminal、Notes、不同标题、片段及示例域名；
the settings pane uses in-memory defaults, with no store, Keychain or notification access.

Outputs: `diary-report-full.png` (900 × 2400 points), `diary-report-empty.png`
(900 × 900), `settings-diary.png` (780 × 700). Display scale may increase pixel size.
Existing Quick Access and settings flags retain their behavior. Neil should review
the full timeline, footer, icon, empty state and settings shot before merge.

Core tests use fixed clocks/calendars and fake keys/notifications. Interactive
permission, notification delivery/click, copy and save-panel behavior are not proved
by offscreen rendering and require a separately authorized interactive check.

## 本轮深化分析验证 — 2026-10-27

- 在 `diary-m1b-report` 工作树执行 `xcodegen generate`、标准依赖版
  `OctoshotCoreTests Debug test` 和 `Octoshot Debug build`，全部通过。
  测试共 210 项：208 通过、0 失败、2 跳过；其中日报测试 12 项全部通过。
- 回归覆盖多 App 往返、相邻同 App 累计、记录空档、并列稳定排序、全部 App 保留、
  文字去重、空记录、缺文字降级、Markdown 转义及非条目 keyframe 的负面隔离。
- 仅以三个 QA 环境变量启动离屏 harness；退出码 0。已查看全部三张 PNG，
  完整日报的八个时间窗、总结及页脚均未裁切；头像仍是 AppIcon。
- 预览目录：`/Users/neardws/octoshot-wt/diary-m1b-preview/`。
  `diary-report-full.png`：1800 × 4800，806693 字节；
  `diary-report-empty.png`：1800 × 1800，189102 字节；
  `settings-diary.png`：1560 × 1400，108180 字节。
- 本轮未启动 recorder、请求 TCC 或执行桌面截图；未接入模型下载/推理及 CLI/MCP。
  构建所用已有依赖不代表启用 M1c。未读取 Sparkle 私钥。
- `Octoshot.xcodeproj` 未跟踪且被忽略，生成后不加入提交；日志留在忽略目录
  `build/diary-qa/`。PNG 和 `.derivedData` 不入库。
  离屏验证仍不证明复制、保存面板或通知交互；本轮结果取代下方旧会话的阻塞结论。

## 历史记录：Verification receipt — 2026-10-27 restricted session

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
