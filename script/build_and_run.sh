#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PeakHalo"
MIN_SYSTEM_VERSION="15.0"
BUILD_CONFIGURATION="${SWIFT_BUILD_CONFIGURATION:-debug}"
DEFAULT_BUNDLE_ID="com.logyxiao.PeakHalo"
if [[ "$BUILD_CONFIGURATION" == "debug" ]]; then
  DEFAULT_BUNDLE_ID="com.logyxiao.PeakHalo.debug"
fi
BUNDLE_ID="${APP_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-dev}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PLIST="$DIST_DIR/$APP_NAME.entitlements"
APP_ICON_SOURCE="$ROOT_DIR/Sources/PeakHalo/Resources/AppIcon.icns"
SPARKLE_FRAMEWORK_SOURCE="${SPARKLE_FRAMEWORK_SOURCE:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-"-"}}"

cd "$ROOT_DIR"

github_repository_slug() {
  local origin_url=""

  origin_url="$(git config --get remote.origin.url 2>/dev/null || true)"
  origin_url="${origin_url%.git}"

  if [[ "$origin_url" =~ github.com[:/]([^/]+/[^/]+)$ ]]; then
    printf "%s" "${BASH_REMATCH[1]}"
  else
    printf "logyxiao/PeakHalo"
  fi
}

APP_UPDATE_REPOSITORY="${APP_UPDATE_REPOSITORY:-${GITHUB_REPOSITORY:-$(github_repository_slug)}}"
SPARKLE_APPCAST_URL="${SPARKLE_APPCAST_URL:-https://github.com/$APP_UPDATE_REPOSITORY/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

if [[ "$MODE" != "--build-app" && "$MODE" != "build-app" && "$MODE" != "bundle" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build -c "$BUILD_CONFIGURATION"
BUILD_BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

while IFS= read -r framework; do
  cp -R "$framework" "$APP_FRAMEWORKS/"
done < <(find "$BUILD_BIN_DIR" -maxdepth 1 -type d -name '*.framework')

if [[ -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  rm -rf "$APP_FRAMEWORKS/Sparkle.framework"
  cp -R "$SPARKLE_FRAMEWORK_SOURCE" "$APP_FRAMEWORKS/"
elif [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "SPARKLE_PUBLIC_ED_KEY is set but Sparkle.framework was not found at $SPARKLE_FRAMEWORK_SOURCE" >&2
  exit 1
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" >/dev/null 2>&1 || true

while IFS= read -r resource_bundle; do
  cp -R "$resource_bundle" "$APP_RESOURCES/"
  if [[ "$(basename "$resource_bundle")" == "${APP_NAME}_${APP_NAME}.bundle" ]]; then
    while IFS= read -r localization_dir; do
      target_localization_dir="$APP_RESOURCES/$(basename "$localization_dir")"
      rm -rf "$target_localization_dir"
      cp -R "$localization_dir" "$APP_RESOURCES/"
    done < <(find "$resource_bundle" -maxdepth 1 -type d -name '*.lproj')
  fi
done < <(find "$BUILD_BIN_DIR" -maxdepth 1 -type d -name '*.bundle')

SPARKLE_INFO_PLIST_ENTRIES=""
if [[ -n "$SPARKLE_APPCAST_URL" ]]; then
  SPARKLE_INFO_PLIST_ENTRIES+="  <key>SUFeedURL</key>
  <string>$SPARKLE_APPCAST_URL</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
"
fi

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  SPARKLE_INFO_PLIST_ENTRIES+="  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>PeakHaloGitHubRepository</key>
  <string>$APP_UPDATE_REPOSITORY</string>
${SPARKLE_INFO_PLIST_ENTRIES}  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAudioCaptureUsageDescription</key>
  <string>PeakHalo uses system audio access to support per-app volume profiles.</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>PeakHalo uses Bluetooth access to show battery levels for connected accessories.</string>
  <key>NSBluetoothPeripheralUsageDescription</key>
  <string>PeakHalo uses Bluetooth access to show battery levels for connected accessories.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$ENTITLEMENTS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.bluetooth</key>
  <true/>
</dict>
</plist>
PLIST

codesign_args=(--force --sign "$CODESIGN_IDENTITY")
if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
  codesign_args+=(--options runtime --timestamp)
fi

while IFS= read -r framework; do
  codesign "${codesign_args[@]}" --deep "$framework" >/dev/null
done < <(find "$APP_FRAMEWORKS" -maxdepth 1 -type d -name '*.framework')

codesign "${codesign_args[@]}" --deep --entitlements "$ENTITLEMENTS_PLIST" "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-app|build-app|bundle)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..50}; do
      if pgrep -f "$APP_BINARY" >/dev/null; then
        exit 0
      fi
      sleep 0.1
    done
    echo "$APP_BUNDLE did not start successfully" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--build-app|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
