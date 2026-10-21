//! X11 child previews backed by isolated GTK/WebKit/Poppler helper processes.
//! The existing winit thread never pumps GTK or waits for child pipe I/O.
use super::NativeCommand;
use crate::{
    image_preview::ImageView,
    units::{GridScale, PixelRect},
};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    collections::HashMap,
    io::{BufRead, BufReader, Read, Write},
    process::{Child, Command, Stdio},
    sync::{OnceLock, mpsc},
    thread,
    time::{Duration, Instant},
};
use winit::window::Window;

const HELPER: &str = include_str!("linux_helper.py");
const MAX_MESSAGE: usize = 64 * 1024;

fn python() -> std::ffi::OsString {
    // Distribution PyGObject belongs to the system interpreter, not the user's
    // Notebook virtual environment. An explicit override is still supported.
    std::env::var_os("NEOVIDE_LINUX_PREVIEW_PYTHON").unwrap_or_else(|| "/usr/bin/python3".into())
}

/// Probe GI typelibs without opening a window. Called once on a blocking worker
/// during bridge setup, never from the winit event loop.
pub fn available_kinds() -> &'static [String] {
    static KINDS: OnceLock<Vec<String>> = OnceLock::new();
    KINDS.get_or_init(|| {
        // Winit prefers Wayland when both display variables are set. Cross-
        // process XEmbed is an X11 facility, so never advertise it on Wayland.
        if std::env::var_os("DISPLAY").is_none()
            || std::env::var_os("WAYLAND_DISPLAY").is_some()
            || std::env::var_os("WAYLAND_SOCKET").is_some()
        {
            return Vec::new();
        }
        let Ok(mut child) = Command::new(python())
            .args(["-I", "-u", "-c", HELPER, "--probe"])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        else {
            return Vec::new();
        };
        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            match child.try_wait() {
                Ok(Some(status)) if status.success() => break,
                Ok(Some(_)) => return Vec::new(),
                Err(_) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Vec::new();
                }
                Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
                Ok(None) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Vec::new();
                }
            }
        }
        let mut output = String::new();
        if let Some(stdout) = child.stdout.take() {
            let _ = stdout.take(MAX_MESSAGE as u64).read_to_string(&mut output);
        }
        serde_json::from_str::<Value>(&output)
            .ok()
            .and_then(|value| value.get("kinds").and_then(Value::as_array).cloned())
            .unwrap_or_default()
            .iter()
            .filter_map(Value::as_str)
            .filter(|kind| ["web", "audio", "video", "pdf"].contains(kind))
            .map(str::to_owned)
            .collect()
    })
}

type Layout = ([i32; 4], Vec<[i32; 4]>, u64);

struct Preview {
    child: Child,
    commands: mpsc::SyncSender<Value>,
    statuses: mpsc::Receiver<Value>,
    status: Value,
    view: Option<ImageView>,
    layout: Option<Layout>,
}

impl Drop for Preview {
    fn drop(&mut self) {
        // Only terminate this preview's child. Closing a route cannot affect
        // another route, an external browser or the user's Python processes.
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

impl Preview {
    fn send(&self, command: Value) -> bool {
        self.commands.try_send(command).is_ok()
    }

    fn status(&mut self) -> String {
        for status in self.statuses.try_iter() {
            self.status = status;
        }
        if let Ok(Some(exit)) = self.child.try_wait()
            && self.status.get("state").and_then(Value::as_str) != Some("error")
        {
            self.status = json!({"state":"error", "backend":"gtk-xembed",
                "error":format!("Linux preview helper exited ({exit}); check GTK3, WebKitGTK and Poppler dependencies.")});
        }
        self.status.to_string()
    }
}

#[derive(Default)]
pub struct NativePreviews {
    previews: HashMap<u64, RefCell<Preview>>,
    occlusions: Vec<PixelRect<f32>>,
}

impl NativePreviews {
    pub fn clear(&mut self) {
        self.previews.clear();
    }

    pub fn handle(
        &mut self,
        command: NativeCommand,
        window: &Window,
        scale: GridScale,
        padding: (u32, u32),
    ) -> Option<(u64, String)> {
        match command {
            NativeCommand::Open { id, kind, source } => {
                self.previews.remove(&id);
                let result = self.open(id, &kind, &source, window);
                Some((
                    id,
                    match result {
                        Ok(()) => self.previews[&id].borrow_mut().status(),
                        Err(error) => {
                            json!({"state":"error", "error":error, "backend":"gtk-xembed"})
                                .to_string()
                        }
                    },
                ))
            }
            NativeCommand::Show(id, view) => {
                if let Some(preview) = self.previews.get(&id) {
                    preview.borrow_mut().view = Some(view);
                }
                self.layout(window, scale, padding);
                None
            }
            NativeCommand::Close(id) => {
                self.previews.remove(&id);
                None
            }
            NativeCommand::Action { id, action, value } => {
                let mut preview = self.previews.get(&id)?.borrow_mut();
                if !preview.send(json!({"type":"action", "action":action, "value":value})) {
                    return Some((id, json!({"state":"error", "error":"Linux preview command queue is unavailable"}).to_string()));
                }
                Some((id, preview.status()))
            }
            NativeCommand::PdfSync { id, page, x, y, width, height } => {
                let mut preview = self.previews.get(&id)?.borrow_mut();
                if !preview.send(json!({"type":"sync", "page":page, "x":x, "y":y, "width":width, "height":height})) {
                    return Some((id, json!({"state":"error", "error":"Linux preview command queue is unavailable"}).to_string()));
                }
                Some((id, preview.status()))
            }
        }
    }

    fn open(&mut self, id: u64, kind: &str, source: &str, window: &Window) -> Result<(), String> {
        if self.previews.len() >= 8 {
            return Err("Too many native previews (maximum 8)".into());
        }
        let handle = window.window_handle().map_err(|error| error.to_string())?;
        let parent = match handle.as_raw() {
            RawWindowHandle::Xlib(handle) => handle.window as u64,
            RawWindowHandle::Xcb(handle) => u64::from(handle.window.get()),
            _ => return Err("Linux embedded previews require an X11/Xwayland parent; a native Wayland surface cannot host an XEmbed child.".into()),
        };
        let mut child = Command::new(python())
            .args([
                "-I",
                "-u",
                "-c",
                HELPER,
                "--parent",
                &parent.to_string(),
                "--kind",
                kind,
                "--source",
                source,
            ])
            .env("GDK_BACKEND", "x11")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|error| format!("Cannot start Linux preview helper: {error}"))?;
        let mut input = child.stdin.take().ok_or("Linux preview stdin is unavailable")?;
        let output = child.stdout.take().ok_or("Linux preview stdout is unavailable")?;
        let (commands, command_rx) = mpsc::sync_channel::<Value>(16);
        let (status_tx, statuses) = mpsc::sync_channel(16);
        thread::spawn(move || {
            for value in command_rx {
                if writeln!(input, "{value}").and_then(|_| input.flush()).is_err() {
                    break;
                }
            }
        });
        thread::spawn(move || {
            let mut reader = BufReader::new(output);
            loop {
                let mut line = Vec::new();
                let Ok(length) =
                    reader.by_ref().take((MAX_MESSAGE + 1) as u64).read_until(b'\n', &mut line)
                else {
                    break;
                };
                if length == 0 || length > MAX_MESSAGE || !line.ends_with(b"\n") {
                    break;
                }
                if let Ok(value) = serde_json::from_slice::<Value>(&line)
                    && value.is_object()
                {
                    // The frontend requests status every 500 ms. Drop an
                    // intermediate update rather than block a helper process.
                    let _ = status_tx.try_send(value);
                }
            }
        });
        self.previews.insert(
            id,
            RefCell::new(Preview {
                child,
                commands,
                statuses,
                status: json!({"state":"loading", "backend":"gtk-xembed"}),
                view: None,
                layout: None,
            }),
        );
        Ok(())
    }

    pub fn set_occlusions(&mut self, regions: Vec<PixelRect<f32>>) {
        self.occlusions = regions;
    }

    pub fn layout(&self, window: &Window, scale: GridScale, padding: (u32, u32)) {
        let dpi = window.scale_factor();
        for preview in self.previews.values() {
            let mut preview = preview.borrow_mut();
            let Some(view) = preview.view else { continue };
            let bounds = [
                (view.col * scale.width() + padding.0 as f32).round() as i32,
                (view.row * scale.height() + padding.1 as f32).round() as i32,
                (view.width * scale.width()).round().max(0.0) as i32,
                (view.height * scale.height()).round().max(0.0) as i32,
            ];
            let holes = occlusion_holes(bounds, &self.occlusions);
            let key = (bounds, holes, dpi.to_bits());
            if preview.layout.as_ref() == Some(&key) {
                continue;
            }
            if preview.send(json!({"type":"layout", "bounds":bounds, "holes":key.1, "dpi":dpi})) {
                preview.layout = Some(key);
            }
        }
    }
}

fn occlusion_holes(bounds: [i32; 4], regions: &[PixelRect<f32>]) -> Vec<[i32; 4]> {
    let [x, y, width, height] = bounds;
    regions
        .iter()
        .filter_map(|region| {
            let hole = [
                (region.min.x.floor() as i32 - x).clamp(0, width),
                (region.min.y.floor() as i32 - y).clamp(0, height),
                (region.max.x.ceil() as i32 - x).clamp(0, width),
                (region.max.y.ceil() as i32 - y).clamp(0, height),
            ];
            (hole[0] < hole[2] && hole[1] < hole[3]).then_some(hole)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::units::PixelPos;

    #[test]
    fn child_holes_preserve_parent_float_intersections() {
        let regions = vec![
            PixelRect::new(PixelPos::new(5.0, 15.0), PixelPos::new(35.5, 50.5)),
            PixelRect::new(PixelPos::new(500.0, 500.0), PixelPos::new(600.0, 600.0)),
        ];
        assert_eq!(occlusion_holes([10, 20, 100, 80], &regions), vec![[0, 0, 26, 31]]);
    }
}
