# Settings localization QA

Settings use the English phrases as keys in `OctoshotL10n` and
`Octoshot/zh-Hans.lproj/Localizable.strings`. Keep interpolated values in format
arguments rather than constructing keys dynamically. `SettingsLocalizationTests`
in `OctoshotCoreTests` checks the shared catalog, app call sites, nonempty Chinese
translations, format arguments, and direct Settings control literals.

## Offscreen snapshots (Debug only)

```sh
bash Scripts/ci-xcodegen.sh
xcodebuild -project Octoshot.xcodeproj -scheme Octoshot \
  -configuration Debug -derivedDataPath ./build-l CODE_SIGNING_ALLOWED=NO build
for locale in zh-Hans en; do
  destination=/tmp/octoshot-settings-en
  [ "$locale" = zh-Hans ] && destination=/tmp/octoshot-settings-zh
  OCTOSHOT_QA_SNAPSHOT_DIR="$destination" \
  OCTOSHOT_QA_SNAPSHOT_SETTINGS=1 \
  OCTOSHOT_QA_SNAPSHOT_LOCALE="$locale" \
    build-l/Build/Products/Debug/Octoshot.app/Contents/MacOS/Octoshot
done
```

The harness runs before `OctoshotApp.main()` and exits after writing eight
`settings-<tab>.png` images. It renders 1120 × 1600 point Settings views in an
unshown hosting window, without screen capture. The locale override applies to
both SwiftUI and the localization bundle. Existing Quick Access snapshots are
unchanged when `OCTOSHOT_QA_SNAPSHOT_SETTINGS` is absent.

Settings snapshots use an in-memory defaults store, enable the JPEG and optional
Ollama controls for coverage, and skip permission refresh, launch-at-login
integration, Ollama requests, and preference persistence. The permission row is
a fixture, not an observation of the user's permission state. No download,
installation, or shortcut mutation actions are invoked. AppKit still needs
access to the macOS graphical session, even though no window is displayed;
restricted runners may abort during `_RegisterApplication` before producing PNGs.

Inspect every Chinese and English PNG for clipping and untranslated labels.
Technical identifiers, commands, JSON, file paths, model names, license names,
units, and keyboard glyphs are intentionally preserved. Custom prompts and
external service diagnostics remain user/provider data. The built-in LaTeX
prompt is translated for display without changing the underlying model prompt.

After validation, restore `Config/EmbeddedAI.xcconfig` to its pre-run contents
and remove `build-l`. Do not launch the app without the harness environment as
part of this workflow.
