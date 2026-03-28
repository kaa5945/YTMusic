#!/bin/bash
# 將 SPM build 的 binary 打包成 macOS .app bundle
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="YTMusic"
BUNDLE_DIR="$PROJECT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# 清理舊 bundle
rm -rf "$BUNDLE_DIR"

# 建立目錄結構
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# 編譯
echo "🔨 Building..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

# 複製 binary
cp "$PROJECT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# 建立 Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>YTMusic</string>
    <key>CFBundleDisplayName</key>
    <string>YTMusic</string>
    <key>CFBundleIdentifier</key>
    <string>com.kaa5945.ytmusic</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>YTMusic</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# 生成 App Icon
echo "🎨 Generating icon..."
python3 "$PROJECT_DIR/scripts/generate_icon.py"

echo "✅ Bundle created at: $BUNDLE_DIR"
echo "   Run with: open \"$BUNDLE_DIR\""
echo "   Install:  cp -R \"$BUNDLE_DIR\" /Applications/"
