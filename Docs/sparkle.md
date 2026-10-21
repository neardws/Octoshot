# Sparkle in-app updates

Octoshot uses [Sparkle 2](https://sparkle-project.org/) for signed, notarized update delivery.

## Feed URL

Released builds read:

`https://www.neardws.com/Octoshot/appcast.xml`

The appcast is published from `website/public/appcast.xml` when the site deploys from `main` (GitHub Pages, custom domain `www.neardws.com`).

## Checking for updates

- Menu bar **Octoshot → Check for Updates…** (简体：**检查更新…**)
- **Settings → About → Check for Updates…**

Automatic checks run once per day (`SUScheduledCheckInterval` = 86400). Downloads are **not** installed without user confirmation (`SUAutomaticallyUpdate` = false).

Debug builds and non-`.app` runs do not start Sparkle (no error dialogs when `SUFeedURL` is absent from the running bundle).

## Signing keys (maintainers)

Sparkle uses an Ed25519 key pair:

1. On a Mac, run:

   ```bash
   bash Scripts/generate-sparkle-keys.sh
   ```

   This uses Sparkle’s `generate_keys`, stores the private key in your login Keychain, and exports:

   `~/octoshot-private/sparkle/eddsa_priv.key`

2. Copy the printed **public** key into `Octoshot/Info.plist` as `SUPublicEDKey` (only the public key belongs in git).

3. **Never commit** `eddsa_priv.key` or any Keychain export. The repo `.gitignore` lists common private-key paths.

If you regenerate keys, every future appcast must be signed with the matching private key. Without the private key that corresponds to `SUPublicEDKey`, you must generate a new pair and ship a release that updates the public key in the app.

Optional GitHub Actions secret: store the **file contents** of `eddsa_priv.key` as `SPARKLE_EDDSA_KEY` and write it to a temp path before calling `Scripts/generate-appcast.sh`.

## Publishing an appcast (no GitHub Release from this script)

`Scripts/package.sh` re-signs Sparkle’s nested XPC services, `Autoupdate`, and `Updater.app` with your Developer ID before signing `Sparkle.framework` and the app.

After `Scripts/package.sh` produces a **notarized** DMG:

```bash
export VERSION=0.2.1
export DMG_PATH=dist/Octoshot-v0.2.1-macOS.dmg
# SPARKLE_KEY defaults to ~/octoshot-private/sparkle/eddsa_priv.key
bash Scripts/generate-appcast.sh
```

Commit `website/public/appcast.xml`, merge to `main`, and ensure the release DMG is uploaded to GitHub Releases at the URL used in the appcast enclosure (for example `https://github.com/neardws/Octoshot/releases/download/v0.2.1/Octoshot-v0.2.1-macOS.dmg`).

## Apple Silicon-only releases

Release builds now set `ARCHS=arm64` for the app, CLI, and embedded MLX framework. The app hard-links MLX, so retaining an Intel app slice without redesigning that boundary is not supported. Intel Macs cannot launch these releases; keep their last compatible universal release available. `LSArchitecturePriority` and `LSMinimumSystemVersion` are unchanged.

Sparkle 2.10's `generate_appcast` detects an arm64-only executable and emits `<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>`. Its Intel update filter honors that requirement (including distinguishing Rosetta on Apple Silicon). `Scripts/generate-appcast.sh` now checks this requirement before copying the generated feed into the website; do not hand-publish an unguarded enclosure. Older Sparkle clients may not honor this field: verify the updater version in every supported Intel release before publishing, or keep those clients on a separate legacy feed. An Info.plist change in the new app cannot protect already-installed clients.

## Placeholder appcast

Until the first signed release, the feed is an empty RSS channel (no `<item>` entries). Sparkle treats that as “no updates available” and does not break clients.
