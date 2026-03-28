#!/bin/bash
# 建立 DMG 安裝映像檔
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="YTMusic"
VERSION="1.0.0"
BUNDLE_DIR="$PROJECT_DIR/build/${APP_NAME}.app"
DMG_DIR="$PROJECT_DIR/build/dmg"
DMG_PATH="$PROJECT_DIR/build/${APP_NAME}-${VERSION}.dmg"

# 先確保 .app bundle 存在
if [ ! -d "$BUNDLE_DIR" ]; then
    echo "⚠️  .app bundle not found, building first..."
    bash "$PROJECT_DIR/scripts/bundle.sh"
fi

# 清理
rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"

# 複製 .app 到 DMG 暫存目錄
cp -R "$BUNDLE_DIR" "$DMG_DIR/"

# 建立 Applications 捷徑
ln -s /Applications "$DMG_DIR/Applications"

# 建立 DMG
echo "📦 Creating DMG..."
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# 清理暫存
rm -rf "$DMG_DIR"

echo "✅ DMG created: $DMG_PATH"
echo "   Size: $(du -h "$DMG_PATH" | cut -f1)"
