//! Native background material behind the existing winit/Metal content view.
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use std::{
    ffi::c_void,
    sync::atomic::{AtomicBool, Ordering},
};
use winit::window::Window;

static ENABLED: AtomicBool = AtomicBool::new(false);
unsafe extern "C" {
    fn glow_glass_create(editor_view: *mut c_void, enabled: bool) -> *mut c_void;
    fn glow_glass_set_enabled(handle: *mut c_void, enabled: bool);
    fn glow_glass_layout(handle: *mut c_void);
    fn glow_glass_destroy(handle: *mut c_void);
    fn glow_glass_panel(panel_view: *mut c_void, enabled: bool, radius: f64);
    fn glow_glass_surface(child_view: *mut c_void, enabled: bool);
}
pub(crate) fn enabled() -> bool {
    ENABLED.load(Ordering::Relaxed)
}
pub(crate) fn panel(view: &objc2_app_kit::NSView) {
    unsafe {
        glow_glass_panel((view as *const objc2_app_kit::NSView).cast_mut().cast(), enabled(), 12.0)
    }
}

pub(crate) fn surface(view: &objc2_app_kit::NSView) {
    unsafe {
        glow_glass_surface((view as *const objc2_app_kit::NSView).cast_mut().cast(), enabled())
    }
}

#[derive(Debug)]
pub(crate) struct GlassMaterial {
    handle: *mut c_void,
}
impl GlassMaterial {
    pub fn new(window: &Window, enabled: bool) -> Self {
        ENABLED.store(enabled, Ordering::Relaxed);
        let handle = window.window_handle().ok().and_then(|handle| match handle.as_raw() {
            RawWindowHandle::AppKit(handle) => Some(handle.ns_view.as_ptr()),
            _ => None,
        });
        Self {
            handle: handle
                .map_or(std::ptr::null_mut(), |view| unsafe { glow_glass_create(view, enabled) }),
        }
    }
    pub fn set_enabled(&self, enabled: bool) {
        ENABLED.store(enabled, Ordering::Relaxed);
        unsafe { glow_glass_set_enabled(self.handle, enabled) }
    }
    pub fn layout(&self) {
        unsafe { glow_glass_layout(self.handle) }
    }
}
impl Drop for GlassMaterial {
    fn drop(&mut self) {
        unsafe { glow_glass_destroy(self.handle) }
    }
}
