# Embedded AI (Neil path)

## Models

| Role | Hugging Face | On-disk folder |
|------|----------------|----------------|
| Light VLM | `mlx-community/SmolVLM2-500M-Video-Instruct-mlx-4bit` | `~/Library/Application Support/Octoshot/Models/smolVLM2_500M_4bit/` |
| LaTeX specialist | `cstr/pix2tex-mfr-gguf` (`pix2tex-mfr-q4_k.gguf`) | `~/Library/Application Support/Octoshot/Models/pix2texMFR_Q4/` |
| Optional diary roast only | `mlx-community/MiniCPM-V-4.6-4bit` (~2.2GB, Apache-2.0) | `~/Library/Application Support/Octoshot/Models/miniCPMV46_4bit/` |

Weights are **never** bundled in the app; use **Settings → AI** or onboarding to download.

MiniCPM is managed separately in **Settings → 一酱日记**. It is opt-in, not bundled,
and never replaces SmolVLM2 for Ask AI. Diary roasts never fall back to SmolVLM2.
The downloader resumes verified whole files, checks HF LFS SHA256 when provided,
checks free space with a 512MiB reserve, and marks installation complete only after
all runtime files are verified. An interrupted file is restarted, not byte-range resumed.

**M1c runtime blocker:** the resolved `mlx-swift-lm` 2.31.3 VLM registry does not
implement `minicpmv4_6`. A config-only offline test reproduces
`Unsupported model type: minicpmv4_6` without downloading weights. The native
adapter and fail-closed UI are wired, but real MiniCPM inference is **not working
or accepted yet**. Settings shows this limitation before a user downloads anything.
The diary adapter requests 64 tokens, fresh sessions, a 256MiB GPU buffer cache,
30s cooperative cancellation, serial calls and five-minute idle unload. The cache
limit is not a total-memory limit; ≤3GB peak and ≤3s hot latency remain unmeasured.
See [M1c QA](yijiang-diary-m1c-qa.md) before reviewing or merging.

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
