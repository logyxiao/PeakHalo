#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PeakHalo"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
PACKAGE_DIR="$DIST_DIR/package"
RELEASE_DIR="$DIST_DIR/release"

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

version_from_git() {
  if git describe --tags --always --dirty >/dev/null 2>&1; then
    git describe --tags --always --dirty
  else
    date +"%Y%m%d%H%M%S"
  fi
}

short_version() {
  local version="$1"
  if [[ "$version" =~ ^v?([0-9]+(\.[0-9]+){0,2}) ]]; then
    printf "%s" "${BASH_REMATCH[1]}"
  else
    printf "0.1.0"
  fi
}

VERSION="${1:-$(version_from_git)}"
SAFE_VERSION="$(printf "%s" "$VERSION" | tr -c 'A-Za-z0-9._-' '-')"
APP_VERSION="${APP_VERSION:-$(short_version "$VERSION")}"
APP_BUILD="${APP_BUILD:-$SAFE_VERSION}"
APP_UPDATE_REPOSITORY="${APP_UPDATE_REPOSITORY:-${GITHUB_REPOSITORY:-$(github_repository_slug)}}"
SPARKLE_DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/$APP_UPDATE_REPOSITORY/releases/download/$VERSION/}"
DMG_ROOT="$PACKAGE_DIR/dmg-root"
APPCAST_SOURCE_DIR="$PACKAGE_DIR/appcast-source"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$SAFE_VERSION.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$SAFE_VERSION.dmg"
PKG_PATH="$RELEASE_DIR/$APP_NAME-$SAFE_VERSION.pkg"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"

if [[ "${REQUIRE_SPARKLE_APPCAST:-0}" == "1" ]]; then
  if [[ -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    echo "REQUIRE_SPARKLE_APPCAST=1 but SPARKLE_PUBLIC_ED_KEY is missing." >&2
    exit 1
  fi

  if [[ -z "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
    echo "REQUIRE_SPARKLE_APPCAST=1 but SPARKLE_PRIVATE_ED_KEY is missing." >&2
    exit 1
  fi
fi

if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" && -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  echo "SPARKLE_PRIVATE_ED_KEY is set but SPARKLE_PUBLIC_ED_KEY is missing." >&2
  exit 1
fi

rm -rf "$PACKAGE_DIR" "$RELEASE_DIR"
mkdir -p "$DMG_ROOT" "$RELEASE_DIR"

APP_VERSION="$APP_VERSION" \
APP_BUILD="$APP_BUILD" \
SWIFT_BUILD_CONFIGURATION="${SWIFT_BUILD_CONFIGURATION:-release}" \
  bash "$ROOT_DIR/script/build_and_run.sh" --build-app

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

if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  if [[ ! -x "$SPARKLE_GENERATE_APPCAST" ]]; then
    echo "Sparkle generate_appcast not found at $SPARKLE_GENERATE_APPCAST" >&2
    exit 1
  fi

  mkdir -p "$APPCAST_SOURCE_DIR"
  cp "$ZIP_PATH" "$APPCAST_SOURCE_DIR/"
  printf "%s" "$SPARKLE_PRIVATE_ED_KEY" | "$SPARKLE_GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "$SPARKLE_DOWNLOAD_URL_PREFIX" \
    -o "$APPCAST_PATH" \
    "$APPCAST_SOURCE_DIR"
else
  echo "Skipping Sparkle appcast generation because SPARKLE_PRIVATE_ED_KEY is not set."
fi

cat <<EOF
Created packages:
$ZIP_PATH
$DMG_PATH
$PKG_PATH
EOF

if [[ -f "$APPCAST_PATH" ]]; then
  echo "$APPCAST_PATH"
fi
