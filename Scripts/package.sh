#!/bin/bash
# Build, sign (Developer ID + hardened runtime), notarize and staple Octoshot.app and a DMG.
# Env:
#   VERSION         version label for artifacts (default: CFBundleShortVersionString of the build)
#   SIGN_IDENTITY   codesign identity (default: first "Developer ID Application" in keychain)
#   NOTARY_PROFILE  notarytool keychain profile (default: Octoshot-notary); set empty to skip notarization
#                   create once with: xcrun notarytool store-credentials <name> --apple-id ... --team-id ...
#                   On this machine: NOTARY_PROFILE=MijiaBar-notary Scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE-Octoshot-notary}"
ENT=Octoshot/Octoshot.entitlements
DERIVED="$PWD/.derivedData-release"
DIST=dist

if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)
fi
[ -n "$SIGN_IDENTITY" ] || { echo "❌ No Developer ID Application identity found"; exit 1; }
echo "🔏 Signing identity: $SIGN_IDENTITY"

# llama-mtmd-cli (optional; embed script warns if missing)
if { [ ! -x build/llama-mtmd/bin/llama-mtmd-cli ] || [ ! -L build/llama-mtmd/bin/libggml.dylib ]; } && [ -x Scripts/fetch-llama-mtmd.sh ]; then
  bash Scripts/fetch-llama-mtmd.sh || true
fi
[ -x build/llama-mtmd/bin/llama-mtmd-cli ] || echo "warning: llama-mtmd-cli missing; LaTeX helper may be incomplete"

command -v xcodegen >/dev/null && xcodegen generate >/dev/null

# Full MLX (project.yml). Skip plugin validation like CI mlx job.
XB=(xcodebuild -project Octoshot.xcodeproj -derivedDataPath "$DERIVED" -configuration Release -skipPackagePluginValidation)
"${XB[@]}" -scheme Octoshot -resolvePackageDependencies
for scheme in octoshot-cli Octoshot; do
  "${XB[@]}" -scheme "$scheme" build
done

SRC_APP="$DERIVED/Build/Products/Release/Octoshot.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC_APP/Contents/Info.plist")}"
rm -rf "$DIST" && mkdir -p "$DIST"
APP="$DIST/Octoshot.app"
ditto "$SRC_APP" "$APP"
ZIP="$DIST/Octoshot-v$VERSION-macOS.zip"
DMG="$DIST/Octoshot-v$VERSION-macOS.dmg"

sign() { codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$@"; }

# Sparkle ships nested helpers signed by the Sparkle project; re-sign inside-out before the
# framework bundle (see https://sparkle-project.org/documentation/sandboxing/).
sign_sparkle_nested() {
  local sparkle="$APP/Contents/Frameworks/Sparkle.framework"
  [ -d "$sparkle" ] || return 0
  local ver="$sparkle/Versions/Current"
  [ -e "$ver" ] || ver="$sparkle/Versions/B"
  local xpc_root="$ver/XPCServices"
  if [ -d "$xpc_root" ]; then
    for name in Installer.xpc Downloader.xpc; do
      [ -d "$xpc_root/$name" ] && sign_sparkle_xpc "$xpc_root/$name"
    done
    local xpc
    for xpc in "$xpc_root"/*.xpc; do
      [ -d "$xpc" ] || continue
      case "$(basename "$xpc")" in Installer.xpc|Downloader.xpc) continue ;; esac
      sign_sparkle_xpc "$xpc"
    done
  fi
  [ -f "$ver/Autoupdate" ] && sign "$ver/Autoupdate"
  [ -d "$ver/Updater.app" ] && sign "$ver/Updater.app"
}
sign_sparkle_xpc() {
  case "$(basename "$1")" in
    Downloader.xpc) sign --preserve-metadata=entitlements "$1" ;;
    *) sign "$1" ;;
  esac
}

# Inside-out (never --deep): dylibs, helpers, Sparkle nested tools, frameworks, app.
while IFS= read -r -d '' item; do sign "$item"; done < <(find "$APP/Contents" -type f -name '*.dylib' -print0)
if [ -d "$APP/Contents/Helpers" ]; then
  while IFS= read -r -d '' item; do
    [ -x "$item" ] || continue
    case "$(basename "$item")" in
      *.dylib) continue ;;
      octoshot) sign --identifier com.neardws.octoshot-cli "$item" ;;
      llama-mtmd-cli) sign --identifier com.neardws.octoshot.llama-mtmd-cli "$item" ;;
      *) sign "$item" ;;
    esac
  done < <(find "$APP/Contents/Helpers" -type f -perm +111 -print0)
fi
RES_OCTOSHOT="$APP/Contents/Resources/octoshot"
if [ -f "$RES_OCTOSHOT" ]; then
  sign --identifier com.neardws.octoshot-cli "$RES_OCTOSHOT"
fi
sign_sparkle_nested
while IFS= read -r -d '' fw; do sign "$fw"; done < <(find "$APP/Contents/Frameworks" -name '*.framework' -maxdepth 1 -print0 2>/dev/null || true)
sign --entitlements "$ENT" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

notarize() {
  local file="$1" log="$DIST/notary-$(basename "$1").log" i
  for i in 1 2 3; do
    if xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$log"; then
      grep -q "status: Accepted" "$log" && return 0
      grep -qi "not found\|keychain" "$log" || break
    fi
    echo "↻ retrying notarytool ($i)…"; sleep 3
  done
  echo "❌ Notarization failed: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"; return 1
}

if [ -n "$NOTARY_PROFILE" ]; then
  echo "📮 Notarizing app…"
  ditto -c -k --keepParent "$APP" "$DIST/notarize-app.zip"
  notarize "$DIST/notarize-app.zip"
  rm -f "$DIST/notarize-app.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"

STAGE="$DIST/dmg" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Octoshot.app" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Octoshot" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

if [ -n "$NOTARY_PROFILE" ]; then
  echo "📮 Notarizing DMG…"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -vv -t exec "$APP"
  spctl -a -vvv -t open --context context:primary-signature "$DMG"
fi
shasum -a 256 "$ZIP" "$DMG"
echo "✅ $ZIP"
echo "✅ $DMG"
