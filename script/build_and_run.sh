#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PeakHalo"
BUNDLE_ID="com.logyxiao.PeakHalo"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="${SWIFT_BUILD_CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PLIST="$DIST_DIR/$APP_NAME.entitlements"
APP_ICON_SOURCE="$ROOT_DIR/Sources/PeakHalo/Resources/AppIcon.icns"

cd "$ROOT_DIR"

if [[ "$MODE" != "--build-app" && "$MODE" != "build-app" && "$MODE" != "bundle" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build -c "$BUILD_CONFIGURATION"
BUILD_BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

while IFS= read -r resource_bundle; do
  cp -R "$resource_bundle" "$APP_RESOURCES/"
  find "$resource_bundle" -maxdepth 1 -type d -name '*.lproj' -exec cp -R {} "$APP_RESOURCES/" \;
done < <(find "$BUILD_BIN_DIR" -maxdepth 1 -type d -name '*.bundle')

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
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

codesign --force --sign - --entitlements "$ENTITLEMENTS_PLIST" "$APP_BUNDLE" >/dev/null

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
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-app|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
