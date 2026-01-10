#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="Tunnels"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/Tunnels.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/build/export}"
EXPORT_METHOD="${EXPORT_METHOD:-developer-id}"
TEAM_ID="${TEAM_ID:-}"
BUNDLE_ID="${BUNDLE_ID:-com.example.tunnels}"
VERSION="${VERSION:-1}"
SHORT_VERSION="${SHORT_VERSION:-1.0}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"

SIGN_ARGS=()
if [[ -n "$TEAM_ID" ]]; then
  SIGN_ARGS+=("DEVELOPMENT_TEAM=$TEAM_ID")
  SIGN_ARGS+=("CODE_SIGN_STYLE=Automatic")
  SIGN_ARGS+=("CODE_SIGNING_REQUIRED=YES")
  SIGN_ARGS+=("CODE_SIGNING_ALLOWED=YES")
else
  SIGN_ARGS+=("CODE_SIGN_IDENTITY=")
  SIGN_ARGS+=("CODE_SIGNING_REQUIRED=NO")
  SIGN_ARGS+=("CODE_SIGNING_ALLOWED=NO")
fi

xcodebuild -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  "${SIGN_ARGS[@]}"

mkdir -p "$EXPORT_PATH"

if [[ -n "$TEAM_ID" ]]; then
  EXPORT_PLIST="$(mktemp)"
  cat <<PLIST > "$EXPORT_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>$EXPORT_METHOD</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST"
  rm -f "$EXPORT_PLIST"
  echo "Exported app to $EXPORT_PATH"
else
  APP_DIR="$ARCHIVE_PATH/Products/Applications"
  APP_PATH=""
  if [[ -d "$APP_DIR" ]]; then
    mapfile -t APPS < <(find "$APP_DIR" -maxdepth 1 -type d -name "*.app" 2>/dev/null)
    if [[ ${#APPS[@]} -gt 0 ]]; then
      APP_PATH="${APPS[0]}"
    fi
  fi
  if [[ -z "$APP_PATH" ]]; then
    mapfile -t APPS < <(find "$ARCHIVE_PATH" -type d -name "*.app" 2>/dev/null)
    if [[ ${#APPS[@]} -gt 0 ]]; then
      APP_PATH="${APPS[0]}"
    fi
  fi

  if [[ -n "$APP_PATH" && -d "$APP_PATH" ]]; then
    APP_NAME="$(basename "$APP_PATH")"
    rm -rf "$EXPORT_PATH/$APP_NAME"
    cp -R "$APP_PATH" "$EXPORT_PATH/"
    echo "Copied app to $EXPORT_PATH/$APP_NAME"
    exit 0
  fi

  BIN_PATH="$ARCHIVE_PATH/Products/usr/local/bin/$SCHEME"
  if [[ ! -x "$BIN_PATH" ]]; then
    mapfile -t BINS < <(find "$ARCHIVE_PATH/Products" -type f -name "$SCHEME" -perm -111 2>/dev/null)
    if [[ ${#BINS[@]} -gt 0 ]]; then
      BIN_PATH="${BINS[0]}"
    fi
  fi

  if [[ ! -x "$BIN_PATH" ]]; then
    echo "App bundle not found in archive: $ARCHIVE_PATH" >&2
    echo "Executable not found for $SCHEME either." >&2
    exit 1
  fi

  APP_BUNDLE="$EXPORT_PATH/$SCHEME.app"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
  cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$SCHEME"

  cat <<PLIST > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$SCHEME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$SCHEME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

  if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE"
  fi

  echo "Wrapped executable into $APP_BUNDLE"
fi
