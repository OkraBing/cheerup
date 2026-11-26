#!/bin/bash
# 在 Mac 上交叉编译 Windows 免安装版（不出安装程序）。
# 需要：rustup（带 1.90.0 以上工具链和 x86_64-pc-windows-gnu 目标）、brew 的 mingw-w64。
#
# Tauri 会把「工程所在的文件夹路径」写进程序里，所以先把工程复制到一个中性的位置再编，
# 免得把本机用户名、文件夹名带进发出去的 exe。编完扫一遍，发现本机路径就报错。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="/Users/Shared/cheerup-build"
OUT="${1:-$HERE/dist}"
TOOLCHAIN="${TOOLCHAIN:-1.90.0}"

mkdir -p "$WORK"
rsync -a --delete --exclude target --exclude gen "$HERE/src-tauri" "$HERE/ui" "$WORK/"

cd "$WORK/src-tauri"
export CARGO_TARGET_DIR="$WORK/target"
export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc
export RUSTFLAGS="--remap-path-prefix=$HOME/.cargo/registry/src=crates --remap-path-prefix=$HOME/.rustup=rustup --remap-path-prefix=$WORK=cheerup"
cargo "+$TOOLCHAIN" build --release --target x86_64-pc-windows-gnu

REL="$WORK/target/x86_64-pc-windows-gnu/release"
LOADER="$(find "$REL/build" -path '*webview2-com-sys*/out/x64/WebView2Loader.dll' | head -1)"

# 扫描：程序里不能有本机用户目录
if LC_ALL=C grep -a -q -e "$HOME" -e "/Users/$USER" "$REL/cheerup.exe"; then
  echo "错误：exe 里有本机路径，不能发出去" >&2
  exit 1
fi

rm -rf "$OUT" && mkdir -p "$OUT/CheerUp"
cp "$REL/cheerup.exe" "$OUT/CheerUp/CheerUp.exe"
cp "$LOADER" "$OUT/CheerUp/WebView2Loader.dll"
(cd "$OUT" && rm -f CheerUp-windows.zip && zip -qr -X CheerUp-windows.zip CheerUp)
echo "完成：$OUT/CheerUp-windows.zip"
