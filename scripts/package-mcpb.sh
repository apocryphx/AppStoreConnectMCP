#!/usr/bin/env bash
#
# package-mcpb.sh — clean Release build → AppStoreConnect-Bridge.mcpb
#
# Uses an isolated DerivedData path (outside iCloud, outside Xcode's normal
# location) so the resulting bundle is free of test-injection and other dev
# artifacts that would break codesign or TCC attribution.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

DERIVED="/tmp/asc-bridge-release-derived"
echo "[package] clean Release build into $DERIVED"
rm -rf "$DERIVED"
xcodebuild -project "AppStoreConnectMCP.xcodeproj" \
           -scheme "AppStoreConnectMCP" \
           -configuration Release \
           -derivedDataPath "$DERIVED" \
           clean build >/dev/null

APP="$DERIVED/Build/Products/Release/AppStoreConnect_Bridge.app"
if [[ ! -d "$APP" ]]; then
    echo "[package] .app not produced at $APP" >&2
    exit 1
fi

echo "[package] codesign verify"
codesign -v --strict "$APP"

echo "[package] bundle/server/"
rm -rf "$ROOT/bundle/server"
mkdir -p "$ROOT/bundle/server"
ditto "$APP" "$ROOT/bundle/server/AppStoreConnect_Bridge.app"
xattr -cr "$ROOT/bundle/server" 2>/dev/null || true
codesign --force --deep --sign - -o runtime "$ROOT/bundle/server/AppStoreConnect_Bridge.app"

if [[ -f "$ROOT/icon.png" ]]; then
    cp "$ROOT/icon.png" "$ROOT/bundle/icon.png"
fi

echo "[package] pack mcpb"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
npx --yes @anthropic-ai/mcpb pack "$ROOT/bundle/" "$ROOT/AppStoreConnect-Bridge.mcpb"

echo "[package] wrote $ROOT/AppStoreConnect-Bridge.mcpb"
ls -la "$ROOT/AppStoreConnect-Bridge.mcpb"
