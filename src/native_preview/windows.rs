//! Offline PDF.js views hosted by WebView2 on Winit's STA UI thread.
use super::{
    NativeCommand,
    pdf_bridge::{self, ViewerEvent},
};
use crate::{
    image_preview::ImageView,
    units::{GridScale, PixelRect},
};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    collections::HashMap,
    path::PathBuf,
    rc::{Rc, Weak},
};
use webview2_com::{
    AcceleratorKeyPressedEventHandler, CreateCoreWebView2ControllerCompletedHandler,
    CreateCoreWebView2EnvironmentCompletedHandler, DownloadStartingEventHandler,
    ExecuteScriptCompletedHandler, Microsoft::Web::WebView2::Win32::*,
    NavigationCompletedEventHandler, NavigationStartingEventHandler,
    NewWindowRequestedEventHandler, PermissionRequestedEventHandler,
    WebMessageReceivedEventHandler, WebResourceRequestedEventHandler,
};
use windows::{
    Win32::{
        Foundation::{E_OUTOFMEMORY, HWND, RECT},
        Graphics::Gdi::{CombineRgn, CreateRectRgn, DeleteObject, RGN_DIFF, SetWindowRgn},
        System::Com::{
            COINIT_APARTMENTTHREADED, CoInitializeEx, CoUninitialize, IStream, STGM_READ,
            STGM_SHARE_DENY_NONE,
        },
        UI::{
            Input::KeyboardAndMouse::{SetFocus, VK_ESCAPE},
            Shell::{SHCreateMemStream, SHCreateStreamOnFileEx},
            WindowsAndMessaging::{
                CreateWindowExW, DestroyWindow, SW_HIDE, SW_SHOWNA, SWP_NOACTIVATE, SWP_NOZORDER,
                SetWindowPos, ShowWindow, WS_CHILD, WS_CLIPCHILDREN, WS_CLIPSIBLINGS,
            },
        },
    },
    core::{BOOL, HSTRING, Interface, PCWSTR, w},
};
use winit::window::Window;
#[path = "pdf_viewer/resources.rs"]
mod pdf_resources;

const CSP: &str = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; worker-src 'self' blob:; connect-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' blob: data:; font-src 'self' blob: data:; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
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
    file: PathBuf,
    prefix: String,
    view: Option<ImageView>,
    state: &'static str,
    error: Option<String>,
    page: u64,
    pages: u64,
    zoom: f64,
    ready: bool,
    revision: u64,
    navigation_id: Option<u64>,
    pending: Vec<Value>,
    pending_reload: bool,
    inverse: Option<Value>,
    inverse_seq: u64,
    input_seq: u64,
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
        self.ready = false;
        self.layout = None;
        unsafe {
            let _ = ShowWindow(self.host, SW_HIDE);
        }
    }
    fn status(&self) -> String {
        json!({"state":self.state,"error":self.error,"source":self.source.as_str(),
            "page":self.page,"page_count":self.pages,"zoom":self.zoom,"backend":"webview2-pdfjs",
            "page_state":"observed","synctex_supported":true,"synctex":self.inverse})
        .to_string()
    }
    fn execute(preview: &Rc<RefCell<Self>>, mut command: Value) -> windows::core::Result<()> {
        let (webview, revision) = {
            let state = preview.borrow();
            let Some(webview) = state.webview.clone() else {
                return Ok(());
            };
            (webview, state.revision)
        };
        command["revision"] = revision.into();
        let script = HSTRING::from(format!("window.glowPdf.command({command})"));
        let weak = Rc::downgrade(preview);
        unsafe {
            webview.ExecuteScript(
                &script,
                &ExecuteScriptCompletedHandler::create(Box::new(move |result, _| {
                    if let Err(error) = result
                        && let Some(preview) = weak.upgrade()
                    {
                        let mut preview = preview.borrow_mut();
                        if preview.revision == revision {
                            preview.fail(error);
                        }
                    }
                    Ok(())
                })),
            )
        }
    }
    fn command(preview: &Rc<RefCell<Self>>, command: Value) -> windows::core::Result<()> {
        if !preview.borrow().ready {
            let mut state = preview.borrow_mut();
            if state.pending.len() == 32 {
                state.pending.remove(0);
            }
            state.pending.push(command);
            return Ok(());
        }
        Self::execute(preview, command)
    }
    fn reload(preview: &Rc<RefCell<Self>>) -> windows::core::Result<()> {
        {
            let mut state = preview.borrow_mut();
            if !state.ready {
                state.pending_reload = true;
                return Ok(());
            }
            state.revision = state.revision.wrapping_add(1);
            state.ready = false;
            state.state = "loading";
            state.error = None;
            state.inverse = None;
            state.input_seq = 0;
        }
        Self::execute(preview, json!({"action":"reload"}))
    }
    fn message(preview: &Rc<RefCell<Self>>, message: &str) -> windows::core::Result<()> {
        let mut state = preview.borrow_mut();
        let Some(event) = pdf_bridge::event(message, state.revision) else {
            return Ok(());
        };
        let mut loaded = false;
        match event {
            ViewerEvent::Ready { page, pages, zoom } => {
                state.page = page;
                state.pages = pages;
                state.zoom = zoom;
                state.ready = true;
                state.state = "ready";
                state.error = None;
                loaded = true;
            }
            ViewerEvent::Status { page, pages, zoom } => {
                state.page = page;
                state.pages = pages;
                state.zoom = zoom;
            }
            ViewerEvent::Inverse { page, x, y, seq }
                if state.ready && page <= state.pages && seq > state.input_seq =>
            {
                state.input_seq = seq;
                state.inverse_seq = state.inverse_seq.wrapping_add(1).max(1);
                state.inverse = Some(json!({"page":page,"x":x,"y":y,"seq":state.inverse_seq}));
            }
            ViewerEvent::Error(error) => state.fail(error),
            _ => {}
        }
        let reload = loaded && std::mem::take(&mut state.pending_reload);
        let pending =
            if loaded && !reload { std::mem::take(&mut state.pending) } else { Vec::new() };
        drop(state);
        if reload {
            Self::reload(preview)?;
        }
        for command in pending {
            Self::execute(preview, command)?;
        }
        Ok(())
    }
}
#[derive(Default)]
pub struct NativePreviews {
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
                Some((
                    id,
                    match result {
                        Ok(()) => self.previews[&id].borrow().status(),
                        Err(error) => json!({"state":"error","error":error}).to_string(),
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
            NativeCommand::PdfSync { id, page, x, y, width, height } => {
                let preview = self.previews.get(&id)?;
                if let Err(error) = Preview::command(
                    preview,
                    json!({"action":"pdf_sync","page":page,"x":x,"y":y,"width":width,"height":height}),
                ) {
                    preview.borrow_mut().fail(error);
                }
                Some((id, preview.borrow().status()))
            }
            NativeCommand::Action { id, action, value } => {
                let preview = self.previews.get(&id)?;
                let result = (|| -> windows::core::Result<()> {
                    match action.as_str() {
                        "reload" => Preview::reload(preview)?,
                        "focus" => {
                            let controller = preview.borrow().controller.clone();
                            if let Some(controller) = controller {
                                unsafe {
                                    controller
                                        .MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC)?;
                                }
                            }
                        }
                        "blur" => {
                            let parent = preview.borrow().parent;
                            unsafe {
                                let _ = SetFocus(Some(parent));
                            }
                        }
                        "page" | "next" | "previous" => {
                            let page = {
                                let mut state = preview.borrow_mut();
                                state.page = match action.as_str() {
                                    "next" => state.page.saturating_add(1).min(1_000_000),
                                    "previous" => state.page.saturating_sub(1).max(1),
                                    _ => value.clamp(1.0, 1_000_000.0) as u64,
                                };
                                state.page
                            };
                            Preview::command(
                                preview,
                                json!({"action":"page","page":page,"value":page}),
                            )?;
                        }
                        "zoom" => Preview::command(
                            preview,
                            json!({"action":action,"value":value.clamp(0.25,5.0)}),
                        )?,
                        "fit" => Preview::command(preview, json!({"action":"fit"}))?,
                        _ => {}
                    }
                    Ok(())
                })();
                if let Err(error) = result {
                    preview.borrow_mut().fail(error);
                }
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
            url::Url::parse(source).map_err(|e| e.to_string())?
        } else {
            url::Url::from_file_path(source).map_err(|_| "PDF path must be absolute")?
        };
        source.set_fragment(None);
        let file = source.to_file_path().map_err(|_| "PDF preview requires a local file")?;
        let size = std::fs::metadata(&file).map_err(|e| e.to_string())?;
        if !size.is_file() || size.len() > 256 * 1024 * 1024 {
            return Err("PDF must be a regular file no larger than 256 MiB".into());
        }
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
            file,
            prefix: format!("https://glow-pdf.invalid/{:032x}/", rand::random::<u128>()),
            view: None,
            state: "loading",
            error: None,
            page: 1,
            pages: 0,
            zoom: 1.0,
            ready: false,
            revision: 0,
            navigation_id: None,
            pending: Vec::new(),
            pending_reload: false,
            inverse: None,
            inverse_seq: 0,
            input_seq: 0,
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
                    let resources = environment.clone();
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
                                    if let Err(error) = initialize(
                                        &preview,
                                        error,
                                        controller,
                                        next.clone(),
                                        resources.clone(),
                                    ) {
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
    environment: ICoreWebView2Environment,
) -> windows::core::Result<()> {
    error?;
    let controller = controller
        .ok_or_else(|| windows::core::Error::from_hresult(windows::Win32::Foundation::E_POINTER))?;
    unsafe {
        let webview = controller.CoreWebView2()?;
        controller.SetIsVisible(false)?;
        let settings = webview.Settings()?;
        settings.SetAreDevToolsEnabled(false)?;
        settings.SetIsWebMessageEnabled(true)?;
        settings.SetAreDefaultContextMenusEnabled(false)?;
        settings.SetAreHostObjectsAllowed(false)?;
        settings.cast::<ICoreWebView2Settings3>()?.SetAreBrowserAcceleratorKeysEnabled(false)?;
        let mut token = 0;
        webview.add_PermissionRequested(
            &PermissionRequestedEventHandler::create(Box::new(|_, args| {
                if let Some(args) = args {
                    args.SetState(COREWEBVIEW2_PERMISSION_STATE_DENY)?;
                }
                Ok(())
            })),
            &mut token,
        )?;
        webview.cast::<ICoreWebView2_4>()?.add_DownloadStarting(
            &DownloadStartingEventHandler::create(Box::new(|_, args| {
                if let Some(args) = args {
                    args.SetCancel(true)?;
                }
                Ok(())
            })),
            &mut token,
        )?;
        let start = weak.clone();
        webview.add_NavigationStarting(
            &NavigationStartingEventHandler::create(Box::new(move |_, args| {
                if let (Some(preview), Some(args)) = (start.upgrade(), args) {
                    let mut raw = windows::core::PWSTR::null();
                    args.Uri(&mut raw)?;
                    let uri = webview2_com::CoTaskMemPWSTR::from(raw).to_string();
                    let mut state = preview.borrow_mut();
                    let allowed = pdf_bridge::viewer_navigation(&uri, &state.prefix);
                    if !allowed {
                        args.SetCancel(true)?;
                    } else if uri == format!("{}viewer.html", state.prefix) {
                        let mut id = 0;
                        args.NavigationId(&mut id)?;
                        state.navigation_id = Some(id);
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
        let complete = weak.clone();
        webview.add_NavigationCompleted(
            &NavigationCompletedEventHandler::create(Box::new(move |_, args| {
                if let (Some(preview), Some(args)) = (complete.upgrade(), args) {
                    let mut id = 0;
                    args.NavigationId(&mut id)?;
                    let mut success = BOOL::default();
                    args.IsSuccess(&mut success)?;
                    let mut state = preview.borrow_mut();
                    if state.navigation_id == Some(id) && !success.as_bool() {
                        state.fail("WebView2 could not load the offline PDF viewer");
                    }
                }
                Ok(())
            })),
            &mut token,
        )?;
        // No folder mapping: every request, including workers, must resolve to
        // one bundled resource or this view's already-authorized PDF file.
        webview.cast::<ICoreWebView2_22>()?.AddWebResourceRequestedFilterWithRequestSourceKinds(
            w!("*"),
            COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL,
            COREWEBVIEW2_WEB_RESOURCE_REQUEST_SOURCE_KINDS_ALL,
        )?;
        let request = weak.clone();
        webview.add_WebResourceRequested(&WebResourceRequestedEventHandler::create(Box::new(move |_,args| {
            let (Some(preview),Some(args))=(request.upgrade(),args) else { return Ok(()); };
            let request=args.Request()?;
            let mut raw=windows::core::PWSTR::null(); request.Uri(&mut raw)?;
            let uri=webview2_com::CoTaskMemPWSTR::from(raw).to_string();
            let mut raw=windows::core::PWSTR::null(); request.Method(&mut raw)?;
            let method=webview2_com::CoTaskMemPWSTR::from(raw).to_string();
            let state=preview.borrow();
            let key=pdf_bridge::resource_key(&uri,&state.prefix);
            let response=(|| -> windows::core::Result<(Option<IStream>,i32,&str,String)> {
                if method=="GET" && let Some(key)=key {
                    if key=="document.pdf" {
                        let size=std::fs::metadata(&state.file).map_err(|e|windows::core::Error::new(windows::Win32::Foundation::E_FAIL,e.to_string()))?.len();
                        if size<=256*1024*1024 {
                            let file=HSTRING::from(state.file.as_os_str());
                            let stream=SHCreateStreamOnFileEx(&file,STGM_READ.0|STGM_SHARE_DENY_NONE.0,0,false,None::<&IStream>)?;
                            return Ok((Some(stream),200,"OK",format!("Content-Type: application/pdf\r\nContent-Length: {size}\r\n")));
                        }
                    } else if let Some((bytes,mime))=pdf_resources::resource(key) {
                        let stream=SHCreateMemStream(Some(bytes)).ok_or_else(||windows::core::Error::from_hresult(E_OUTOFMEMORY))?;
                        return Ok((Some(stream),200,"OK",format!("Content-Type: {mime}\r\nContent-Length: {}\r\n",bytes.len())));
                    }
                }
                Ok((None,403,"Forbidden",String::new()))
            })();
            drop(state);
            let (stream,code,reason,mut headers)=response.unwrap_or((None,404,"Not Found",String::new()));
            headers.push_str(&format!("Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: {CSP}\r\n"));
            let response=environment.CreateWebResourceResponse(stream.as_ref(),code,&HSTRING::from(reason),&HSTRING::from(headers))?;
            args.SetResponse(&response)?;
            Ok(())
        })),&mut token)?;
        let message = weak.clone();
        webview.add_WebMessageReceived(
            &WebMessageReceivedEventHandler::create(Box::new(move |_, args| {
                if let (Some(preview), Some(args)) = (message.upgrade(), args) {
                    let mut raw = windows::core::PWSTR::null();
                    args.Source(&mut raw)?;
                    let source = webview2_com::CoTaskMemPWSTR::from(raw).to_string();
                    if !pdf_bridge::viewer_navigation(&source, &preview.borrow().prefix) {
                        return Ok(());
                    }
                    let mut raw = windows::core::PWSTR::null();
                    args.WebMessageAsJson(&mut raw)?;
                    let json = webview2_com::CoTaskMemPWSTR::from(raw).to_string();
                    if let Err(error) = Preview::message(&preview, &json) {
                        preview.borrow_mut().fail(error);
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
        if let Some([_, _, w, h]) = preview.borrow().layout.as_ref().map(|(bounds, _)| *bounds) {
            controller.SetBounds(RECT { left: 0, top: 0, right: w, bottom: h })?;
            controller.SetIsVisible(w > 0 && h > 0)?;
        }
        let url = {
            let mut state = preview.borrow_mut();
            state.controller = Some(controller);
            state.webview = Some(webview.clone());
            state.layout = None;
            HSTRING::from(format!("{}viewer.html", state.prefix))
        };
        webview.Navigate(&url)?;
    }
    Ok(())
}
