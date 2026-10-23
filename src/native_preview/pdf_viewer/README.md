# Embedded Windows PDF viewer

This local viewer uses the official Mozilla `pdfjs-dist` **6.4.299** release.
All rendering, character maps, standard fonts and decoders are bundled; there
is no CDN or package installation at runtime. `vendor/pdfjs/manifest.json`
records the npm archive integrity, SHA-256 and every shipped upstream file.
The upstream Apache-2.0 license and font/decoder license files are preserved.

Official references checked on 2026-10-23:

- https://github.com/mozilla/pdf.js/releases/tag/v6.4.299
- https://github.com/mozilla/pdf.js/wiki/Third-party-viewer-usage
- https://github.com/mozilla/pdf.js/security/advisories/GHSA-hq66-cqwq-w95j
- https://github.com/mozilla/pdf.js/security/advisories/GHSA-wgrm-67xf-hhpq

## Host boundary

`resources.rs::resource(path)` serves only an exact bundled resource name.
The native host maps these names under a per-view random token on
`https://glow-pdf.invalid/<token>/`. The sole PDF endpoint is `document.pdf`,
whose native mapping must reference only that view's previously authorized
PDF. Do not map arbitrary directories, decoded paths, URLs or filenames from
the document. Native code must also block outbound navigation, new windows,
downloads, permissions and all requests outside that view's exact allowlist.
No WebView host objects or native file APIs are exposed to the document.

The HTML has a CSP as defense in depth; the host also supplies the CSP as an
HTTP response header. JavaScript eval and PDF scripting are disabled. WASM
compilation is allowed for the bundled official PDF image decoders.
`PDFViewer` supplies text selection, copy, page layout, lazy rendering and a
bounded canvas cache. PDF forms are read-only and attachments have no download
manager. External links are disabled; internal document links may navigate.

## Protocol version 1

Native code calls `window.glowPdf.command(command)` with an object. Unsupported
or invalid commands return `false`; valid commands return `true` immediately.
Optional `version` must equal 1. Optional `revision` is a nonnegative safe
integer; values older than the current revision are rejected. The host begins
at revision 0, increments it for a PDF reload and rejects stale page messages.

| `action` | Fields | Behavior |
| --- | --- | --- |
| `pdf_sync` | `page`, `x`, `y`, optional `width`, `height`, `media_box` | Scroll without loading PDF bytes again; briefly mark the target. |
| `page` | `page` | Go to a 1-based page. |
| `next` / `previous` | | Go forward/back one page, clamped to the document. |
| `zoom` | `value` | Absolute zoom multiplier, 0.1–8; 1 means 100%. |
| `fit` | optional `value` | `page-fit` (default), `page-width` or `auto`. |
| `reload` | `revision` | Cancel previous rendering and load new bytes from the same authorized PDF endpoint. |
| `close` | | Cancel loading, rendering, pending positioning and all further messages. |

The page sends JSON objects through `chrome.webview.postMessage`:

- `{version:1,type:"ready",revision,page,page_count,zoom}` after `pagesinit`.
- `{version:1,type:"status",revision,page,page_count,zoom}` after page/zoom/scroll changes.
- `{version:1,type:"inverse",revision,page,x,y,seq}` for Ctrl+click or Meta+click.
- `{version:1,type:"error",revision,message}` for a document load failure.

`page` is 1-based; `zoom` is a multiplier. Inverse `x`, `y` are unrotated PDF
points from the top-left, independent of display scale, device pixel ratio,
scroll and page rotation. Forward `pdf_sync` uses SyncTeX CLI `h`, `v`, `W`,
`H`: `x` is the box's left edge, `y` is its bottom edge (baseline plus depth),
and `height` extends **upwards**, covering `y-height` through `y`. The viewer
centers this box in the available viewport when page edges permit, keeping
surrounding text visible. This convention follows the official
[`synctex_main.c`](https://github.com/jlaurens/synctex/blob/master/synctex_main.c)
CLI output; it is distinct from an arbitrary top-left rectangle.
PDF.js exposes the visible page box
(CropBox intersect MediaBox). For ordinary XeLaTeX output this is the MediaBox.
For deliberately cropped PDFs, the host must supply `media_box: [x0,y0,x1,y1]`
with a forward command for exact MediaBox coordinates; without it, inverse
coordinates are relative to the visible box. This is an explicit limitation,
not a guarantee of general cropped-PDF SyncTeX support.

All async loading/positioning checks document generation. Only the latest
pending command is retained while loading. Reload and close invalidate older
positioning. The native host remains responsible for rejecting messages after
a view is closed and for generating its own monotonic inverse-search sequence
when forwarding to Neovim.

## Verification

`tests/media/windows_pdf_viewer.mjs` is a standalone Playwright browser test
against a loopback, exact-allowlist fixture server; it does not control the
user's GUI. Set `NODE_PATH` to a Node package directory containing Playwright,
and optionally `GLOW_TEST_CHROME` to a Chromium executable. Its output defaults
to `target/glow-windows-embedded-synctex-20261023/viewer/`.

`node --test tests/media/windows_pdf_protocol.mjs` checks validation and the
coordinate conversions independently of a browser.

`tests/media/windows_pdf_synctex_roundtrip.mjs` compiles an isolated real
XeLaTeX fixture and checks that the marker-center DOM click returns its exact
included-source line through `synctex edit`, at 135% and 50% (the 12px minimum
marker size). It preserves raw forward/inverse CLI output and screenshots in
the test output's `tex-roundtrip/` directory. It needs XeLaTeX and SyncTeX;
their executables may be set with `GLOW_TEST_XELATEX` and `GLOW_TEST_SYNCTEX`.
