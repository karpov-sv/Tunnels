#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/Tunnels.xcodeproj}"
SCHEME="${SCHEME:-Tunnels}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build}"
APP_NAME="${APP_NAME:-Tunnels.app}"
TEAM_ID="${TEAM_ID:-}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Xcode project not found at $PROJECT_PATH" >&2
  echo "Run ./scripts/generate_xcodeproj.sh first." >&2
  exit 1
fi

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

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  "${SIGN_ARGS[@]}"

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  mapfile -t APPS < <(find "$DERIVED_DATA/Build/Products" -type d -name "*.app" 2>/dev/null)
  if [[ ${#APPS[@]} -gt 0 ]]; then
    APP_PATH="${APPS[0]}"
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found under $DERIVED_DATA/Build/Products" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/$(basename "$APP_PATH")"
cp -R "$APP_PATH" "$OUTPUT_DIR/"

echo "Built app at $OUTPUT_DIR/$(basename "$APP_PATH")"
