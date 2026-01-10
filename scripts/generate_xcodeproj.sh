#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC_TEMPLATE="$ROOT_DIR/xcodegen.yml"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR}"
PROJECT_NAME="Tunnels"
BUNDLE_ID="${BUNDLE_ID:-com.example.tunnels}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found; falling back to SwiftPM generate-xcodeproj." >&2
  if ! command -v swift >/dev/null 2>&1; then
    echo "swift is required for the fallback." >&2
    exit 1
  fi
  (cd "$ROOT_DIR" && swift package generate-xcodeproj)
  echo "Generated $ROOT_DIR/$PROJECT_NAME.xcodeproj via SwiftPM." >&2
  echo "Note: SwiftPM project builds the CLI product. For a .app bundle, use scripts/build_app.sh or install xcodegen." >&2
  exit 0
fi

if [[ ! -f "$SPEC_TEMPLATE" ]]; then
  echo "Spec template not found at $SPEC_TEMPLATE" >&2
  exit 1
fi

TMP_SPEC="$(mktemp)"
trap 'rm -f "$TMP_SPEC"' EXIT

sed -e "s|{{BUNDLE_ID}}|$BUNDLE_ID|g" -e "s|{{ROOT_DIR}}|$ROOT_DIR|g" "$SPEC_TEMPLATE" > "$TMP_SPEC"

PROJECT_PATH="$OUTPUT_DIR/$PROJECT_NAME.xcodeproj"
if [[ -d "$PROJECT_PATH" ]]; then
  rm -rf "$PROJECT_PATH"
fi

xcodegen generate --spec "$TMP_SPEC" --project "$OUTPUT_DIR" --project-root "$ROOT_DIR"

echo "Generated $PROJECT_PATH"
