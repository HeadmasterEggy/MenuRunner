#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=MenuRunner.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
swiftc -O Sources/**/*.swift -o $APP/Contents/MacOS/MenuRunner
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MenuRunner</string>
  <key>CFBundleIdentifier</key><string>local.joey.menurunner</string>
  <key>CFBundleExecutable</key><string>MenuRunner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.9.1</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
mkdir -p $APP/Contents/Resources
cp assets/AppIcon.icns $APP/Contents/Resources/AppIcon.icns
codesign --force -s - $APP
echo "Built $PWD/$APP"

pkill -x MenuRunner || true
mkdir -p ~/Applications
rm -rf ~/Applications/MenuRunner.app
cp -R $APP ~/Applications/
echo "Installed ~/Applications/MenuRunner.app"
