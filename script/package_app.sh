#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PeakHalo"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
PACKAGE_DIR="$DIST_DIR/package"
RELEASE_DIR="$DIST_DIR/release"

cd "$ROOT_DIR"

version_from_git() {
  if git describe --tags --always --dirty >/dev/null 2>&1; then
    git describe --tags --always --dirty
  else
    date +"%Y%m%d%H%M%S"
  fi
}

VERSION="${1:-$(version_from_git)}"
SAFE_VERSION="$(printf "%s" "$VERSION" | tr -c 'A-Za-z0-9._-' '-')"
DMG_ROOT="$PACKAGE_DIR/dmg-root"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$SAFE_VERSION.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$SAFE_VERSION.dmg"
PKG_PATH="$RELEASE_DIR/$APP_NAME-$SAFE_VERSION.pkg"

rm -rf "$PACKAGE_DIR" "$RELEASE_DIR"
mkdir -p "$DMG_ROOT" "$RELEASE_DIR"

SWIFT_BUILD_CONFIGURATION="${SWIFT_BUILD_CONFIGURATION:-release}" "$ROOT_DIR/script/build_and_run.sh" --build-app

codesign --verify --deep --strict "$APP_BUNDLE"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

pkgbuild \
  --component "$APP_BUNDLE" \
  --install-location /Applications \
  "$PKG_PATH"

cat <<EOF
Created packages:
$ZIP_PATH
$DMG_PATH
$PKG_PATH
EOF
