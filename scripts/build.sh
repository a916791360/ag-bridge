#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="AG Bridge.app"
EXEC_NAME="ag-bridge"
ICON_NAME="AGBridge.icns"
APP_DIR="$DIST_DIR/$APP_NAME"

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/usr/bin/install -m 755 "$ROOT_DIR/src/$EXEC_NAME" \
  "$APP_DIR/Contents/MacOS/$EXEC_NAME"
/bin/cp "$ROOT_DIR/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "$ROOT_DIR/resources/$ICON_NAME" \
  "$APP_DIR/Contents/Resources/$ICON_NAME"

/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

printf 'Built ad-hoc signed app: %s\n' "$APP_DIR"
