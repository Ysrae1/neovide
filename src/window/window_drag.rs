use rmpv::Value;

/// A tabline click, resolved by Neovim's own click definitions rather than
/// guessing which painted text or highlight belongs to a button.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WindowDragRequest {
    pub column: u32,
}

impl WindowDragRequest {
    pub fn parse(arguments: &[Value]) -> Result<Self, &'static str> {
        let [snapshot] = arguments else { return Err("Expected one window-drag request") };
        let fields = snapshot.as_map().ok_or("Window-drag request must be a map")?;
        if fields.len() != 3 {
            return Err("Window-drag request needs version, row and column");
        }
        let field = |name| {
            fields.iter().find_map(|(key, value)| (key.as_str() == Some(name)).then_some(value))
        };
        if field("version").and_then(Value::as_u64) != Some(1)
            || field("row").and_then(Value::as_u64) != Some(0)
        {
            return Err("Expected version 1 and root tabline row 0");
        }
        let column = field("column")
            .and_then(Value::as_u64)
            .filter(|column| *column < 65_536)
            .ok_or("Invalid tabline column")? as u32;
        Ok(Self { column })
    }
}

#[cfg(any(target_os = "windows", test))]
mod input {
    use std::time::{Duration, Instant};

    use crate::units::{PixelPos, PixelRect};

    use super::WindowDragRequest;

    // A delayed callback must never start moving a window after a stalled UI
    // resumes. A normal click-to-notification round trip is well below this.
    const MAX_REQUEST_AGE: Duration = Duration::from_millis(500);

    #[derive(Clone, Copy, Debug)]
    pub struct TablinePress {
        pub column: u32,
        pub bounds: PixelRect<f32>,
        pub at: Instant,
    }

    #[derive(Clone, Copy, Debug)]
    pub struct DragConditions {
        pub frameless: bool,
        pub focused: bool,
        pub left_down: bool,
        pub no_modifiers: bool,
    }

    #[derive(Default)]
    pub struct WindowDragState {
        press: Option<TablinePress>,
        native_release_pending: bool,
    }

    impl WindowDragState {
        pub fn press(&mut self, press: Option<TablinePress>) {
            // Windows can consume the previous release in its native move
            // loop. A new press always starts a fresh editor interaction.
            self.native_release_pending = false;
            self.press = press;
        }

        pub fn cancel(&mut self) {
            self.press = None;
            self.native_release_pending = false;
        }

        pub fn release(&mut self) -> bool {
            self.press = None;
            std::mem::take(&mut self.native_release_pending)
        }

        pub fn begin(
            &mut self,
            request: WindowDragRequest,
            pointer: PixelPos<f32>,
            conditions: DragConditions,
            now: Instant,
        ) -> bool {
            let Some(press) = self.press else { return false };
            if !conditions.frameless
                || !conditions.focused
                || !conditions.left_down
                || !conditions.no_modifiers
                || request.column != press.column
                || pointer.x < press.bounds.min.x
                || pointer.x >= press.bounds.max.x
                || pointer.y < press.bounds.min.y
                || pointer.y >= press.bounds.max.y
                || now.saturating_duration_since(press.at) > MAX_REQUEST_AGE
            {
                return false;
            }
            self.press = None;
            self.native_release_pending = true;
            true
        }
    }
}

#[cfg(any(target_os = "windows", test))]
pub use input::{DragConditions, TablinePress, WindowDragState};

#[cfg(target_os = "windows")]
pub fn plain_left_button_down() -> bool {
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        GetAsyncKeyState, VK_CONTROL, VK_LBUTTON, VK_LWIN, VK_MENU, VK_RBUTTON, VK_RWIN, VK_SHIFT,
    };
    use windows::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_SWAPBUTTON};
    // The native move loop can consume a release before winit reports it. Read
    // only the high bit (current state), never the unreliable "pressed since"
    // bit, and reject modifiers even if their winit events are still queued.
    unsafe {
        // GetAsyncKeyState reports physical buttons. Honor Windows' primary
        // button mapping so left-handed users retain the same tabline gesture.
        let primary = if GetSystemMetrics(SM_SWAPBUTTON) != 0 { VK_RBUTTON } else { VK_LBUTTON };
        GetAsyncKeyState(i32::from(primary.0)) < 0
            && [VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN]
                .into_iter()
                .all(|key| GetAsyncKeyState(i32::from(key.0)) >= 0)
    }
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, Instant};

    use super::*;
    use crate::units::{PixelPos, PixelRect};

    fn packet(version: i64, row: i64, column: i64) -> Vec<Value> {
        vec![Value::Map(vec![
            ("version".into(), version.into()),
            ("row".into(), row.into()),
            ("column".into(), column.into()),
        ])]
    }

    #[test]
    fn window_drag_request_rejects_other_rows_versions_and_malformed_packets() {
        assert_eq!(
            WindowDragRequest::parse(&packet(1, 0, 12)),
            Ok(WindowDragRequest { column: 12 })
        );
        for bad in [packet(2, 0, 12), packet(1, 1, 12), packet(1, 0, -1), packet(1, 0, 65_536)] {
            assert!(WindowDragRequest::parse(&bad).is_err());
        }
        assert!(WindowDragRequest::parse(&[]).is_err());
        assert!(
            WindowDragRequest::parse(&[Value::Map(vec![
                ("version".into(), 1.into()),
                ("row".into(), 0.into()),
                ("row".into(), 0.into()),
            ])])
            .is_err()
        );
    }

    fn conditions() -> DragConditions {
        DragConditions { frameless: true, focused: true, left_down: true, no_modifiers: true }
    }

    fn press(at: Instant) -> TablinePress {
        TablinePress { column: 12, bounds: PixelRect::from_min_max((0.0, 0.0), (800.0, 20.0)), at }
    }

    #[test]
    fn window_drag_requires_current_plain_left_press_in_the_same_tabline() {
        let now = Instant::now();
        let request = WindowDragRequest { column: 12 };
        let pointer = PixelPos::new(125.0, 10.0);
        let mut state = WindowDragState::default();
        assert!(
            !state.begin(request, pointer, conditions(), now),
            "RPC alone is not a mouse press"
        );
        for denied in [
            DragConditions { frameless: false, ..conditions() },
            DragConditions { focused: false, ..conditions() },
            DragConditions { left_down: false, ..conditions() },
            DragConditions { no_modifiers: false, ..conditions() },
        ] {
            state.press(Some(press(now)));
            assert!(!state.begin(request, pointer, denied, now));
        }
        state.press(Some(press(now)));
        assert!(!state.begin(WindowDragRequest { column: 13 }, pointer, conditions(), now));
        assert!(!state.begin(request, PixelPos::new(125.0, 20.0), conditions(), now));
        assert!(!state.begin(request, pointer, conditions(), now + Duration::from_millis(501)));
        state.release();
        assert!(
            !state.begin(request, pointer, conditions(), now),
            "released clicks cannot start a move"
        );
    }

    #[test]
    fn window_drag_consumes_its_release_once_and_does_not_swallow_the_next_click() {
        let now = Instant::now();
        let request = WindowDragRequest { column: 12 };
        let pointer = PixelPos::new(125.0, 10.0);
        let mut state = WindowDragState::default();
        state.press(Some(press(now)));
        assert!(state.begin(request, pointer, conditions(), now));
        assert!(
            !state.begin(request, pointer, conditions(), now),
            "one press starts at most one move"
        );
        assert!(state.release());
        assert!(!state.release());
        state.press(Some(press(now)));
        assert!(state.begin(request, pointer, conditions(), now));
        state.press(None); // A normal editor/control click after Windows consumed the native release.
        assert!(!state.release());
        state.press(Some(press(now)));
        state.cancel();
        assert!(
            !state.begin(request, pointer, conditions(), now),
            "focus loss invalidates queued requests"
        );
    }
}
