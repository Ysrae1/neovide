use super::NativeCommand;
use crate::{
    image_preview::ImageView,
    units::{GridScale, PixelRect},
};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use std::{
    collections::HashMap,
    ffi::{CStr, CString, c_char, c_void},
};
use winit::window::Window;

unsafe extern "C" {
    fn glow_media_create(parent: *mut c_void, path: *const c_char, video: bool) -> *mut c_void;
    fn glow_media_frame(ctx: *mut c_void, x: f64, y: f64, width: f64, height: f64);
    fn glow_media_occlusion(ctx: *mut c_void, rects: *const f64, count: usize);
    fn glow_media_command(ctx: *mut c_void, action: *const c_char, value: f64);
    fn glow_media_status(ctx: *mut c_void) -> *mut c_char;
    fn glow_media_destroy(ctx: *mut c_void);
    fn glow_web_create(parent: *mut c_void, url: *const c_char) -> *mut c_void;
    fn glow_web_frame(ctx: *mut c_void, x: f64, y: f64, width: f64, height: f64);
    fn glow_web_occlusion(ctx: *mut c_void, rects: *const f64, count: usize);
    fn glow_web_command(ctx: *mut c_void, action: *const c_char, value: f64);
    fn glow_web_status(ctx: *mut c_void) -> *mut c_char;
    fn glow_web_destroy(ctx: *mut c_void);
    fn glow_pdf_create(parent: *mut c_void, path: *const c_char) -> *mut c_void;
    fn glow_pdf_frame(ctx: *mut c_void, x: f64, y: f64, width: f64, height: f64);
    fn glow_pdf_occlusion(ctx: *mut c_void, rects: *const f64, count: usize);
    fn glow_pdf_command(ctx: *mut c_void, action: *const c_char, value: f64);
    fn glow_pdf_status(ctx: *mut c_void) -> *mut c_char;
    fn glow_pdf_destroy(ctx: *mut c_void);
    fn free(ptr: *mut c_void);
}

struct Preview {
    context: *mut c_void,
    kind: String,
    view: Option<ImageView>,
}
impl Drop for Preview {
    fn drop(&mut self) {
        // Both AppKit creation and this route-owned drop occur on the UI thread.
        unsafe {
            match self.kind.as_str() {
                "web" => glow_web_destroy(self.context),
                "pdf" => glow_pdf_destroy(self.context),
                _ => glow_media_destroy(self.context),
            }
        }
    }
}
#[derive(Default)]
pub struct NativePreviews {
    previews: HashMap<u64, Preview>,
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
                let result = (|| {
                    if self.previews.len() >= 8 {
                        return Err("Too many native previews (maximum 8)");
                    }
                    let Ok(handle) = window.window_handle() else {
                        return Err("Native window unavailable");
                    };
                    let RawWindowHandle::AppKit(handle) = handle.as_raw() else {
                        return Err("AppKit view unavailable");
                    };
                    let source = CString::new(source).map_err(|_| "Invalid source")?;
                    let context = unsafe {
                        match kind.as_str() {
                            "web" => glow_web_create(handle.ns_view.as_ptr(), source.as_ptr()),
                            "pdf" => glow_pdf_create(handle.ns_view.as_ptr(), source.as_ptr()),
                            _ => glow_media_create(
                                handle.ns_view.as_ptr(),
                                source.as_ptr(),
                                kind == "video",
                            ),
                        }
                    };
                    if context.is_null() {
                        return Err("Cannot create native preview");
                    }
                    self.previews.insert(id, Preview { context, kind, view: None });
                    Ok(())
                })();
                if let Err(error) = result {
                    return Some((
                        id,
                        serde_json::json!({"state":"error","error":error}).to_string(),
                    ));
                }
                Some((id, self.status(id)))
            }
            NativeCommand::Show(id, view) => {
                if let Some(p) = self.previews.get_mut(&id) {
                    p.view = Some(view);
                }
                self.layout(window, scale, padding);
                None
            }
            NativeCommand::Close(id) => {
                self.previews.remove(&id);
                None
            }
            NativeCommand::Action { id, action, value } => {
                let p = self.previews.get(&id)?;
                let action = CString::new(action).ok()?;
                unsafe {
                    match p.kind.as_str() {
                        "web" => glow_web_command(p.context, action.as_ptr(), value),
                        "pdf" => glow_pdf_command(p.context, action.as_ptr(), value),
                        _ => glow_media_command(p.context, action.as_ptr(), value),
                    }
                }
                Some((id, self.status(id)))
            }
        }
    }

    // These are the current animated pixel regions actually drawn by Skia.
    // Cache them so an asynchronous Show uses the same mask before the next frame.
    pub fn set_occlusions(&mut self, regions: Vec<PixelRect<f32>>) {
        self.occlusions = regions;
    }

    pub fn layout(&self, window: &Window, scale: GridScale, padding: (u32, u32)) {
        let dpi = window.scale_factor();
        for p in self.previews.values() {
            let Some(v) = p.view else {
                continue;
            };
            let x = (v.col as f64 * scale.width() as f64 + padding.0 as f64) / dpi;
            let y = (v.row as f64 * scale.height() as f64 + padding.1 as f64) / dpi;
            let w = v.width as f64 * scale.width() as f64 / dpi;
            let h = v.height as f64 * scale.height() as f64 / dpi;
            let occlusions: Vec<[f64; 4]> = self
                .occlusions
                .iter()
                .map(|r| {
                    [
                        r.min.x as f64 / dpi - x,
                        r.min.y as f64 / dpi - y,
                        (r.max.x - r.min.x) as f64 / dpi,
                        (r.max.y - r.min.y) as f64 / dpi,
                    ]
                })
                .collect();
            let rects = occlusions.as_ptr().cast::<f64>();
            unsafe {
                match p.kind.as_str() {
                    "web" => {
                        glow_web_frame(p.context, x, y, w, h);
                        glow_web_occlusion(p.context, rects, occlusions.len());
                    }
                    "pdf" => {
                        glow_pdf_frame(p.context, x, y, w, h);
                        glow_pdf_occlusion(p.context, rects, occlusions.len());
                    }
                    _ => {
                        glow_media_frame(p.context, x, y, w, h);
                        glow_media_occlusion(p.context, rects, occlusions.len());
                    }
                }
            }
        }
    }
    fn status(&self, id: u64) -> String {
        let Some(p) = self.previews.get(&id) else {
            return "{}".into();
        };
        unsafe {
            let ptr = match p.kind.as_str() {
                "web" => glow_web_status(p.context),
                "pdf" => glow_pdf_status(p.context),
                _ => glow_media_status(p.context),
            };
            if ptr.is_null() {
                return "{\"state\":\"error\",\"error\":\"No native status\"}".into();
            }
            let status = CStr::from_ptr(ptr).to_string_lossy().into_owned();
            free(ptr.cast());
            status
        }
    }
}
