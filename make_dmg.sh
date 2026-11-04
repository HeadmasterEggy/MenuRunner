#!/bin/zsh
# 打包 DMG：MenuRunner.app + “应用程序”快捷方式，拖进去即可安装
set -e
cd "$(dirname "$0")"
./build.sh >/dev/null
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" MenuRunner.app/Contents/Info.plist)
STAGE=$(mktemp -d)
cp -R MenuRunner.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
OUT="dist/MenuRunner-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "MenuRunner $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$OUT" >/dev/null
rm -rf "$STAGE"
echo "$OUT"
