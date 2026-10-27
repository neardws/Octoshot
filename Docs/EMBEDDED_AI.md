# Embedded AI (Neil path)

## Models

| Role | Hugging Face | On-disk folder |
|------|----------------|----------------|
| Light VLM | `mlx-community/SmolVLM2-500M-Video-Instruct-mlx-4bit` | `~/Library/Application Support/Octoshot/Models/smolVLM2_500M_4bit/` |
| LaTeX specialist | `cstr/pix2tex-mfr-gguf` (`pix2tex-mfr-q4_k.gguf`) | `~/Library/Application Support/Octoshot/Models/pix2texMFR_Q4/` |

Weights are **never** bundled in the app; use **Settings → AI** or onboarding to download.

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
