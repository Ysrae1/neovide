//! PDF-only WebView2 child views. Creation and callbacks stay on Winit's STA UI
//! thread; no blocking message pump, subprocess, package identity or second loop.
use super::NativeCommand;
use crate::{
    image_preview::ImageView,
    units::{GridScale, PixelRect},
};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use std::{
    cell::RefCell,
    collections::HashMap,
    rc::{Rc, Weak},
};
use webview2_com::{
    AcceleratorKeyPressedEventHandler, CreateCoreWebView2ControllerCompletedHandler,
    CreateCoreWebView2EnvironmentCompletedHandler, Microsoft::Web::WebView2::Win32::*,
    NavigationCompletedEventHandler, NavigationStartingEventHandler,
    NewWindowRequestedEventHandler,
};
use windows::{
    Win32::{
        Foundation::{HWND, RECT},
        Graphics::Gdi::{CombineRgn, CreateRectRgn, DeleteObject, RGN_DIFF, SetWindowRgn},
        System::Com::{COINIT_APARTMENTTHREADED, CoInitializeEx, CoUninitialize},
        UI::{
            Input::KeyboardAndMouse::{SetFocus, VK_ESCAPE},
            WindowsAndMessaging::{
                CreateWindowExW, DestroyWindow, SW_HIDE, SW_SHOWNA, SWP_NOACTIVATE, SWP_NOZORDER,
                SetWindowPos, ShowWindow, WS_CHILD, WS_CLIPCHILDREN, WS_CLIPSIBLINGS,
            },
        },
    },
    core::{BOOL, HSTRING, PCWSTR, w},
};
use winit::window::Window;

struct Apartment;
impl Apartment {
    fn new() -> windows::core::Result<Self> {
        unsafe {
            CoInitializeEx(None, COINIT_APARTMENTTHREADED).ok()?;
        }
        Ok(Self)
    }
}
impl Drop for Apartment {
    fn drop(&mut self) {
        unsafe {
            CoUninitialize();
        }
    }
}

type Layout = ([i32; 4], Vec<[i32; 4]>);

struct Preview {
    parent: HWND,
    host: HWND,
    controller: Option<ICoreWebView2Controller>,
    webview: Option<ICoreWebView2>,
    source: url::Url,
    view: Option<ImageView>,
    state: &'static str,
    error: Option<String>,
    page: u64,
    zoom: f64,
    fit: bool,
    // Last HWND bounds and subtracted editor floats, in physical pixels.
    layout: Option<Layout>,
}
impl Drop for Preview {
    fn drop(&mut self) {
        unsafe {
            if let Some(controller) = self.controller.take() {
                let _ = controller.Close();
            }
            let _ = DestroyWindow(self.host);
        }
    }
}
impl Preview {
    fn fail(&mut self, error: impl std::fmt::Display) {
        self.state = "error";
        self.error = Some(error.to_string());
        unsafe {
            let _ = ShowWindow(self.host, SW_HIDE);
        }
    }
    fn navigate(&self) -> windows::core::Result<()> {
        if let Some(webview) = &self.webview {
            let mut url = self.source.clone();
            // Edge's PDF viewer accepts standard PDF open parameters. We only
            // report requested page/zoom, never invent a page count or SyncTeX.
            url.set_fragment(Some(&if self.fit {
                format!("page={}&view=FitH", self.page)
            } else {
                format!("page={}&zoom={:.2}", self.page, self.zoom * 100.0)
            }));
            unsafe {
                webview.Navigate(&HSTRING::from(url.as_str()))?;
            }
        }
        Ok(())
    }
    fn status(&self) -> String {
        serde_json::json!({"state":self.state,"error":self.error,"source":self.source.as_str(),
            "page":self.page,"zoom":self.zoom,"backend":"webview2",
            "page_state":"requested","synctex_supported":false})
        .to_string()
    }
}

#[derive(Default)]
pub struct NativePreviews {
    // Drop views before our matching CoUninitialize, on the same UI thread.
    previews: HashMap<u64, Rc<RefCell<Preview>>>,
    occlusions: Vec<PixelRect<f32>>,
    apartment: Option<Apartment>,
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
        window.request_redraw();
        match command {
            NativeCommand::Open { id, kind, source } => {
                self.previews.remove(&id);
                let result = self.open(id, &kind, &source, window);
                Some((id, match result {
                    Ok(()) => self.previews[&id].borrow().status(),
                    Err(error) => serde_json::json!({"state":"error","error":error}).to_string(),
                }))
            }
            NativeCommand::Show(id, view) => {
                if let Some(preview) = self.previews.get(&id) { preview.borrow_mut().view = Some(view); }
                self.layout(window, scale, padding);
                None
            }
            NativeCommand::Close(id) => { self.previews.remove(&id); None }
            NativeCommand::PdfSync { id, .. } => {
                Some((id, serde_json::json!({"state":"error",
                    "error":"Windows embedded PDF does not yet support coordinate SyncTeX; use the external PDF viewer for forward search.",
                    "synctex_supported":false}).to_string()))
            }
            NativeCommand::Action { id, action, value } => {
                let preview = self.previews.get(&id)?;
                let mut preview = preview.borrow_mut();
                let result = (|| -> windows::core::Result<()> {
                    match action.as_str() {
                        "page" => { preview.page = value.clamp(1.0, 1_000_000.0) as u64; preview.navigate()?; }
                        "next" => { preview.page = preview.page.saturating_add(1).min(1_000_000); preview.navigate()?; }
                        "previous" => { preview.page = preview.page.saturating_sub(1).max(1); preview.navigate()?; }
                        "zoom" => { preview.zoom = value.clamp(0.25, 5.0); preview.fit = false; preview.navigate()?; }
                        "fit" => { preview.fit = true; preview.navigate()?; }
                        "reload" => { if let Some(webview) = &preview.webview { unsafe { webview.Reload()?; } } }
                        "focus" => { if let Some(controller) = &preview.controller { unsafe { controller.MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC)?; } } }
                        "blur" => { unsafe { let _ = SetFocus(Some(preview.parent)); } }
                        _ => {}
                    }
                    Ok(())
                })();
                if let Err(error) = result { preview.fail(error); }
                Some((id, preview.status()))
            }
        }
    }

    fn open(&mut self, id: u64, kind: &str, source: &str, window: &Window) -> Result<(), String> {
        if kind != "pdf" {
            return Err("This Windows backend supports PDF only".into());
        }
        if self.previews.len() >= 8 {
            return Err("Too many native previews (maximum 8)".into());
        }
        if self.apartment.is_none() {
            self.apartment = Some(Apartment::new().map_err(|e| e.to_string())?);
        }
        let mut source = if source.starts_with("file:") {
            let url = url::Url::parse(source).map_err(|e| e.to_string())?;
            if url.scheme() != "file" {
                return Err("PDF preview requires a local file".into());
            }
            url
        } else {
            url::Url::from_file_path(source).map_err(|_| "PDF path must be absolute")?
        };
        source.set_fragment(None);
        let handle = window.window_handle().map_err(|e| e.to_string())?;
        let RawWindowHandle::Win32(handle) = handle.as_raw() else {
            return Err("Win32 parent unavailable".into());
        };
        let parent = HWND(handle.hwnd.get() as *mut _);
        let host = unsafe {
            CreateWindowExW(
                Default::default(),
                w!("STATIC"),
                w!(""),
                WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
                0,
                0,
                1,
                1,
                Some(parent),
                None,
                None,
                None,
            )
            .map_err(|e| e.to_string())?
        };
        let preview = Rc::new(RefCell::new(Preview {
            parent,
            host,
            controller: None,
            webview: None,
            source,
            view: None,
            state: "loading",
            error: None,
            page: 1,
            zoom: 1.0,
            fit: true,
            layout: None,
        }));
        self.previews.insert(id, preview.clone());
        let weak = Rc::downgrade(&preview);
        let folder = dirs::cache_dir()
            .ok_or("No writable WebView2 cache directory")?
            .join("neovide-glow")
            .join("webview2");
        std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
        let folder = HSTRING::from(folder.as_os_str());
        let handler = CreateCoreWebView2EnvironmentCompletedHandler::create(Box::new(
            move |error, environment| {
                let Some(preview) = weak.upgrade() else {
                    return Ok(());
                };
                let result = (|| -> windows::core::Result<()> {
                    error?;
                    let environment = environment.ok_or_else(|| {
                        windows::core::Error::from_hresult(windows::Win32::Foundation::E_POINTER)
                    })?;
                    let next = weak.clone();
                    unsafe {
                        environment.CreateCoreWebView2Controller(
                            host,
                            &CreateCoreWebView2ControllerCompletedHandler::create(Box::new(
                                move |error, controller| {
                                    let Some(preview) = next.upgrade() else {
                                        if let Some(controller) = controller {
                                            let _ = controller.Close();
                                        }
                                        return Ok(());
                                    };
                                    if let Err(error) =
                                        initialize(&preview, error, controller, next.clone())
                                    {
                                        preview.borrow_mut().fail(error);
                                    }
                                    Ok(())
                                },
                            )),
                        )?;
                    }
                    Ok(())
                })();
                if let Err(error) = result {
                    preview.borrow_mut().fail(error);
                }
                Ok(())
            },
        ));
        if let Err(error) = unsafe {
            CreateCoreWebView2EnvironmentWithOptions(PCWSTR::null(), &folder, None, &handler)
        } {
            preview.borrow_mut().fail(format!("WebView2 Runtime is unavailable: {error}"));
        }
        Ok(())
    }

    pub fn set_occlusions(&mut self, regions: Vec<PixelRect<f32>>) {
        self.occlusions = regions;
    }
    pub fn layout(&self, _window: &Window, scale: GridScale, padding: (u32, u32)) {
        for preview in self.previews.values() {
            let mut preview = preview.borrow_mut();
            let Some(view) = preview.view else {
                continue;
            };
            if preview.state == "error" {
                continue;
            }
            let x = (view.col * scale.width() + padding.0 as f32).round() as i32;
            let y = (view.row * scale.height() + padding.1 as f32).round() as i32;
            let w = (view.width * scale.width()).round().max(0.0) as i32;
            let h = (view.height * scale.height()).round().max(0.0) as i32;
            let holes: Vec<[i32; 4]> = self
                .occlusions
                .iter()
                .filter_map(|r| {
                    let hole = [
                        (r.min.x.round() as i32 - x).clamp(0, w),
                        (r.min.y.round() as i32 - y).clamp(0, h),
                        (r.max.x.round() as i32 - x).clamp(0, w),
                        (r.max.y.round() as i32 - y).clamp(0, h),
                    ];
                    (hole[0] < hole[2] && hole[1] < hole[3]).then_some(hole)
                })
                .collect();
            let key = ([x, y, w, h], holes);
            if preview.layout.as_ref() == Some(&key) {
                continue;
            }
            let result = (|| -> windows::core::Result<()> {
                unsafe {
                    SetWindowPos(preview.host, None, x, y, w, h, SWP_NOACTIVATE | SWP_NOZORDER)?;
                    let region = CreateRectRgn(0, 0, w, h);
                    for hole in &key.1 {
                        let cut = CreateRectRgn(hole[0], hole[1], hole[2], hole[3]);
                        CombineRgn(Some(region), Some(region), Some(cut), RGN_DIFF);
                        let _ = DeleteObject(cut.into());
                    }
                    // A successful SetWindowRgn transfers region ownership to USER32.
                    if SetWindowRgn(preview.host, Some(region), true) == 0 {
                        let _ = DeleteObject(region.into());
                    }
                    if let Some(controller) = &preview.controller {
                        controller.SetBounds(RECT { left: 0, top: 0, right: w, bottom: h })?;
                        controller.SetIsVisible(w > 0 && h > 0)?;
                        controller.NotifyParentWindowPositionChanged()?;
                    }
                    let _ =
                        ShowWindow(preview.host, if w > 0 && h > 0 { SW_SHOWNA } else { SW_HIDE });
                    Ok(())
                }
            })();
            if let Err(error) = result {
                preview.fail(error);
            }
            preview.layout = Some(key);
        }
    }
}

fn initialize(
    preview: &Rc<RefCell<Preview>>,
    error: windows::core::Result<()>,
    controller: Option<ICoreWebView2Controller>,
    weak: Weak<RefCell<Preview>>,
) -> windows::core::Result<()> {
    error?;
    let controller = controller
        .ok_or_else(|| windows::core::Error::from_hresult(windows::Win32::Foundation::E_POINTER))?;
    unsafe {
        let webview = controller.CoreWebView2()?;
        controller.SetIsVisible(false)?;
        let settings = webview.Settings()?;
        settings.SetAreDevToolsEnabled(false)?;
        settings.SetIsWebMessageEnabled(false)?;
        let mut token = 0;
        let allowed = preview.borrow().source.clone();
        webview.add_NavigationStarting(
            &NavigationStartingEventHandler::create(Box::new(move |_, args| {
                if let Some(args) = args {
                    let mut raw = windows::core::PWSTR::null();
                    args.Uri(&mut raw)?;
                    let value = webview2_com::CoTaskMemPWSTR::from(raw).to_string();
                    let permitted = url::Url::parse(&value).is_ok_and(|mut url| {
                        url.set_fragment(None);
                        url == allowed
                    });
                    // A PDF link cannot turn a PDF-only capability into arbitrary
                    // web or filesystem browsing inside the editor.
                    if !permitted {
                        args.SetCancel(true)?;
                    }
                }
                Ok(())
            })),
            &mut token,
        )?;
        webview.add_NewWindowRequested(
            &NewWindowRequestedEventHandler::create(Box::new(|_, args| {
                if let Some(args) = args {
                    args.SetHandled(true)?;
                }
                Ok(())
            })),
            &mut token,
        )?;
        let completed = weak.clone();
        webview.add_NavigationCompleted(
            &NavigationCompletedEventHandler::create(Box::new(move |_, args| {
                if let (Some(preview), Some(args)) = (completed.upgrade(), args) {
                    let mut success = BOOL::default();
                    args.IsSuccess(&mut success)?;
                    if success.as_bool() {
                        preview.borrow_mut().state = "ready";
                    } else {
                        let mut status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
                        args.WebErrorStatus(&mut status)?;
                        if status == COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED {
                            return Ok(());
                        }
                        preview.borrow_mut().fail("WebView2 could not load this PDF");
                    }
                }
                Ok(())
            })),
            &mut token,
        )?;
        controller.add_AcceleratorKeyPressed(
            &AcceleratorKeyPressedEventHandler::create(Box::new(move |_, args| {
                if let (Some(preview), Some(args)) = (weak.upgrade(), args) {
                    let mut key = 0;
                    args.VirtualKey(&mut key)?;
                    if key == VK_ESCAPE.0 as u32 {
                        args.SetHandled(true)?;
                        let _ = SetFocus(Some(preview.borrow().parent));
                    }
                }
                Ok(())
            })),
            &mut token,
        )?;
        let mut preview = preview.borrow_mut();
        // Show may arrive while the environment is still initializing. Apply
        // its latest geometry now, without waiting for another redraw.
        if let Some(([_, _, w, h], _)) = &preview.layout {
            controller.SetBounds(RECT { left: 0, top: 0, right: *w, bottom: *h })?;
            controller.SetIsVisible(*w > 0 && *h > 0)?;
        }
        preview.controller = Some(controller);
        preview.webview = Some(webview);
        preview.layout = None; // Apply the most recent Show on the next frame.
        preview.navigate()?;
    }
    Ok(())
}
