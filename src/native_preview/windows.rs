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

enum Navigation {
    Ready,
    LoadingBlank { id: Option<u64> },
    LoadingPdf { id: Option<u64>, revision: u64, target: String },
}

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
    navigation: Navigation,
    revision: u64,
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
        self.navigation = Navigation::Ready;
        self.layout = None;
        unsafe {
            let _ = ShowWindow(self.host, SW_HIDE);
        }
    }
    fn pdf_url(&self) -> String {
        let mut url = self.source.clone();
        // Edge's PDF viewer accepts standard PDF open parameters. We only
        // report requested page/zoom, never invent a page count or SyncTeX.
        url.set_fragment(Some(&if self.fit {
            format!("page={}&view=FitH", self.page)
        } else {
            format!("page={}&zoom={:.2}", self.page, self.zoom * 100.0)
        }));
        url.into()
    }
    fn request_navigation(preview: &Rc<RefCell<Self>>) -> windows::core::Result<()> {
        let start = {
            let mut preview = preview.borrow_mut();
            preview.revision = preview.revision.wrapping_add(1);
            preview.state = "loading";
            preview.error = None;
            // Keep only the latest requested parameters while initialization or
            // an existing navigation is in flight. A reload also gets a revision.
            preview.webview.is_some() && matches!(preview.navigation, Navigation::Ready)
        };
        if start {
            Self::navigate(preview, true)?;
        }
        Ok(())
    }
    fn navigate(preview: &Rc<RefCell<Self>>, reset: bool) -> windows::core::Result<()> {
        let (webview, target) = {
            let mut preview = preview.borrow_mut();
            let Some(webview) = preview.webview.clone() else {
                return Ok(());
            };
            // Changing only a PDF fragment can leave Edge's PDF viewer on the
            // old page. Finish a different-document navigation before reopening
            // the PDF; do not race two asynchronous Navigate calls.
            let target = if reset {
                preview.navigation = Navigation::LoadingBlank { id: None };
                "about:blank".to_owned()
            } else {
                let target = preview.pdf_url();
                preview.navigation = Navigation::LoadingPdf {
                    id: None,
                    revision: preview.revision,
                    target: target.clone(),
                };
                target
            };
            preview.state = "loading";
            preview.error = None;
            (webview, HSTRING::from(target))
        };
        // Navigation callbacks may access Preview. Never call Navigate with a
        // RefCell borrow held, including when called from a completion handler.
        unsafe { webview.Navigate(&target) }
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
                let result = (|| -> windows::core::Result<()> {
                    let navigate = {
                        let mut preview = preview.borrow_mut();
                        match action.as_str() {
                            "page" => { preview.page = value.clamp(1.0, 1_000_000.0) as u64; true }
                            "next" => { preview.page = preview.page.saturating_add(1).min(1_000_000); true }
                            "previous" => { preview.page = preview.page.saturating_sub(1).max(1); true }
                            "zoom" => { preview.zoom = value.clamp(0.25, 5.0); preview.fit = false; true }
                            "fit" => { preview.fit = true; true }
                            "reload" => true,
                            _ => false,
                        }
                    };
                    if navigate {
                        Preview::request_navigation(preview)?;
                    } else if action == "focus" {
                        let controller = preview.borrow().controller.clone();
                        if let Some(controller) = controller {
                            unsafe { controller.MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC)?; }
                        }
                    } else if action == "blur" {
                        let parent = preview.borrow().parent;
                        unsafe { let _ = SetFocus(Some(parent)); }
                    }
                    Ok(())
                })();
                if let Err(error) = result { preview.borrow_mut().fail(error); }
                Some((id, preview.borrow().status()))
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
            navigation: Navigation::Ready,
            revision: 0,
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
        let starting = weak.clone();
        webview.add_NavigationStarting(
            &NavigationStartingEventHandler::create(Box::new(move |_, args| {
                if let (Some(preview), Some(args)) = (starting.upgrade(), args) {
                    let mut raw = windows::core::PWSTR::null();
                    args.Uri(&mut raw)?;
                    let value = webview2_com::CoTaskMemPWSTR::from(raw).to_string();
                    let mut navigation_id = 0;
                    args.NavigationId(&mut navigation_id)?;
                    let permitted = {
                        let mut preview = preview.borrow_mut();
                        if value == "about:blank" {
                            // This exception is only for our pending reset; PDF
                            // links never gain a general about: navigation right.
                            if let Navigation::LoadingBlank { id } = &mut preview.navigation {
                                if id.is_none() || *id == Some(navigation_id) {
                                    *id = Some(navigation_id);
                                    true
                                } else {
                                    false
                                }
                            } else {
                                false
                            }
                        } else {
                            let permitted = url::Url::parse(&value).is_ok_and(|mut url| {
                                url.set_fragment(None);
                                url == allowed
                            });
                            if permitted {
                                if let Navigation::LoadingPdf { id, target, .. } =
                                    &mut preview.navigation
                                {
                                    if *target == value && id.is_none() {
                                        *id = Some(navigation_id);
                                    }
                                }
                            }
                            permitted
                        }
                    };
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
                    let mut navigation_id = 0;
                    args.NavigationId(&mut navigation_id)?;
                    let next = {
                        let preview = preview.borrow();
                        match &preview.navigation {
                            Navigation::LoadingBlank { id: Some(id) } if *id == navigation_id => {
                                Some(false)
                            }
                            Navigation::LoadingPdf { id: Some(id), revision, .. }
                                if *id == navigation_id =>
                            {
                                (*revision != preview.revision).then_some(true)
                            }
                            // A canceled or older document must not complete a
                            // newer request, including a same-id reopened view.
                            _ => return Ok(()),
                        }
                    };
                    let mut success = BOOL::default();
                    args.IsSuccess(&mut success)?;
                    if success.as_bool() {
                        if let Some(reset) = next {
                            if let Err(error) = Preview::navigate(&preview, reset) {
                                preview.borrow_mut().fail(error);
                            }
                        } else {
                            let mut preview = preview.borrow_mut();
                            preview.navigation = Navigation::Ready;
                            preview.state = "ready";
                        }
                    } else {
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
        // Show may arrive while the environment is still initializing. Apply
        // its latest geometry now, without waiting for another redraw.
        let bounds = preview.borrow().layout.as_ref().map(|(bounds, _)| *bounds);
        if let Some([_, _, w, h]) = bounds {
            controller.SetBounds(RECT { left: 0, top: 0, right: w, bottom: h })?;
            controller.SetIsVisible(w > 0 && h > 0)?;
        }
        {
            let mut preview = preview.borrow_mut();
            preview.controller = Some(controller);
            preview.webview = Some(webview);
            preview.layout = None; // Apply the most recent Show on the next frame.
        }
        Preview::navigate(preview, false)?;
    }
    Ok(())
}
