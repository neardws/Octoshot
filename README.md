# Octoshot · 一酱

**八只手，一次截完**

[Octoshot](https://github.com/neardws/Octoshot) 是一款开源（MIT）的 macOS 原生截图工具：基于 Swift、SwiftUI + AppKit 与 ScreenCaptureKit，强调**本机处理**与**隐私优先**，面向科研写作者与开发者。菜单栏常驻、无 Dock 图标；简体中文系统下显示名为 **一酱**。应用图标为原创卡通章鱼 mascot（半眯眼、略带嫌弃的表情，举着取景框——与任何既有版权角色无关）。

## 现已可用

- **区域 / 窗口 / 全屏**截图与全局快捷键；区域选择时 **模式条**（S 截图 / R 滚动拼接 / V 视频 / G GIF / L LaTeX / T 图或表）
- **滚动截图**：滚轮采集多帧并纵向拼接；可选自动滚动（需辅助功能权限）
- **屏幕录制**：ScreenCaptureKit 区域或全屏 H.264 MP4；**GIF** 定时帧导出；录制中浮动 **停止** 面板与菜单栏指示
- **快速访问**浮层缩略图：复制、保存、标注、关闭、拖出；**推测式 top-1 智能操作**（本机分类，需点 Apply）
- **标注**窗口：箭头、矩形、文字、马赛克、撤销、复制/保存
- **设置**（侧边栏）：通用、快捷键、捕获、**录制**、标注、AI、开发者（含 Agent/CLI）、关于；版本号显示在侧栏底部
- **首次运行引导**：屏幕录制、快捷键接管、Ollama 可选配置
- **菜单栏**：捕获项旁显示快捷键、最近截图、打开保存文件夹、Clips 库
- **本机 AI（嵌入式）**：SmolVLM2-500M MLX 4-bit（~292MB）与 pix2tex-mfr Q4（~18MB）按需下载至 `~/Library/Application Support/Octoshot/Models/`；设置 → AI 显示进度与磁盘占用；Ollama 为可选回退（默认关闭且安装嵌入式模型后保持关闭）
- **系统截图快捷键**：读取 `symbolichotkeys.plist`，支持用 ⌘⇧3/4/5 接管并引导关闭系统快捷键

## 路线图

以下能力在开发中或规划中，详见对应 Issue：

| Issue | 功能 |
|-------|------|
| [#2](https://github.com/neardws/Octoshot/issues/2) | 区域选择十字线与放大镜 |
| [#3](https://github.com/neardws/Octoshot/issues/3) | 窗口检测与高亮 |
| [#4](https://github.com/neardws/Octoshot/issues/4) | 快速访问缩略图体验增强 |
| [#5](https://github.com/neardws/Octoshot/issues/5) | 自动脱敏（本机 Vision） |
| [#6](https://github.com/neardws/Octoshot/issues/6) | 询问本机 AI（Ollama 等 OpenAI 兼容接口） |
| [#7](https://github.com/neardws/Octoshot/issues/7) | 截图 → LaTeX |
| [#8](https://github.com/neardws/Octoshot/issues/8) | 论文图/表助手与 Clips 库 |
| [#9](https://github.com/neardws/Octoshot/issues/9) | 开发者模式（取色、标尺、Markdown 粘贴） |
| [#13](https://github.com/neardws/Octoshot/issues/13) | Agent 接口：`octoshot` CLI、stdio MCP、URL scheme、快捷指令 |

### Agent 接口（#13）

构建后可在 DerivedData 或安装路径使用 **`octoshot`** CLI，以及 **`octoshot mcp`**（stdio MCP 服务）。核心能力在 **`OctoshotCore`** 框架中，与 GUI 应用共享。默认仅访问本机；需已授予屏幕录制权限。

**Cursor / Claude Code MCP 配置示例**（路径请改为你本机构建产物）：

在 Octoshot **设置 → Developer** 中点击 **Install Command Line Tool**，将 `octoshot` 安装到 `/usr/local/bin/octoshot`（符号链接到 `Octoshot.app/Contents/Helpers/octoshot`，避免与 `MacOS/Octoshot` 主程序在大小写不敏感磁盘上冲突）。

```json
{
  "mcpServers": {
    "octoshot": {
      "command": "/usr/local/bin/octoshot",
      "args": ["mcp"]
    }
  }
}
```

Claude Desktop（`claude_desktop_config.json`）同样使用 `command` + `args: ["mcp"]`。工具包括：`capture_screen`、`capture_window`、`list_windows`、`list_displays`、`ocr`、`auto_redact`、`ask_ai`、`to_latex`、`extract_table`、`annotate`、`record_start`、`record_stop`。

URL 示例：`octoshot://capture?mode=fullscreen`（区域/窗口模式会打开应用内交互流程）；`octoshot://record?action=start&mode=fullscreen&format=video`；`octoshot record stop`（通过 URL 唤起应用）。任何应用或网页都能打开这些链接，因此直接截全屏或开始录屏的请求默认会先弹窗确认（设置 → 开发者 → URL 协议，可改为始终允许或关闭）；截图固定保存到存储文件夹，链接无法指定路径。

## 环境要求

- macOS **14.0** 或更高
- Xcode **15+**（Swift 5.9）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（生成 Xcode 工程）

## 构建与运行

```bash
brew install xcodegen
git clone https://github.com/neardws/Octoshot.git
cd Octoshot
xcodegen generate
open Octoshot.xcodeproj
```

在 Xcode 中选择 **Octoshot** scheme，按 **⌘R** 运行。

本地签名：默认团队 ID 在 `Config/Signing.xcconfig`（可复制 `Config/Signing.xcconfig.sample` 自定义）。避免空 `DEVELOPMENT_TEAM` 导致 ad-hoc 签名与屏幕录制权限失效。

命令行构建：

```bash
xcodegen generate
DERIVED="$PWD/.derivedData"
xcodebuild -derivedDataPath "$DERIVED" -scheme octoshot-cli -configuration Debug build
xcodebuild -derivedDataPath "$DERIVED" -scheme Octoshot -configuration Debug build
```

首次使用请在 **系统设置 → 隐私与安全性 → 屏幕录制** 中允许 Octoshot（简体系统列表中可能显示为 **一酱**）。

## 签名与屏幕录制权限

macOS 将**屏幕录制**权限绑定到应用的 **Bundle ID 与代码签名**。请使用稳定的 **Apple Development** 签名进行本地调试；避免长期依赖 ad-hoc 签名（`CODE_SIGN_IDENTITY=-`），否则权限状态容易与系统设置不一致。

- **Bundle ID**：`com.neardws.Octoshot`
- 从旧版 MacShot 更名后，即使曾在旧 Bundle ID 下授权，也需在系统设置中**重新允许** Octoshot。

重置屏幕录制权限（更换签名、迁移 Bundle ID 或权限卡住时）：

```bash
tccutil reset ScreenCapture com.neardws.Octoshot
```

然后重新打开应用并在 **隐私与安全性 → 屏幕录制** 中启用。应用内会通过 **ScreenCaptureKit**（`SCShareableContent`）校验权限，因 CoreGraphics 预检 API 可能滞后于真实 TCC 状态。

## 应用内更新（Sparkle）

正式发布的 Octoshot 通过 Sparkle 2 检查 [站点上的 appcast](https://www.neardws.com/Octoshot/appcast.xml)。菜单栏或 **设置 → 关于** 中可选择 **检查更新…**。维护者签名与发布流程见 [Docs/sparkle.md](Docs/sparkle.md)。

## 参与贡献

欢迎 Issue 与 Pull Request：[neardws/Octoshot](https://github.com/neardws/Octoshot)。请先 `xcodegen generate` 再构建；修改应用图标可运行 `python3 Scripts/generate_icons.py`。

## 截图自动化安全

通过 CLI、MCP 或 `octoshot://` 发起的 `record start` 默认会在一酱（Octoshot）中请求确认。
记住的 URL 授权绑定到调用进程的代码签名指定要求（designated requirement），而非仅绑定 Bundle ID 或路径。
浏览器及已注册的 HTTP/HTTPS 处理程序不能被永久允许；旧版仅存字符串的允许记录会被忽略。
旧版全局“始终允许”策略现在仍会请求确认，除非调用方的签名已验证且已记住授权。区域录屏也会先确认，再打开区域选择。
截图按设置使用 PNG/JPEG 编码。自动生成的文件名和未指定扩展名的 CLI 路径使用 `.png`/`.jpg`；显式指定的扩展名会保留，即使它与配置的编码不一致。
自动命名的文件采用独占创建，并在重名时追加编号，避免覆盖其他截图。
无效的显示器 ID 会返回错误并列出可用 ID，不会静默改为截取其他显示器。

## 许可证

[MIT License](LICENSE) · Copyright © 2026 [neardws](https://github.com/neardws)

---

# Octoshot · 一酱

**Eight arms, one shot.**

[Octoshot](https://github.com/neardws/Octoshot) is an open-source (**MIT**) native macOS screenshot app built with Swift, SwiftUI + AppKit, and ScreenCaptureKit. It is **on-device** and **privacy-first**, aimed at **researchers and developers**. The app lives in the menu bar (no Dock icon). On Simplified Chinese systems the display name is **一酱**. The mascot is an **original** cartoon octopus with a deadpan, half-lidded, slightly grumpy look, holding a crop viewfinder—not based on any copyrighted character.

## Available now

- **Area, window, and fullscreen** capture with global hotkeys; **mode bar** on area select (S screenshot / R scroll stitch / V video / G GIF / L LaTeX / T figure or table)
- **Scrolling capture**: scroll-wheel frames stitched vertically; optional auto-scroll (Accessibility)
- **Screen recording**: ScreenCaptureKit region or fullscreen H.264 MP4; **GIF** frame export; floating **Stop** control and menu bar indicator while recording
- **Quick access** floating thumbnail: copy, save, annotate, close, drag-out; **speculative top-1 smart actions** (on-device classify; Apply to copy)
- **Annotate** window: arrow, rectangle, text, pixelate, undo, copy/save
- **Settings** sidebar: General, Shortcuts, Capture, **Recording**, Annotation, AI, Developer (Agent/CLI), About — version in the sidebar footer
- **First-run onboarding**: Screen Recording, shortcut takeover, optional Ollama setup
- **Menu bar**: shortcuts beside capture actions, recent files, open save folder, Clips library browser
- **Embedded local AI**: SmolVLM2-500M MLX 4-bit (~292MB) + pix2tex-mfr Q4 (~18MB) on-demand downloads to Application Support; Settings → AI progress & disk usage; optional Ollama fallback (off by default when embedded models are installed)
- **macOS screenshot hotkeys**: reads `symbolichotkeys.plist`, optional ⌘⇧3/4/5 takeover with Keyboard settings guidance

## Roadmap

Planned or in-progress work is tracked in GitHub issues:

| Issue | Feature |
|-------|---------|
| [#2](https://github.com/neardws/Octoshot/issues/2) | Area crosshair & loupe |
| [#3](https://github.com/neardws/Octoshot/issues/3) | Window detection & highlight |
| [#4](https://github.com/neardws/Octoshot/issues/4) | Quick-access thumbnail polish |
| [#5](https://github.com/neardws/Octoshot/issues/5) | Auto-redact (on-device Vision) |
| [#6](https://github.com/neardws/Octoshot/issues/6) | Ask local AI (Ollama / OpenAI-compatible) |
| [#7](https://github.com/neardws/Octoshot/issues/7) | Screenshot → LaTeX |
| [#8](https://github.com/neardws/Octoshot/issues/8) | Paper figure/table assistant & Clips library |
| [#9](https://github.com/neardws/Octoshot/issues/9) | Developer mode (color picker, ruler, Markdown for issues) |
| [#13](https://github.com/neardws/Octoshot/issues/13) | Agent interface: `octoshot` CLI, stdio MCP, URL scheme, Shortcuts |

### Agent interface (#13)

Build the **`octoshot`** CLI and run **`octoshot mcp`** for a stdio MCP server. Shared logic lives in the **`OctoshotCore`** framework (used by the app, CLI, and MCP). Local-only by default; requires Screen Recording permission.

Use **Settings → Developer → Install Command Line Tool** to install `octoshot` at `/usr/local/bin/octoshot` (symlink to `Octoshot.app/Contents/Helpers/octoshot`).

**Cursor / Claude Code** (`mcp.json`):

```json
{
  "mcpServers": {
    "octoshot": {
      "command": "/usr/local/bin/octoshot",
      "args": ["mcp"]
    }
  }
}
```

MCP tools: `capture_screen`, `capture_window`, `list_windows`, `list_displays`, `ocr`, `auto_redact`, `ask_ai`, `to_latex`, `extract_table`, `annotate`, `record_start`, `record_stop`. URL examples: `octoshot://capture?mode=window`; `octoshot://record?action=start&format=gif`; CLI `octoshot record stop` (opens the app via URL). Because any app or web page can open these links, requests that capture the full screen or start a recording on their own ask for confirmation by default (Settings → Developer → URL scheme: always allow or off); screenshots always go to the save folder, and links cannot choose the path.

### Embedded AI (SmolVLM2 + pix2tex)

- **Vision**: `mlx-community/SmolVLM2-500M-Video-Instruct-mlx-4bit` via pinned [mlx-swift-lm 2.29.3](https://github.com/ml-explore/mlx-swift-lm) (`MLXVLM` + `MLXLMCommon` in `project.yml`).
- **LaTeX**: `cstr/pix2tex-mfr-gguf` via bundled or auto-downloaded `llama-mtmd-cli` (`Scripts/fetch-llama-mtmd.sh`, Application Support fallback).
- **CI** does not download ML weights; builds MLX on macOS Apple Silicon when `EMBEDDED_MLX=1` (see `Config/EmbeddedAI.xcconfig`).

## Requirements

- macOS **14.0** or later
- Xcode **15+** (Swift 5.9)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build & run

```bash
brew install xcodegen
git clone https://github.com/neardws/Octoshot.git
cd Octoshot
xcodegen generate
open Octoshot.xcodeproj
```

Select the **Octoshot** scheme in Xcode and press **⌘R** (builds the `octoshot-cli` target first, producing the `octoshot` binary and embedding it at `Octoshot.app/Contents/Helpers/octoshot` — not `MacOS/`, which collides with the `Octoshot` executable on case-insensitive volumes).

Signing: default team in `Config/Signing.xcconfig` (see `.sample` for overrides). Do not leave `DEVELOPMENT_TEAM` empty or TCC may treat each build as a new app.

```bash
xcodegen generate
DERIVED="$PWD/.derivedData"
xcodebuild -derivedDataPath "$DERIVED" -scheme octoshot-cli -configuration Debug build
xcodebuild -derivedDataPath "$DERIVED" -scheme Octoshot -configuration Debug build
```

Grant **Screen Recording** under **System Settings → Privacy & Security** on first run (may appear as **一酱** in Chinese locales).

## Signing & Screen Recording (TCC)

macOS ties Screen Recording to your app’s **bundle ID and code signature**. Use a stable **Apple Development** identity for local builds; ad-hoc signing often breaks or confuses TCC.

- **Bundle ID**: `com.neardws.Octoshot`
- After renaming from legacy MacShot, you must **re-grant** Screen Recording even if an older build was allowed.

```bash
tccutil reset ScreenCapture com.neardws.Octoshot
```

Relaunch the app and enable it again under **Privacy & Security → Screen Recording**. The UI verifies access via **ScreenCaptureKit** because `CGPreflightScreenCaptureAccess()` can lag TCC.

## In-app updates (Sparkle)

Shipped Octoshot builds use Sparkle 2 to read the [site appcast](https://www.neardws.com/Octoshot/appcast.xml). Use **Check for Updates…** from the menu bar or **Settings → About**. Maintainer signing and appcast generation are documented in [Docs/sparkle.md](Docs/sparkle.md).

## Contributing

Issues and pull requests are welcome at [neardws/Octoshot](https://github.com/neardws/Octoshot). Run `xcodegen generate` before building; regenerate icons with `python3 Scripts/generate_icons.py` when needed.

## Capture automation safety

`record start` through CLI, MCP, or `octoshot://` asks for consent by default.
Remembered URL consent is bound to the sending process's code-signing designated
requirement, not just its bundle ID or path. Browsers and registered HTTP/HTTPS
handlers cannot be permanently allowed; old string-only allow entries are ignored.
The legacy global “Always allow” policy now asks unless the caller has a verified,
remembered signature. Region recording requests also ask before opening selection.
Capture output uses the configured PNG/JPEG encoding. Auto-generated names and
extensionless CLI paths use `.png`/`.jpg`; an explicitly supplied extension is
preserved even if it differs from the configured encoding. Auto-named files use
exclusive creation and numbered suffixes to avoid overwriting other captures.
Invalid display IDs return an error listing available IDs rather than silently
capturing another display.

## License

[MIT License](LICENSE) · Copyright © 2026 [neardws](https://github.com/neardws)
