# Windows embedded PDF

The Windows native preview backend is a WebView2 child HWND using the installed
Evergreen WebView2 Runtime. It does not require an MSIX identity. The loader is
statically linked by `webview2-com-sys` on MSVC; do not bundle a private Chromium
runtime or point production builds at an Edge browser installation.

The UI thread owns COM initialization, the parent/child HWNDs and all WebView2
callbacks. Environment and controller creation are asynchronous on Winit's
existing message loop. Closing a route releases its controller and child HWND;
late initialization callbacks use weak references. Grid geometry is converted to
physical pixels, and editor floating regions are subtracted from the child HWND
region so notifications and menus remain accessible.

## Protocol

- `neovide_native_preview_kinds`: Windows `{"pdf"}` array; macOS retains all four
  kinds. `neovide_native_pdf_synctex`: Windows false, macOS true.
- Windows accepts local absolute paths / file URIs only. Drive, UNC, spaces and
  Unicode are encoded through the URL library. Navigation to another document or
  external URL and new windows are blocked.
- Page/zoom/fit actions request PDF open parameters. Returned `page_state` is
  `requested`; no page count, exact live viewer position or coordinate SyncTeX is
  claimed. Use the external PDF viewer for coordinate forward/inverse search.
- `i` focuses the child viewer; Escape returns focus to the editor. In-view PDF
  controls and mouse interactions are supplied by the installed WebView2 Runtime.

## Build and validation

Use the existing Windows MSVC build environment and renderer-cache recipe, with
new Cargo.toml / Cargo.lock plus `src/native_preview/windows.rs`, `mod.rs`,
`src/bridge/setup.rs`, and `src/window/window_wrapper.rs`. No C++ SDK setup is
needed beyond the existing MSVC/Windows SDK. Standard build command:

```powershell
cargo build --release --locked --target x86_64-pc-windows-msvc
```

Preserve the existing machine's Skia prebuilt/no-compile environment; this command
is not a request to change that environment. Install/reuse the system WebView2
Runtime through the dependency layer if absent.

The backend was checked against ARM64 Windows Rust bindings in an isolated
Skia-free harness on macOS (2026-10-21). This checks the actual module's API types,
not full product linking or runtime behavior. Required real Windows validation:
open a private two-page PDF from drive and Unicode UNC paths; resize/switch tabs;
open an overlapping editor float; focus/Escape; page/zoom/fit; close during async
creation; close/reopen and verify browser child processes are released. Test the
runtime-missing path separately in an isolated environment.

References: [local PDF loading](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/working-with-local-content),
[threading and callbacks](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/threading-model),
[shared Runtime distribution](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution).
