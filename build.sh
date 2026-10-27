#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=Pasteroni.app
rm -rf $APP; mkdir -p $APP/Contents/MacOS
cp "$(swift build -c release --show-bin-path)/Pasteroni" $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Pasteroni</string>
<key>CFBundleIdentifier</key><string>dev.pasteroni.app</string>
<key>CFBundleName</key><string>Pasteroni</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign - $APP
echo "Built $PWD/$APP"
