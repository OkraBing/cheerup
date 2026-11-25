#!/bin/bash
# 一键安装 CheerUp：下载最新版，放到桌面，然后打开。
# 用法：curl -fsSL https://raw.githubusercontent.com/OkraBing/cheerup/main/install.sh | bash
set -e
URL="https://github.com/OkraBing/cheerup/releases/latest/download/CheerUp.zip"
DEST="$HOME/Desktop"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "正在下载 CheerUp…"
curl -fL --progress-bar "$URL" -o "$TMP/CheerUp.zip"
ditto -x -k "$TMP/CheerUp.zip" "$TMP/out"
[ -d "$TMP/out/CheerUp.app" ] || { echo "下载的文件不对，没有安装。"; exit 1; }

# 已经在运行的先退出，再换成新的
pkill -x CheerUp 2>/dev/null || true
rm -rf "$DEST/CheerUp.app"
mv "$TMP/out/CheerUp.app" "$DEST/CheerUp.app"
# 程序没有苹果的开发者签名；去掉「来自互联网」的标记，否则第一次打开会被系统拦住
xattr -dr com.apple.quarantine "$DEST/CheerUp.app" 2>/dev/null || true

open "$DEST/CheerUp.app"
echo "装好了：桌面上的 CheerUp。小窗在屏幕右下角，屏幕顶部栏里也有它的图标。"
