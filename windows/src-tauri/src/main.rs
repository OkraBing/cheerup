// CheerUp Windows 版 · 阶段 0：只验证外壳，没有任何业务功能。
//
// 要验证的六件事：
//   1. 悬浮在最上面，点它不抢走别的程序的焦点      → tauri.conf.json 里 alwaysOnTop + focusable:false
//   2. 透明无边框，透明处点穿、有内容处能点到        → 下面的 watcher：盯着鼠标位置，切换「整窗点穿」
//   3. 不在任务栏和 Alt+Tab 里                       → skipTaskbar + 工具窗口样式（watcher 里补）
//   4. 托盘图标：点一下隐藏/显示，右键退出           → build_tray
//   5. Ctrl+Alt+S 隐藏/显示；开机启动可开关          → global-shortcut / autostart 插件
//   6. 截图和屏幕共享里不显示（可切换）              → set_content_protected
// 另外：拖动（自己跟着鼠标挪，不用系统的拖动，因为不抢焦点的窗口用系统拖动不可靠）、记住位置。

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod shell;

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use tauri::menu::{MenuBuilder, MenuItemBuilder};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, WebviewWindow, WindowEvent};
use tauri_plugin_autostart::ManagerExt as _;
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt as _, Modifiers, Shortcut, ShortcutState};

/// 外壳的运行状态。页面和 watcher 线程都会读写。
#[derive(Default)]
pub struct Shell {
    /// 页面上「有内容」的矩形（x, y, 宽, 高），单位是页面里的逻辑像素。鼠标在这些矩形外面时整窗点穿
    pub rects: Mutex<Vec<[f64; 4]>>,
    /// 正在拖动时：按下那一刻鼠标离窗口左上角多远（屏幕像素）
    pub drag: Mutex<Option<(i32, i32)>>,
    pub shown: AtomicBool,
    pub capture_hidden: AtomicBool,
    pub hotkey_ok: AtomicBool,
    pub tray_ok: AtomicBool,
    /// 小窗被系统「激活」（拿到焦点）了几次。做对了的话应该一直是 0
    pub focus_count: AtomicU32,
}

/// 存在磁盘上的东西：位置，和「截图里隐藏」开没开
#[derive(Serialize, Deserialize, Default, Clone)]
struct Saved {
    x: Option<i32>,
    y: Option<i32>,
    #[serde(default)]
    capture_hidden: bool,
}

fn saved_path(app: &AppHandle) -> Option<std::path::PathBuf> {
    app.path().app_config_dir().ok().map(|d| d.join("shell.json"))
}

fn load_saved(app: &AppHandle) -> Saved {
    saved_path(app)
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn store_saved(app: &AppHandle, f: impl FnOnce(&mut Saved)) {
    let mut s = load_saved(app);
    f(&mut s);
    if let Some(p) = saved_path(app) {
        if let Some(dir) = p.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(text) = serde_json::to_string_pretty(&s) {
            let _ = std::fs::write(p, text);
        }
    }
}

pub fn save_position(app: &AppHandle, x: i32, y: i32) {
    store_saved(app, |s| {
        s.x = Some(x);
        s.y = Some(y);
    });
}

pub fn main_window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window("main")
}

/// 告诉页面「状态变了，重新问一遍」
pub fn notify(app: &AppHandle) {
    let _ = app.emit("shell-changed", ());
}

fn set_shown(app: &AppHandle, show: bool) {
    let Some(win) = main_window(app) else { return };
    app.state::<Shell>().shown.store(show, Ordering::SeqCst);
    shell::show_window(&win, show);
    notify(app);
}

fn toggle_shown(app: &AppHandle) {
    let now = app.state::<Shell>().shown.load(Ordering::SeqCst);
    set_shown(app, !now);
}

// ───────────── 页面能调用的命令 ─────────────

#[derive(Serialize)]
struct StateView {
    version: String,
    capture_hidden: bool,
    autostart: bool,
    hotkey_ok: bool,
    tray_ok: bool,
    focus_count: u32,
    scale: f64,
    x: i32,
    y: i32,
}

#[tauri::command]
fn get_state(app: AppHandle) -> StateView {
    let sh = app.state::<Shell>();
    let win = main_window(&app);
    let pos = win.as_ref().and_then(|w| w.outer_position().ok()).unwrap_or(PhysicalPosition::new(0, 0));
    StateView {
        version: app.package_info().version.to_string(),
        capture_hidden: sh.capture_hidden.load(Ordering::SeqCst),
        autostart: app.autolaunch().is_enabled().unwrap_or(false),
        hotkey_ok: sh.hotkey_ok.load(Ordering::SeqCst),
        tray_ok: sh.tray_ok.load(Ordering::SeqCst),
        focus_count: sh.focus_count.load(Ordering::SeqCst),
        scale: win.as_ref().and_then(|w| w.scale_factor().ok()).unwrap_or(1.0),
        x: pos.x,
        y: pos.y,
    }
}

#[tauri::command]
fn set_hit_rects(app: AppHandle, rects: Vec<[f64; 4]>) {
    *app.state::<Shell>().rects.lock().unwrap() = rects;
}

#[tauri::command]
fn start_drag(app: AppHandle) {
    if let Some(win) = main_window(&app) {
        if let Some(offset) = shell::cursor_offset(&win) {
            *app.state::<Shell>().drag.lock().unwrap() = Some(offset);
        }
    }
}

#[tauri::command]
fn set_capture_hidden(app: AppHandle, on: bool) -> Result<(), String> {
    let win = main_window(&app).ok_or("no window")?;
    win.set_content_protected(on).map_err(|e| e.to_string())?;
    app.state::<Shell>().capture_hidden.store(on, Ordering::SeqCst);
    store_saved(&app, |s| s.capture_hidden = on);
    Ok(())
}

#[tauri::command]
fn set_autostart(app: AppHandle, on: bool) -> Result<(), String> {
    let auto = app.autolaunch();
    if on { auto.enable() } else { auto.disable() }.map_err(|e| e.to_string())
}

#[tauri::command]
fn hide_window(app: AppHandle) {
    set_shown(&app, false);
}

#[tauri::command]
fn quit(app: AppHandle) {
    app.exit(0);
}

// ───────────── 托盘 ─────────────

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let toggle = MenuItemBuilder::with_id("toggle", "显示 / 隐藏").build(app)?;
    let quit = MenuItemBuilder::with_id("quit", "退出").build(app)?;
    let menu = MenuBuilder::new(app).item(&toggle).separator().item(&quit).build()?;
    let mut tray = TrayIconBuilder::with_id("main")
        .tooltip("CheerUp")
        .menu(&menu)
        .show_menu_on_left_click(false) // 左键是隐藏/显示，右键才出菜单
        .on_menu_event(|app, event| match event.id().as_ref() {
            "toggle" => toggle_shown(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                toggle_shown(tray.app_handle());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        tray = tray.icon(icon.clone());
    }
    tray.build(app)?;
    Ok(())
}

// ───────────── 启动 ─────────────

/// 保存的位置还在某块屏幕里吗（显示器拔掉、分辨率变了之后可能不在了）
fn on_some_monitor(win: &WebviewWindow, x: i32, y: i32) -> bool {
    let Ok(size) = win.outer_size() else { return false };
    let (cx, cy) = (x + size.width as i32 / 2, y + size.height as i32 / 2);
    win.available_monitors().unwrap_or_default().iter().any(|m| {
        let (p, s) = (m.position(), m.size());
        cx >= p.x && cx < p.x + s.width as i32 && cy >= p.y && cy < p.y + s.height as i32
    })
}

fn place_window(app: &AppHandle, win: &WebviewWindow, saved: &Saved) {
    if let (Some(x), Some(y)) = (saved.x, saved.y) {
        if on_some_monitor(win, x, y) {
            let _ = win.set_position(PhysicalPosition::new(x, y));
            return;
        }
    }
    // 默认：主屏幕右下角，避开任务栏
    let monitor = win.primary_monitor().ok().flatten().or_else(|| win.current_monitor().ok().flatten());
    if let (Some(m), Ok(size)) = (monitor, win.outer_size()) {
        let area = m.work_area();
        let margin = (24.0 * m.scale_factor()) as i32;
        let x = area.position.x + area.size.width as i32 - size.width as i32 - margin;
        let y = area.position.y + area.size.height as i32 - size.height as i32 - margin;
        let _ = win.set_position(PhysicalPosition::new(x, y));
    }
    let _ = app;
}

fn main() {
    tauri::Builder::default()
        // 已经开着的时候再点一次图标：不开第二个，把已有的小窗叫出来
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| set_shown(app, true)))
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _shortcut, event| {
                    if event.state() == ShortcutState::Pressed {
                        toggle_shown(app);
                    }
                })
                .build(),
        )
        .manage(Shell::default())
        .invoke_handler(tauri::generate_handler![
            get_state,
            set_hit_rects,
            start_drag,
            set_capture_hidden,
            set_autostart,
            hide_window,
            quit
        ])
        .on_window_event(|window, event| {
            if let WindowEvent::Focused(true) = event {
                let app = window.app_handle();
                app.state::<Shell>().focus_count.fetch_add(1, Ordering::SeqCst);
                notify(app);
            }
        })
        .setup(|app| {
            let handle = app.handle().clone();
            let sh = app.state::<Shell>();

            let hotkey = Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyS);
            sh.hotkey_ok.store(handle.global_shortcut().register(hotkey).is_ok(), Ordering::SeqCst);
            sh.tray_ok.store(build_tray(&handle).is_ok(), Ordering::SeqCst);

            if let Some(win) = main_window(&handle) {
                let saved = load_saved(&handle);
                place_window(&handle, &win, &saved);
                if saved.capture_hidden && win.set_content_protected(true).is_ok() {
                    sh.capture_hidden.store(true, Ordering::SeqCst);
                }
                shell::prepare(&win); // 还没显示的时候先把窗口样式设好
                shell::spawn_watcher(handle.clone());
                set_shown(&handle, true);
            }

            // 冒烟测试：设了这个环境变量就打印一行状态、两秒后自己退出
            if std::env::var_os("CHEERUP_SMOKE").is_some() {
                println!(
                    "smoke: window={} tray_ok={} hotkey_ok={}",
                    main_window(&handle).is_some(),
                    sh.tray_ok.load(Ordering::SeqCst),
                    sh.hotkey_ok.load(Ordering::SeqCst)
                );
                let h = handle.clone();
                std::thread::spawn(move || {
                    std::thread::sleep(std::time::Duration::from_secs(2));
                    h.exit(0);
                });
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running CheerUp");
}
