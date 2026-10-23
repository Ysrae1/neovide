import * as pdfjsLib from "./vendor/pdfjs/build/pdf.mjs";
import { PROTOCOL_VERSION, validCommand, synctexBoxToPdf, clientToSynctex } from "./protocol.mjs";

const { EventBus, PDFLinkService, PDFViewer } = await import("./vendor/pdfjs/web/pdf_viewer.mjs");
pdfjsLib.GlobalWorkerOptions.workerSrc = new URL("./vendor/pdfjs/build/pdf.worker.mjs", import.meta.url).href;

const container = document.getElementById("viewerContainer");
const errorElement = document.getElementById("error");
const eventBus = new EventBus();
const lifetime = new AbortController();
const linkService = new PDFLinkService({ eventBus });
linkService.externalLinkEnabled = false;
// Attachments/downloads deliberately have no download manager. PDF actions
// cannot invoke scripts, launch applications, or navigate the WebView.
const viewer = new PDFViewer({
  container, eventBus, linkService, abortSignal: lifetime.signal,
  scriptingManager: null, annotationEditorMode: pdfjsLib.AnnotationEditorType.DISABLE,
  annotationMode: pdfjsLib.AnnotationMode.ENABLE, enableAutoLinking: false,
  textLayerMode: 1, removePageBorders: true, maxCanvasPixels: 16777216,
  enableDetailCanvas: false,
});
linkService.setViewer(viewer);

let documentTask = null;
let generation = 0;
let revision = 0;
let commandSequence = 0;
let inverseSequence = 0;
let disposed = false;
let loaded = false;
let pendingCommand = null;
let commandChain = Promise.resolve();
let marker = null;
let markerTimer = null;
let statusFrame = null;
const pageBoxes = new Map();

function send(type, extra = {}) {
  if (disposed) return;
  // Send an object: WebView2 serializes this itself. No document text, URL,
  // attachment names, or executable data are sent across the native boundary.
  window.chrome?.webview?.postMessage({ version: PROTOCOL_VERSION, type, revision, ...extra });
}
function status() {
  if (!loaded || disposed || statusFrame !== null) return;
  statusFrame = requestAnimationFrame(() => {
    statusFrame = null;
    if (loaded && !disposed) send("status", {
      page: viewer.currentPageNumber, page_count: viewer.pagesCount,
      zoom: viewer.currentScale,
    });
  });
}
function clearMarker() {
  clearTimeout(markerTimer);
  markerTimer = null;
  marker?.remove();
  marker = null;
}
function showError(message) {
  errorElement.textContent = message;
  errorElement.hidden = false;
  send("error", { message });
}
function close() {
  if (disposed) return;
  disposed = true;
  loaded = false;
  generation++;
  commandSequence++;
  pendingCommand = null;
  clearMarker();
  cancelAnimationFrame(statusFrame);
  statusFrame = null;
  lifetime.abort();
  viewer.setDocument(null);
  linkService.setDocument(null);
  documentTask?.destroy().catch(() => {});
  documentTask = null;
}

async function openDocument() {
  const currentGeneration = ++generation;
  loaded = false;
  clearMarker();
  pageBoxes.clear();
  errorElement.hidden = true;
  const oldTask = documentTask;
  documentTask = null;
  viewer.setDocument(null);
  linkService.setDocument(null);
  await oldTask?.destroy().catch(() => {});
  if (disposed || generation !== currentGeneration) return;
  const url = new URL("./document.pdf", location.href);
  // The host returns Cache-Control: no-store. Keep this endpoint exact:
  // neither paths nor query strings can expand the native resource scope.
  const task = documentTask = pdfjsLib.getDocument({
    url: url.href,
    cMapUrl: new URL("./vendor/pdfjs/cmaps/", import.meta.url).href, cMapPacked: true,
    standardFontDataUrl: new URL("./vendor/pdfjs/standard_fonts/", import.meta.url).href,
    wasmUrl: new URL("./vendor/pdfjs/wasm/", import.meta.url).href,
    isEvalSupported: false, enableXfa: false,
    disableAutoFetch: true, disableStream: true,
    useWorkerFetch: true, stopAtErrors: true,
  });
  task.onPassword = () => {
    if (!disposed && generation === currentGeneration) showError("Password-protected PDFs are not supported in this preview.");
    task.destroy().catch(() => {});
  };
  try {
    const pdf = await task.promise;
    if (disposed || generation !== currentGeneration) { await task.destroy(); return; }
    linkService.setDocument(pdf);
    viewer.setDocument(pdf);
  } catch (error) {
    if (!disposed && generation === currentGeneration && error?.name !== "AbortException") {
      showError("Unable to load this PDF. Rebuild it and reopen the preview.");
    }
  }
}

async function sync(command, sequence) {
  const currentGeneration = generation;
  const pdf = viewer.pdfDocument;
  const page = await pdf.getPage(command.page);
  if (disposed || generation !== currentGeneration || sequence !== commandSequence || pdf !== viewer.pdfDocument) return;
  const pageView = viewer.getPageView(command.page - 1);
  if (!pageView.pdfPage) pageView.setPdfPage(page);
  if (command.media_box) pageBoxes.set(command.page, command.media_box.slice());
  const box = pageBoxes.get(command.page) || page.view;
  const [pdfX, pdfY, pdfRight, pdfTop] = synctexBoxToPdf(command.x, command.y, command.width ?? 0, command.height ?? 0, box);
  viewer.scrollPageIntoView({
    pageNumber: command.page,
    destArray: [null, { name: "XYZ" }, (pdfX + pdfRight) / 2, (pdfY + pdfTop) / 2, null],
    ignoreDestinationZoom: true, allowNegativeOffset: false, center: "both",
  });
  clearMarker();
  const viewport = pageView.viewport;
  const a = viewport.convertToViewportPoint(pdfX, pdfY);
  const b = viewport.convertToViewportPoint(pdfRight, pdfTop);
  marker = document.createElement("div");
  marker.className = "glow-sync-marker";
  marker.setAttribute("aria-hidden", "true");
  const width = Math.max(12, Math.abs(b[0] - a[0]));
  const height = Math.max(12, Math.abs(b[1] - a[1]));
  Object.assign(marker.style, {
    left: `${(a[0] + b[0] - width) / 2}px`,
    top: `${(a[1] + b[1] - height) / 2}px`,
    width: `${width}px`, height: `${height}px`,
  });
  pageView.div.append(marker);
  markerTimer = setTimeout(clearMarker, 1600);
  status();
}

async function navigate(pageNumber, currentGeneration) {
  const pdf = viewer.pdfDocument;
  const page = await pdf.getPage(pageNumber);
  if (disposed || generation !== currentGeneration || pdf !== viewer.pdfDocument) return;
  const pageView = viewer.getPageView(pageNumber - 1);
  if (!pageView.pdfPage) pageView.setPdfPage(page);
  viewer.currentPageNumber = pageNumber;
  // Refresh PDFViewer's scroll location before a queued fit/zoom command.
  // Otherwise its previous page location can pull a quick page+fit back.
  viewer.update();
}

function command(value) {
  if (disposed || !validCommand(value)) return false;
  if (value.revision !== undefined && value.revision < revision) return false;
  if (value.revision !== undefined) revision = value.revision;
  const sequence = ++commandSequence;
  if (value.action === "close") { close(); return true; }
  if (value.action === "reload") { pendingCommand = null; commandChain = Promise.resolve(); void openDocument(); return true; }
  if (!loaded) { pendingCommand = { ...value }; return true; }
  if (value.page && value.page > viewer.pagesCount) return false;
  const currentGeneration = generation;
  const currentRevision = revision;
  commandChain = commandChain.then(async () => {
    if (disposed || generation !== currentGeneration || revision !== currentRevision) return;
    clearMarker();
    switch (value.action) {
      case "pdf_sync": await sync(value, sequence); break;
      case "page": await navigate(value.page, currentGeneration); break;
      case "next": await navigate(Math.min(viewer.pagesCount, viewer.currentPageNumber + 1), currentGeneration); break;
      case "previous": await navigate(Math.max(1, viewer.currentPageNumber - 1), currentGeneration); break;
      case "zoom": viewer.currentScaleValue = value.value; break;
      case "fit": viewer.currentScaleValue = value.value || "page-fit"; break;
    }
    status();
  }).catch(() => {});
  return true;
}

Object.defineProperty(window, "glowPdf", { value: Object.freeze({ command }), writable: false, configurable: false });

eventBus.on("pagesinit", () => {
  if (disposed || !viewer.pdfDocument) return;
  viewer.currentScaleValue = "page-width";
  loaded = true;
  send("ready", { page: viewer.currentPageNumber, page_count: viewer.pagesCount, zoom: viewer.currentScale });
  const queued = pendingCommand;
  pendingCommand = null;
  if (queued) command(queued);
  status();
});
for (const name of ["pagechanging", "scalechanging", "updateviewarea"]) eventBus.on(name, status);

container.addEventListener("click", async event => {
  if (!(event.ctrlKey || event.metaKey) || event.button !== 0 || !loaded || disposed) return;
  const pageElement = event.target.closest?.(".page[data-page-number]");
  if (!pageElement) return;
  event.preventDefault();
  event.stopPropagation();
  const currentGeneration = generation;
  const currentRevision = revision;
  const currentCommand = commandSequence;
  const seq = ++inverseSequence;
  const pageNumber = Number(pageElement.dataset.pageNumber);
  const pageView = viewer.getPageView(pageNumber - 1);
  const pdf = viewer.pdfDocument;
  const page = await pdf.getPage(pageNumber).catch(() => null);
  if (!page || disposed || generation !== currentGeneration || currentRevision !== revision || currentCommand !== commandSequence || seq !== inverseSequence || pdf !== viewer.pdfDocument) return;
  const rect = pageElement.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return;
  const [x, y] = clientToSynctex(event.clientX, event.clientY, rect, pageView.viewport, pageBoxes.get(pageNumber) || page.view);
  if (Number.isFinite(x) && Number.isFinite(y)) send("inverse", { page: pageNumber, x, y, seq });
}, { capture: true, signal: lifetime.signal });

// Keep ordinary text selection/copy and browser scrolling. Ctrl+click is the
// sole click gesture owned by SyncTeX. Block PDF-created outbound links.
container.addEventListener("click", event => {
  const anchor = event.target.closest?.("a[href]");
  if (anchor && anchor.getAttribute("href") && !anchor.getAttribute("href").startsWith("#")) event.preventDefault();
}, { capture: true, signal: lifetime.signal });
container.addEventListener("keydown", event => {
  if (event.ctrlKey || event.metaKey || event.altKey || event.shiftKey) return;
  if (event.key === "PageDown") { event.preventDefault(); command({ action: "next" }); }
  if (event.key === "PageUp") { event.preventDefault(); command({ action: "previous" }); }
  if (event.key === "Home") { event.preventDefault(); command({ action: "page", page: 1 }); }
  if (event.key === "End" && loaded) { event.preventDefault(); command({ action: "page", page: viewer.pagesCount }); }
}, { signal: lifetime.signal });
window.addEventListener("pagehide", close, { once: true });
void openDocument();
