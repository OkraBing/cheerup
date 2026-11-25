#!/bin/bash
# 编译成 CheerUp.app（不占 Dock，不出现在 ⌘Tab）
set -e
cd "$(dirname "$0")"
APP="CheerUp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
# 同时编出苹果芯片和 Intel 两种，合成一个；哪种编不出来就只用本机这一种
# -file-prefix-map 把源码所在的目录从程序里抹掉，编出来的程序不带本机路径
BIN="$APP/Contents/MacOS/CheerUp"
FLAGS="-O -file-prefix-map $(pwd)=. -debug-prefix-map $(pwd)=."
if swiftc $FLAGS -target arm64-apple-macos12 main.swift -o "$BIN.arm64" 2>/dev/null \
   && swiftc $FLAGS -target x86_64-apple-macos12 main.swift -o "$BIN.x86_64" 2>/dev/null \
   && lipo -create "$BIN.arm64" "$BIN.x86_64" -output "$BIN" 2>/dev/null; then
  rm -f "$BIN.arm64" "$BIN.x86_64"
else
  rm -f "$BIN.arm64" "$BIN.x86_64"
  swiftc $FLAGS main.swift -o "$BIN"
fi
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
# 放在同步盘里的文件夹会被系统加上额外的标记，带着它签不了名，先清掉
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "提示：没签上名（程序在本机仍然能用）"
echo "已生成 $(pwd)/$APP"
