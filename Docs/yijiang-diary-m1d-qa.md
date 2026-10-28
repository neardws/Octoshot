# 一酱日记 M1d — CLI / MCP QA

## Runtime boundary

Live commands require **Octoshot already running** and diary enabled in its settings.
Disabled diary returns a clear JSON error for every command, including `status`,
without opening the database.
The CLI never opens the diary database or reads the diary Keychain key. Only the
app creates `DiaryStore` and decrypts records. No command enables diary, requests
AX/Screen Recording consent, starts a capture, or starts a recording.

The URL gate classifies `octoshot://diary` as non-capture and always allows routing,
including when capture automation is off. The app routes it **before** display
selection or capture consent handling. A URL alone cannot request an action: the
CLI creates a random UUID request directory under
`~/Library/Application Support/Octoshot/DiaryIPC`, then opens
`octoshot://diary?request=<UUID>` in the running app. The app consumes the local
`request.json` once and writes `reply.json`. No caller-supplied output path is
accepted. Direct `?action=purge` URLs are rejected. Directories are owner-only
0700; files are 0600; symlink directories/requests/replies are rejected. Requests
expire after 120 seconds. CLI replies time out after 30 seconds and the request
directory is removed on normal success/error/timeout. A forcibly killed CLI can
leave an owner-only plaintext reply directory; it can be removed manually.

Pause/resume persist `DiarySettings.pausedUntil` through the app coordinator;
`isPaused(at:)` becomes false automatically after the deadline. Minutes must be
integers in 1...525600. Existing settings without the new optional field still
decode. The M1a–M1c baseline has no production `DiaryRecorder` sampling loop wired
in the app: this milestone supplies the pause state, not a new background capture
pipeline. A future recorder coordinator must consult enabled/isPaused before
sampling. Purge calls `DiaryStore.deleteAll()` and leaves settings/key unchanged;
it is not a promise of forensic secure erasure or deletion of separate exports.

## CLI

```sh
octoshot diary today [--json]
octoshot diary show 2026-10-29 [--json]
octoshot diary timeline --from 2026-10-29T00:00:00+08:00 --to 2026-10-30T00:00:00+08:00 [--json]
octoshot diary export [--date 2026-10-29] --format md|json
octoshot diary pause 60
octoshot diary resume
octoshot diary status [--json]
octoshot diary purge --confirm
```

Square brackets and `md|json` describe alternatives; they are not literal shell
arguments. `export` defaults to today and writes to stdout (redirect it yourself).
Reports without `--json` and Markdown exports use `DiaryMarkdownExporter`.
Status/mutations print short status text. Timeline prints JSON in both modes.
Invalid arguments and app/service failures print `{"error":"..."}` on stdout and
exit nonzero. `purge` without the exact `--confirm` flag fails before any IPC; the
service independently checks the confirmation. Dates are strictly YYYY-MM-DD in
the app's local timezone. ISO8601 range endpoints require offsets or Z and accept
fractional seconds. Empty days/ranges return empty arrays, not an error.

## Stable JSON contracts

All payloads use system Codable encoders/decoders, including MCP text content.
The internal file-IPC envelope is not the CLI/MCP public payload.

- Report: `{ "date": "YYYY-MM-DD", "summary": "...", "focusPattern": "...", "apps": [{ "bundleID": "...", "name": "...", "duration": 600, "bullets": ["..."] }], "segments": [{ "start": "ISO8601", "end": "ISO8601", "app": "...", "title": "...", "snippets": "...", "urlHost": "..." }], "closingRoast": "..." }`.
- Timeline: `{ "from": "ISO8601", "to": "ISO8601", "windows": [{ "start": "ISO8601", "end": "ISO8601", "app": "...", "title": "...", "snippets": "...", "urlHost": "..." }] }`.
- Status: `{ "enabled": true, "paused": false, "pausedUntil": null, "retentionDays": 30, "dailyReportTime": "22:00" }`.

Report `closingRoast` and window `urlHost` are omitted when unavailable. Status
`pausedUntil` and `retentionDays` are explicitly null when absent. Timestamp
outputs normalize to UTC with seconds precision. Durations are seconds; snippets
are newline-joined text. Multiple app entries in a skeleton produce multiple
rows sharing its start/end. Timeline selects overlapping skeletons in `[from,to)`
without inventing clipped/prorated durations. Reports retain the existing
start-day ownership rule. IPC reports use deterministic text analysis and do not
invoke Ollama or change M1c behavior. No key-frame objects, image data, or
screenshot paths are included in DTOs.

## MCP

Start with `octoshot mcp`:

| Tool | Arguments |
| --- | --- |
| `diary_get_report` | optional string `date`, defaults to today |
| `diary_get_timeline` | required ISO8601 strings `from`, `to` |
| `diary_status` | none |
| `diary_pause` | optional integer `minutes`, defaults to 60 |

These tools use the same app IPC client. Successful `content[0].text` is a JSON
report/timeline/status, not interpolated JSON. Diary tool errors use `isError: true`
with JSON error text. There is deliberately no MCP resume, purge, or image tool.

## Verification (no GUI launch, no TCC)

```sh
xcodegen generate
xcodebuild test -project Octoshot.xcodeproj -scheme OctoshotCoreTests \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
  -only-testing:OctoshotCoreTests/DiaryAgentTests \
  -only-testing:OctoshotCoreTests/URLSchemeGateTests \
  -only-testing:OctoshotCoreTests/YijiangDiaryTests \
  -only-testing:OctoshotCoreTests/YijiangDiaryStoreTests \
  -only-testing:OctoshotCoreTests/YijiangDiaryReportTests \
  -only-testing:OctoshotCoreTests/YijiangDiaryReportSchedulerTests \
  -only-testing:OctoshotCoreTests/MCPFileResultTests \
  -only-testing:OctoshotCoreTests/DiaryOllamaTests \
  -only-testing:OctoshotCoreTests/DiaryMiniCPMTests
xcodebuild build -project Octoshot.xcodeproj -scheme Octoshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
```

Tests use temporary databases/mailboxes, `InMemoryDiaryKeyProvider`, injected
settings/clock, and synthetic skeletons. They cover JSON fields/escaping, report
and timeline boundaries, pause expiry, disabled errors, purge confirmation,
one-shot mailbox delivery, unsafe URLs/symlinks, MCP schemas and service dispatch.
Actual Launch Services delivery to an installed running app is a separate manual
integration check for the orchestrator; this verification does not install or
launch the app and must not be described as that live check.

M1d verification result: **124 tests passed, 0 failed, 0 skipped**; unsigned
Octoshot + embedded CLI build passed. An additional **7 stdio smoke assertions**
passed against the built CLI: missing purge confirmation, invalid date and zero
pause duration all exit nonzero with decodable JSON; `tools/list` advertises exactly
the four diary tools; invalid pause/report and omitted timeline arguments return
MCP `isError` content containing decodable JSON. No live URL delivery was invoked.
