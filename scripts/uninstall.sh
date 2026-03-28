#!/bin/bash
# 完整移除 YTMusic App 及其資料
set -euo pipefail

echo "🗑  Uninstalling YTMusic..."

rm -rf /Applications/YTMusic.app
rm -rf ~/Library/WebKit/com.kaa5945.ytmusic
rm -rf ~/Library/Caches/com.kaa5945.ytmusic
rm -rf ~/Library/Preferences/com.kaa5945.ytmusic.plist

echo "✅ YTMusic has been completely removed."
