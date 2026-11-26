# CheerUp · Windows 版（开发中）

用 [Tauri](https://tauri.app) 做：界面是网页技术画的（`ui/`），外面套一层很薄的壳（`src-tauri/`）。Mac 版在仓库根目录的 `main.swift`，两边互不影响。

现在是**阶段 0**：只验证外壳，没有行情、没有会动的拉拉队。窗口里是一块占位面板和一个不动的小人。测试步骤见 [TESTING.md](TESTING.md)。

## 目录

| 位置 | 是什么 |
|---|---|
| `ui/` | 页面：`index.html`、`style.css`、`main.js`，没有构建步骤，可以直接用浏览器打开看 |
| `src-tauri/src/main.rs` | 外壳：托盘、快捷键、开机启动、截图里隐藏、记住位置 |
| `src-tauri/src/shell.rs` | 和 Windows 窗口直接打交道的部分：点穿、不进任务栏、拖动 |
| `src-tauri/tauri.conf.json` | 窗口怎么开：透明、无边框、置顶、不抢焦点 |

## 编译

在 Mac 上直接编免安装版（需要 rustup 和 `brew install mingw-w64`），产物在 `windows/dist/`：

```bash
bash windows/build-on-mac.sh
```

在 Windows 上（需要 Rust 和 Node）：

```bash
cd windows
npx @tauri-apps/cli@2 build
```
