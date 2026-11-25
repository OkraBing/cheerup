#!/bin/bash
# 编译成 CheerUp.app（不占 Dock，不出现在 ⌘Tab）
set -e
cd "$(dirname "$0")"
APP="CheerUp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/CheerUp"
if [ -f icon.icns ]; then mkdir -p "$APP/Contents/Resources"; cp icon.icns "$APP/Contents/Resources/icon.icns"; fi
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CheerUp</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundleExecutable</key><string>CheerUp</string>
  <key>CFBundleIdentifier</key><string>local.cheerup</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "已生成 $(pwd)/$APP"
