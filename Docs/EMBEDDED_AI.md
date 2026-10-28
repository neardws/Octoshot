# Embedded AI (Neil path)

## Models

| Role | Hugging Face | On-disk folder |
|------|----------------|----------------|
| Light VLM | `mlx-community/SmolVLM2-500M-Video-Instruct-mlx-4bit` | `~/Library/Application Support/Octoshot/Models/smolVLM2_500M_4bit/` |
| LaTeX specialist | `cstr/pix2tex-mfr-gguf` (`pix2tex-mfr-q4_k.gguf`) | `~/Library/Application Support/Octoshot/Models/pix2texMFR_Q4/` |
| Optional diary roast only (external local Ollama) | `openbmb/minicpm-v4.7:1b` (~1.8GB Q4_K_M) | Managed by the user's Ollama, not Octoshot |

Weights are **never** bundled in the app; use **Settings → AI** or onboarding to download.

MiniCPM diary roasts now use **optional local Ollama ≥ 0.40.5**, not Swift MLX.
In **Settings → 一酱日记**, the user installs/runs Ollama themselves and executes
`ollama pull openbmb/minicpm-v4.7:1b`. Do not use `latest` (22GB, 35B-A3B).
Octoshot never installs/starts Ollama, pulls its models, bundles GGUF, or sets up
LaunchAgents. The model name and loopback address are configurable in UserDefaults;
defaults are `openbmb/minicpm-v4.7:1b` and `http://127.0.0.1:11434`.
Non-loopback addresses and HTTP redirects are rejected so diary inputs stay local.
Settings checks version/model availability, offers the download-page link and copy
command, and tests one synthetic skeleton without accessing the screen.

Roasts remain opt-in (off for new users; existing opt-in is preserved). Chat requests
use `stream:false`, `think:false`, 64 predicted tokens, temperature 0.7, `keep_alive:"2m"`,
and a 30-second deadline. Inference is serialized across clients. Only bounded AX/OCR
skeletons supply facts; optional existing keyframes are resized to 448px and sent as
base64 JPEG. Thinking blocks are stripped before the existing strict Chinese/length/
grounding gate; repeated output within a report is rejected. Failures return rule-based
placeholders without changing report facts. Three consecutive failures disable model
roasts for the local calendar day, persisting across restarts; tomorrow resets the breaker.
Ollama manages model memory; `keep_alive` is a request, not an enforced memory bound.

The old MLX MiniCPM download UI and diary MLX adapter are removed. Historical catalog,
download helpers and architecture-probe tests remain for compatibility, **not as a
supported inference route** (`minicpmv4_6` is still unsupported). SmolVLM2/Ask AI is
unchanged, and is never used as a diary fallback. All current QA uses mocked HTTP;
real inference, quality, peak memory and hot latency remain unmeasured.
See [M1c QA](yijiang-diary-m1c-qa.md); PR #119 remains draft, not approved for merge.

New pix2tex downloads use the canonical lowercase filename `pix2tex-mfr-q4_k.gguf`. The legacy `pix2tex-mfr-Q4_K.gguf` filename is still accepted locally without re-downloading; if both exist, the canonical lowercase file is preferred.

## MLX (SmolVLM2)

`project.yml` pins **[mlx-swift-lm 2.29.3](https://github.com/ml-explore/mlx-swift-lm)** and links **MLXVLM** + **MLXLMCommon** into the **Octoshot** app target.

`Config/EmbeddedAI.xcconfig` sets `EMBEDDED_MLX=1` (adds Swift condition `EMBEDDED_MLX`). Set `EMBEDDED_MLX=0` and remove `EMBEDDED_MLX` from `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in `xcodebuild` if you need a stub MLX build (CI fallback).

Inference loads weights from Application Support via `VLMModelFactory.shared.loadContainer(configuration: ModelConfiguration(directory: …))`.

## pix2tex (llama.cpp mtmd)

- **Bundled**: `Scripts/fetch-llama-mtmd.sh` (pinned `b11514`) runs in CI and dev builds; `llama-mtmd-cli` is copied to `Octoshot.app/Contents/Helpers/`.
- **First use**: if the helper is missing, `LaTeXEngineInstaller` downloads the same release into `~/Library/Application Support/Octoshot/bin/` (no Homebrew).

## Licenses

- Octoshot app: **MIT**
- SmolVLM2 weights: **Apache-2.0**
- pix2tex-mfr GGUF: **MIT**
- mlx-swift-lm: **Apache-2.0**
- llama.cpp binaries: **MIT**

See **Settings → About** for a short attribution blurb.
