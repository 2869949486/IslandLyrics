#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="dist/灵动岛歌词.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchLyrics "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# 菜单栏图标走 SF Symbol(music.note.list, template)，无需图片资源
[ -f Resources/sample-cover.png ] && cp Resources/sample-cover.png "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
