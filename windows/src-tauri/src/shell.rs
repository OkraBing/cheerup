// 和操作系统窗口直接打交道的部分。真正的实现只在 Windows 上；其他系统上是能编过、能跑起来的简化版，方便在开发机上自查。

use tauri::{AppHandle, WebviewWindow};

#[cfg(windows)]
mod imp {
    use std::sync::atomic::Ordering;
    use std::time::Duration;

    use tauri::{AppHandle, Manager, WebviewWindow};
    use windows::Win32::Foundation::{HWND, POINT, RECT};
    use windows::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON, VK_RBUTTON};
    use windows::Win32::UI::WindowsAndMessaging::{
        GetCursorPos, GetSystemMetrics, GetWindowLongPtrW, GetWindowRect, SetWindowLongPtrW, SetWindowPos, ShowWindow,
        GWL_EXSTYLE, HWND_TOPMOST, SM_SWAPBUTTON, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_NOZORDER, SW_HIDE,
        SW_SHOWNOACTIVATE, WS_EX_APPWINDOW, WS_EX_LAYERED, WS_EX_TOOLWINDOW, WS_EX_TRANSPARENT,
    };

    use crate::Shell;

    fn hwnd(win: &WebviewWindow) -> Option<HWND> {
        win.hwnd().ok()
    }

    /// 把窗口的扩展样式改成我们要的：永远是「工具窗口」（不进任务栏和 Alt+Tab），
    /// 需要点穿时再加上「鼠标事件穿过去」。只动这几位，别的位（置顶、不抢焦点）原样保留。
    /// 每次都先读现在的值再比较，被别处改掉了也会改回来。
    fn apply_ex_style(h: HWND, through: bool) {
        unsafe {
            let cur = GetWindowLongPtrW(h, GWL_EXSTYLE);
            let pass = (WS_EX_TRANSPARENT.0 | WS_EX_LAYERED.0) as isize;
            let mut want = (cur | WS_EX_TOOLWINDOW.0 as isize) & !(WS_EX_APPWINDOW.0 as isize) & !pass;
            if through {
                want |= pass;
            }
            if want != cur {
                SetWindowLongPtrW(h, GWL_EXSTYLE, want);
            }
        }
    }

    pub fn prepare(win: &WebviewWindow) {
        if let Some(h) = hwnd(win) {
            apply_ex_style(h, false);
        }
    }

    /// 显示时不激活（不抢焦点），并且重新放到最上层
    pub fn show_window(win: &WebviewWindow, show: bool) {
        let Some(h) = hwnd(win) else { return };
        unsafe {
            if show {
                let _ = ShowWindow(h, SW_SHOWNOACTIVATE);
                let _ = SetWindowPos(h, Some(HWND_TOPMOST), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            } else {
                let _ = ShowWindow(h, SW_HIDE);
            }
        }
    }

    fn cursor() -> Option<POINT> {
        let mut p = POINT::default();
        unsafe { GetCursorPos(&mut p).ok()? };
        Some(p)
    }

    fn window_rect(h: HWND) -> Option<RECT> {
        let mut r = RECT::default();
        unsafe { GetWindowRect(h, &mut r).ok()? };
        Some(r)
    }

    /// 鼠标主键现在按着吗（有人把左右键对调了，那主键就是右键）
    fn primary_down() -> bool {
        unsafe {
            let key = if GetSystemMetrics(SM_SWAPBUTTON) != 0 { VK_RBUTTON } else { VK_LBUTTON };
            (GetAsyncKeyState(key.0 as i32) as u16 & 0x8000) != 0
        }
    }

    pub fn cursor_offset(win: &WebviewWindow) -> Option<(i32, i32)> {
        let (c, r) = (cursor()?, window_rect(hwnd(win)?)?);
        Some((c.x - r.left, c.y - r.top))
    }

    /// 一直在后台跑的小循环，做三件事：
    ///   · 鼠标在「有内容」的矩形里 → 窗口正常接收点击；在外面 → 整窗点穿
    ///   · 正在拖动 → 让窗口跟着鼠标走，松手时记下位置
    ///   · 顺手保证「工具窗口」样式一直在
    pub fn spawn_watcher(app: AppHandle) {
        std::thread::spawn(move || loop {
            let sh = app.state::<Shell>();
            let shown = sh.shown.load(Ordering::SeqCst);
            let win = crate::main_window(&app);
            let (Some(win), true) = (win, shown) else {
                std::thread::sleep(Duration::from_millis(200));
                continue;
            };
            let Some(h) = hwnd(&win) else {
                std::thread::sleep(Duration::from_millis(200));
                continue;
            };

            let drag = *sh.drag.lock().unwrap();
            if let Some((dx, dy)) = drag {
                apply_ex_style(h, false);
                if primary_down() {
                    if let Some(c) = cursor() {
                        unsafe {
                            let _ = SetWindowPos(h, None, c.x - dx, c.y - dy, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
                        }
                    }
                } else {
                    *sh.drag.lock().unwrap() = None;
                    if let Some(r) = window_rect(h) {
                        crate::save_position(&app, r.left, r.top);
                    }
                    crate::notify(&app);
                }
                std::thread::sleep(Duration::from_millis(8));
                continue;
            }

            if let (Some(c), Some(r)) = (cursor(), window_rect(h)) {
                let scale = win.scale_factor().unwrap_or(1.0);
                let (x, y) = ((c.x - r.left) as f64 / scale, (c.y - r.top) as f64 / scale);
                let inside = sh.rects.lock().unwrap().iter().any(|q| x >= q[0] && x < q[0] + q[2] && y >= q[1] && y < q[1] + q[3]);
                apply_ex_style(h, !inside);
            }
            std::thread::sleep(Duration::from_millis(30));
        });
    }
}

#[cfg(not(windows))]
mod imp {
    use tauri::{AppHandle, WebviewWindow};

    pub fn prepare(_win: &WebviewWindow) {}
    pub fn show_window(win: &WebviewWindow, show: bool) {
        let _ = if show { win.show() } else { win.hide() };
    }
    pub fn cursor_offset(_win: &WebviewWindow) -> Option<(i32, i32)> {
        None
    }
    pub fn spawn_watcher(_app: AppHandle) {}
}

pub fn prepare(win: &WebviewWindow) {
    imp::prepare(win)
}
pub fn show_window(win: &WebviewWindow, show: bool) {
    imp::show_window(win, show)
}
pub fn cursor_offset(win: &WebviewWindow) -> Option<(i32, i32)> {
    imp::cursor_offset(win)
}
pub fn spawn_watcher(app: AppHandle) {
    imp::spawn_watcher(app)
}
