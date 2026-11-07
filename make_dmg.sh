#!/bin/zsh
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
