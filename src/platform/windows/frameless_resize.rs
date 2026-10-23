//! Restore Windows' native resize hit targets for `--frame none`. Winit 0.30
//! retains WS_THICKFRAME but expands its client area over the sizing border.
//! The system still owns resize cursors, capture and the modal sizing loop.
//! Track that loop for every frame style so redraws can prepare new grid sizes
//! while Windows temporarily owns the event loop.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ResizeEdge {
    North,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
    NorthWest,
}

fn screen_point(lparam: isize) -> (i32, i32) {
    // WM_NCHITTEST coordinates are signed words, including on monitors to the
    // left/above the primary display. LOWORD/HIWORD alone would lose the sign.
    (i32::from(lparam as i16), i32::from((lparam >> 16) as i16))
}

fn resize_edge(point: (i32, i32), bounds: [i32; 4], border: (i32, i32)) -> Option<ResizeEdge> {
    let [left, top, right, bottom] = bounds.map(i64::from);
    let (x, y) = (i64::from(point.0), i64::from(point.1));
    if right <= left || bottom <= top || x < left || x >= right || y < top || y >= bottom {
        return None;
    }
    let border_x = i64::from(border.0.max(0)).min((right - left) / 2);
    let border_y = i64::from(border.1.max(0)).min((bottom - top) / 2);
    let west = x < left + border_x;
    let east = x >= right - border_x;
    let north = y < top + border_y;
    let south = y >= bottom - border_y;
    match (west, east, north, south) {
        (true, _, true, _) => Some(ResizeEdge::NorthWest),
        (_, true, true, _) => Some(ResizeEdge::NorthEast),
        (true, _, _, true) => Some(ResizeEdge::SouthWest),
        (_, true, _, true) => Some(ResizeEdge::SouthEast),
        (true, _, _, _) => Some(ResizeEdge::West),
        (_, true, _, _) => Some(ResizeEdge::East),
        (_, _, true, _) => Some(ResizeEdge::North),
        (_, _, _, true) => Some(ResizeEdge::South),
        _ => None,
    }
}

#[cfg(target_os = "windows")]
mod native {
    use std::{cell::RefCell, collections::HashSet};

    use raw_window_handle::{HasWindowHandle, RawWindowHandle};
    use windows::Win32::{
        Foundation::{HWND, LPARAM, LRESULT, RECT, WPARAM},
        Graphics::Gdi::{RDW_INTERNALPAINT, RedrawWindow},
        UI::{
            HiDpi::{GetDpiForWindow, GetSystemMetricsForDpi},
            Input::KeyboardAndMouse::GetCapture,
            Shell::{DefSubclassProc, RemoveWindowSubclass, SetWindowSubclass},
            WindowsAndMessaging::{
                GWL_STYLE, GetWindowLongW, GetWindowRect, HTBOTTOM, HTBOTTOMLEFT, HTBOTTOMRIGHT,
                HTLEFT, HTRIGHT, HTTOP, HTTOPLEFT, HTTOPRIGHT, IsZoomed, SIZE_MINIMIZED,
                SM_CXPADDEDBORDER, SM_CXSIZEFRAME, SM_CYSIZEFRAME, WM_ENTERSIZEMOVE,
                WM_EXITSIZEMOVE, WM_NCDESTROY, WM_NCHITTEST, WM_SIZE, WM_SIZING, WS_THICKFRAME,
            },
        },
    };
    use winit::window::Window;

    use super::{ResizeEdge, resize_edge, screen_point};

    const SUBCLASS_ID: usize = 0x474c4f57;
    const FRAMELESS_HIT_TEST: usize = 1;

    thread_local! {
        // The subclass and Application query both run on the HWND's Winit UI
        // thread. Track each window independently and drop it on destruction,
        // without adding GetWindowSubclass's Comctl32 v6 manifest requirement.
        static LIVE_RESIZES: RefCell<HashSet<usize>> = RefCell::new(HashSet::new());
        static LIVE_MOVES: RefCell<HashSet<usize>> = RefCell::new(HashSet::new());
    }

    pub fn install(window: &Window, frameless: bool) {
        let Ok(handle) = window.window_handle() else {
            log::warn!("Could not get window handle for native resizing");
            return;
        };
        let RawWindowHandle::Win32(handle) = handle.as_raw() else { return };
        // create_window calls this on the HWND's owning Winit UI thread. No
        // application pointer is retained; WM_NCDESTROY removes the callback.
        if !unsafe {
            SetWindowSubclass(
                HWND(handle.hwnd.get() as _),
                Some(subclass),
                SUBCLASS_ID,
                if frameless { FRAMELESS_HIT_TEST } else { 0 },
            )
        }
        .as_bool()
        {
            log::warn!("Could not install native resize handling");
        }
    }

    pub fn is_resizing(window: &Window) -> bool {
        let Ok(handle) = window.window_handle() else { return false };
        let RawWindowHandle::Win32(handle) = handle.as_raw() else { return false };
        LIVE_RESIZES.with(|windows| windows.borrow().contains(&(handle.hwnd.get() as usize)))
    }

    unsafe extern "system" fn subclass(
        hwnd: HWND,
        message: u32,
        wparam: WPARAM,
        lparam: LPARAM,
        subclass_id: usize,
        data: usize,
    ) -> LRESULT {
        unsafe {
            if message == WM_NCDESTROY {
                LIVE_RESIZES.with(|windows| windows.borrow_mut().remove(&(hwnd.0 as usize)));
                LIVE_MOVES.with(|windows| windows.borrow_mut().remove(&(hwnd.0 as usize)));
                let _ = RemoveWindowSubclass(hwnd, Some(subclass), subclass_id);
            } else if message == WM_ENTERSIZEMOVE {
                LIVE_MOVES.with(|windows| windows.borrow_mut().insert(hwnd.0 as usize));
                LIVE_RESIZES.with(|windows| windows.borrow_mut().remove(&(hwnd.0 as usize)));
            } else if message == WM_EXITSIZEMOVE {
                LIVE_MOVES.with(|windows| windows.borrow_mut().remove(&(hwnd.0 as usize)));
                let resized =
                    LIVE_RESIZES.with(|windows| windows.borrow_mut().remove(&(hwnd.0 as usize)));
                let result = DefSubclassProc(hwnd, message, wparam, lparam);
                if resized {
                    // The final Snap geometry may arrive as the modal loop
                    // ends. Queue one paint after Winit has handled the exit.
                    let _ = RedrawWindow(Some(hwnd), None, None, RDW_INTERNALPAINT);
                }
                return result;
            } else if message == WM_SIZING {
                LIVE_RESIZES.with(|windows| windows.borrow_mut().insert(hwnd.0 as usize));
            } else if message == WM_SIZE
                && wparam.0 != SIZE_MINIMIZED as usize
                && LIVE_MOVES.with(|windows| windows.borrow().contains(&(hwnd.0 as usize)))
            {
                // Drag-to-Snap can change size without WM_SIZING. Continue
                // native paints for asynchronous grid updates only after an
                // actual size event; ordinary title-bar moves keep pacing.
                LIVE_RESIZES.with(|windows| windows.borrow_mut().insert(hwnd.0 as usize));
            } else if message == WM_NCHITTEST
                && data & FRAMELESS_HIT_TEST != 0
                && GetWindowLongW(hwnd, GWL_STYLE) as u32 & WS_THICKFRAME.0 != 0
                && !IsZoomed(hwnd).as_bool()
                && GetCapture().0.is_null()
            {
                // Winit removes WS_THICKFRAME in both fullscreen modes and
                // when resizing is disabled. Keep editor drags with capture
                // in the client area, including when they reach an edge.
                let mut rect = RECT::default();
                if GetWindowRect(hwnd, &mut rect).is_ok() {
                    let dpi = match GetDpiForWindow(hwnd) {
                        0 => 96,
                        dpi => dpi,
                    };
                    let padding = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
                    let border = (
                        (GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + padding).max(1),
                        (GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padding).max(1),
                    );
                    if let Some(edge) = resize_edge(
                        screen_point(lparam.0),
                        [rect.left, rect.top, rect.right, rect.bottom],
                        border,
                    ) {
                        return LRESULT(match edge {
                            ResizeEdge::North => HTTOP,
                            ResizeEdge::NorthEast => HTTOPRIGHT,
                            ResizeEdge::East => HTRIGHT,
                            ResizeEdge::SouthEast => HTBOTTOMRIGHT,
                            ResizeEdge::South => HTBOTTOM,
                            ResizeEdge::SouthWest => HTBOTTOMLEFT,
                            ResizeEdge::West => HTLEFT,
                            ResizeEdge::NorthWest => HTTOPLEFT,
                        } as isize);
                    }
                }
            }
            // Interior tab labels, the tabline's blank drag area, editor input
            // and every unrelated message retain Winit's original handling.
            DefSubclassProc(hwnd, message, wparam, lparam)
        }
    }
}

#[cfg(target_os = "windows")]
pub use native::{install, is_resizing};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frameless_resize_hits_all_eight_directions_at_each_dpi() {
        for scale in [1, 2, 3] {
            let bounds = [-600, -400, -600 + 500 * scale, -400 + 400 * scale];
            let [left, top, right, bottom] = bounds;
            let mid_x = (left + right) / 2;
            let mid_y = (top + bottom) / 2;
            for (point, edge) in [
                ((left, top), ResizeEdge::NorthWest),
                ((mid_x, top), ResizeEdge::North),
                ((right - 1, top), ResizeEdge::NorthEast),
                ((right - 1, mid_y), ResizeEdge::East),
                ((right - 1, bottom - 1), ResizeEdge::SouthEast),
                ((mid_x, bottom - 1), ResizeEdge::South),
                ((left, bottom - 1), ResizeEdge::SouthWest),
                ((left, mid_y), ResizeEdge::West),
            ] {
                assert_eq!(resize_edge(point, bounds, (8 * scale, 8 * scale)), Some(edge));
            }
        }
    }

    #[test]
    fn frameless_resize_leaves_tabline_interior_and_outside_points_alone() {
        let bounds = [100, 200, 1100, 1000];
        for point in
            [(116, 216), (600, 224), (600, 600), (1083, 983), (99, 200), (1100, 300), (100, 1000)]
        {
            assert_eq!(resize_edge(point, bounds, (16, 16)), None, "{point:?}");
        }
        assert_eq!(resize_edge((115, 600), bounds, (16, 16)), Some(ResizeEdge::West));
        assert_eq!(resize_edge((1084, 600), bounds, (16, 16)), Some(ResizeEdge::East));
        assert_eq!(resize_edge((600, 215), bounds, (16, 16)), Some(ResizeEdge::North));
        assert_eq!(resize_edge((600, 984), bounds, (16, 16)), Some(ResizeEdge::South));
    }

    #[test]
    fn frameless_resize_preserves_signed_monitor_coordinates() {
        for (x, y) in [(-1200i32, -300i32), (-10, 400), (500, -20), (10, 20)] {
            let packed = (u32::from(x as u16) | (u32::from(y as u16) << 16)) as isize;
            assert_eq!(screen_point(packed), (x, y));
        }
    }

    #[test]
    fn frameless_resize_rejects_degenerate_bounds_and_disabled_border() {
        for bounds in [[0, 0, 0, 20], [0, 0, 20, 0], [20, 20, 0, 0]] {
            assert_eq!(resize_edge((0, 0), bounds, (8, 8)), None);
        }
        assert_eq!(resize_edge((0, 0), [0, 0, 500, 400], (0, 0)), None);
    }
}
