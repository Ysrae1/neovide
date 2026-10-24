// Standalone, headless Chromium integration test. Requires Playwright; does
// not attach to or modify any user browser, Windows GUI, or installed app.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
const { chromium } = createRequire(import.meta.url)("playwright");
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const root = path.join(repo, "src/native_preview/pdf_viewer");
const output = process.env.GLOW_PDF_TEST_OUTPUT || path.join(repo, "target/glow-windows-embedded-synctex-20261023/viewer");
await mkdir(output, { recursive: true });

function fixture() {
  const objects = [];
  const add = text => { objects.push(text); return objects.length; };
  const catalog = add("");
  const pages = add("");
  const font = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
  const action = add("<< /S /JavaScript /JS (globalThis.__pdfScriptRan=true;) >>");
  const kids = [];
  for (let i = 0; i < 24; i++) {
    const text = `BT /F1 18 Tf 60 730 Td (Glow SyncTeX page ${i + 1}) Tj ET\n0.2 0.5 0.8 RG 120 600 60 20 re S\n`;
    const content = add(`<< /Length ${Buffer.byteLength(text)} >>\nstream\n${text}endstream`);
    const annotation = add("<< /Type /Annot /Subtype /Link /Rect [60 680 240 710] /A << /S /URI /URI (https://example.invalid/blocked) >> >>");
    const rotation = [0, 90, 180, 270][i % 4];
    kids.push(add(`<< /Type /Page /Parent ${pages} 0 R /MediaBox [0 0 600 800] /Rotate ${rotation} /Resources << /Font << /F1 ${font} 0 R >> >> /Contents ${content} 0 R /Annots [${annotation} 0 R] >>`));
  }
  objects[catalog - 1] = `<< /Type /Catalog /Pages ${pages} 0 R /OpenAction ${action} 0 R >>`;
  objects[pages - 1] = `<< /Type /Pages /Count 24 /Kids [${kids.map(id => `${id} 0 R`).join(" ")}] >>`;
  let pdf = "%PDF-1.7\n";
  const offsets = [0];
  objects.forEach((text, i) => { offsets.push(Buffer.byteLength(pdf)); pdf += `${i + 1} 0 obj\n${text}\nendobj\n`; });
  const xref = Buffer.byteLength(pdf);
  pdf += `xref\n0 ${offsets.length}\n0000000000 65535 f \n${offsets.slice(1).map(n => `${String(n).padStart(10, "0")} 00000 n \n`).join("")}trailer\n<< /Root 1 0 R /Size ${offsets.length} >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf);
}
const pdf = fixture();
await writeFile(path.join(output, "fixture.pdf"), pdf);
const manifest = JSON.parse(await readFile(path.join(root, "vendor/pdfjs/manifest.json"), "utf8"));
const allow = new Set(["viewer.html", "viewer.css", "viewer.mjs", "protocol.mjs", ...manifest.files.map(f => `vendor/pdfjs/${f.path}`)]);
const requests = [];
let pdfRequests = 0;
const server = createServer(async (request, response) => {
  const url = new URL(request.url, "http://127.0.0.1");
  const name = url.pathname.replace(/^\/0123456789abcdef0123456789abcdef\//, "");
  requests.push(url.pathname);
  if (request.method !== "GET" || (!allow.has(name) && name !== "document.pdf")) { response.writeHead(404).end(); return; }
  const types = { ".html": "text/html", ".css": "text/css", ".mjs": "text/javascript", ".wasm": "application/wasm", ".ttf": "font/ttf", ".otf": "font/otf" };
  const data = name === "document.pdf" ? (pdfRequests++, pdf) : await readFile(path.join(root, name));
  response.writeHead(200, { "Content-Type": name === "document.pdf" ? "application/pdf" : types[path.extname(name)] || "application/octet-stream", "Cache-Control": "no-store" });
  response.end(data);
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
const browser = await chromium.launch({ headless: true, executablePath: process.env.GLOW_TEST_CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" });
const context = await browser.newContext({ viewport: { width: 1000, height: 820 }, deviceScaleFactor: 2 });
const page = await context.newPage();
page.setDefaultTimeout(8000);
const errors = [];
const consoleMessages = [];
const network = [];
page.on("pageerror", error => errors.push(String(error)));
page.on("console", message => consoleMessages.push(`${message.type()}: ${message.text()}`));
page.on("request", request => network.push(request.url()));
await page.addInitScript(() => {
  globalThis.__messages = [];
  globalThis.chrome ??= {};
  globalThis.chrome.webview = { postMessage(message) { globalThis.__messages.push(message); } };
});
const results = [];
const command = value => page.evaluate(value => window.glowPdf.command(value), value);
try {
  await page.goto(`http://127.0.0.1:${port}/0123456789abcdef0123456789abcdef/viewer.html`);
  await page.waitForFunction(() => __messages.some(m => m.type === "ready" && m.page_count === 24), null, { timeout: 15000 });
  await page.waitForSelector(".textLayer span");
  assert.match(await page.locator(".textLayer").first().textContent(), /Glow SyncTeX page 1/);
  assert.equal(await page.evaluate(() => globalThis.__pdfScriptRan), undefined);
  await page.waitForSelector(".annotationLayer a");
  assert.equal(await page.locator(".annotationLayer a").first().getAttribute("href"), "");
  assert.ok((await page.locator("canvas").count()) < 10);
  results.push("Real PDF rendering, selectable text, PDF scripting disabled, initial lazy canvas count");

  const mappings = [];
  for (let i = 1; i <= 4; i++) {
    await command({ action: "page", page: i });
    await command({ action: "fit", value: "page-fit" });
    const element = page.locator(`.page[data-page-number="${i}"]`);
    await element.locator("canvas").waitFor();
    await page.waitForTimeout(80);
    const fractions = [[0.2, 0.25], [0.75, 0.2], [0.8, 0.75], [0.25, 0.8]][i - 1];
    const click = await element.evaluate((element, fractions) => {
      const rect = element.getBoundingClientRect();
      return { x: rect.left + rect.width * fractions[0], y: rect.top + rect.height * fractions[1] };
    }, fractions);
    // macOS turns a native Control+click into a context-menu gesture. Dispatch
    // the Windows DOM event directly so this test exercises its actual path.
    await page.evaluate(({ x, y }) => document.elementFromPoint(x, y).dispatchEvent(new MouseEvent("click", {
      bubbles: true, cancelable: true, view: window, button: 0, ctrlKey: true, clientX: x, clientY: y,
    })), click);
    await page.waitForFunction(pageNumber => __messages.some(m => m.type === "inverse" && m.page === pageNumber), i);
    const message = await page.evaluate(pageNumber => __messages.filter(m => m.type === "inverse" && m.page === pageNumber).at(-1), i);
    assert.ok(Math.abs(message.x - 120) < 1, `rotation ${(i - 1) * 90} x ${message.x}`);
    assert.ok(Math.abs(message.y - 200) < 1, `rotation ${(i - 1) * 90} y ${message.y}`);
    mappings.push({ rotation: (i - 1) * 90, x: message.x, y: message.y });
  }
  results.push("Ctrl+click PDF-point coordinates at 0/90/180/270 degree rotation, DPR 2 and scroll");

  await command({ action: "page", page: 1 });
  await command({ action: "zoom", value: 1.25 });
  const beforeSync = pdfRequests;
  assert.equal(await command({ action: "pdf_sync", page: 2, x: 120, y: 200, width: 60, height: 20 }), true);
  await page.waitForSelector(".page[data-page-number='2'] .glow-sync-marker");
  assert.equal(pdfRequests, beforeSync);
  const marker = await page.locator(".glow-sync-marker").evaluate(el => ({ left: parseFloat(el.style.left), top: parseFloat(el.style.top), width: parseFloat(el.style.width), height: parseFloat(el.style.height) }));
  // 90-degree page: point (120,600), scale 1.25 * 96/72.
  assert.ok(Math.abs(marker.left - 600 * 1.25 * 4 / 3) < 1);
  assert.ok(Math.abs(marker.top - 120 * 1.25 * 4 / 3) < 1);
  assert.ok(Math.abs(marker.width - 20 * 1.25 * 4 / 3) < 1);
  assert.ok(Math.abs(marker.height - 60 * 1.25 * 4 / 3) < 1);
  results.push("Forward SyncTeX transformed rectangle after zoom/rotation without a PDF reload");
  await page.screenshot({ path: path.join(output, "forward-rotated.png") });
  const markerCenter = await page.locator(".glow-sync-marker").evaluate(el => {
    const rect = el.getBoundingClientRect();
    return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
  });
  const sequenceBeforeZoomClick = await page.evaluate(() => __messages.filter(m => m.type === "inverse").at(-1).seq);
  await page.evaluate(({ x, y }) => document.elementFromPoint(x, y).dispatchEvent(new MouseEvent("click", {
    bubbles: true, cancelable: true, view: window, button: 0, metaKey: true, clientX: x, clientY: y,
  })), markerCenter);
  await page.waitForFunction(seq => __messages.some(m => m.type === "inverse" && m.seq > seq), sequenceBeforeZoomClick);
  const zoomInverse = await page.evaluate(() => __messages.filter(m => m.type === "inverse").at(-1));
  assert.ok(Math.abs(zoomInverse.x - 150) < 1 && Math.abs(zoomInverse.y - 190) < 1, JSON.stringify(zoomInverse));
  mappings.push({ rotation: 90, zoom: 1.25, metaKey: true, x: zoomInverse.x, y: zoomInverse.y });
  results.push("Meta+click inverse mapping at 125% after rotated forward positioning and scrolling");

  await command({ action: "fit" });
  for (let i = 5; i <= 24; i++) {
    await command({ action: "page", page: i });
    await page.locator(`.page[data-page-number="${i}"] canvas`).waitFor();
  }
  const canvasCount = await page.locator("canvas").count();
  assert.ok(canvasCount <= 12, `Canvas cache grew to ${canvasCount}`);
  results.push(`Lazy page canvas release after visiting 24 pages (${canvasCount} live canvases)`);

  const readyBefore = await page.evaluate(() => __messages.filter(m => m.type === "ready").length);
  await command({ action: "pdf_sync", page: 1, x: 50, y: 60, revision: 0 });
  await command({ action: "reload", revision: 1 });
  await page.waitForFunction(n => __messages.filter(m => m.type === "ready").length > n, readyBefore);
  assert.equal(await command({ action: "page", page: 4, revision: 0 }), false);
  assert.equal(await page.locator(".glow-sync-marker").count(), 0);
  assert.equal(await command({ action: "zoom", value: NaN }), false);
  assert.equal(await command({ action: "page", page: 25 }), false);
  assert.ok(network.every(url => url.startsWith(`http://127.0.0.1:${port}/`)), "Outbound request occurred");
  assert.deepEqual(errors, []);
  results.push("Reload invalidates older sync/marker and revision; invalid commands and outbound navigation rejected");

  // A plain q must reach the host as an owner-scoped request even when a
  // forward search leaves Neovim's selected window on the source buffer.
  // The native adapter owns Escape's existing return-to-editor behavior.
  const closeCount = () => page.evaluate(() => __messages.filter(m => m.type === "close_requested").length);
  await page.locator("#viewerContainer").focus();
  await page.keyboard.press("q");
  assert.equal(await closeCount(), 1);
  assert.deepEqual(await page.evaluate(() => __messages.filter(m => m.type === "close_requested").at(-1)),
    { version: 1, type: "close_requested", revision: 1 });
  await page.keyboard.press("Escape");
  assert.equal(await closeCount(), 1);
  await page.evaluate(() => document.activeElement.blur());
  await page.keyboard.press("q");
  assert.equal(await closeCount(), 2, "Initial WebView document focus must also close the preview");

  const ignored = await page.evaluate(() => {
    const variants = [
      { ctrlKey: true }, { altKey: true }, { metaKey: true }, { shiftKey: true },
      { isComposing: true }, { keyCode: 229 }, { repeat: true }, { key: "Q" },
    ];
    return variants.map(options => {
      const event = new KeyboardEvent("keydown", { key: "q", bubbles: true, cancelable: true, ...options });
      document.getElementById("viewerContainer").dispatchEvent(event);
      return event.defaultPrevented;
    });
  });
  assert.ok(ignored.every(prevented => !prevented));
  assert.equal(await closeCount(), 2);
  await page.evaluate(() => {
    const target = document.getElementById("viewerContainer");
    target.addEventListener("keydown", event => event.preventDefault(), { once: true });
    target.dispatchEvent(new KeyboardEvent("keydown", { key: "q", bubbles: true, cancelable: true }));
  });
  assert.equal(await closeCount(), 2, "Already handled keys belong to the child control");

  for (const kind of ["input", "textarea", "select", "editable", "textbox"]) {
    await page.evaluate(kind => {
      const element = document.createElement(["editable", "textbox"].includes(kind) ? "div" : kind);
      element.id = "keyboard-fixture";
      if (kind === "editable") { element.contentEditable = "true"; element.innerHTML = "<span id='keyboard-fixture-child'>edit</span>"; }
      if (kind === "textbox") { element.setAttribute("role", "textbox"); element.tabIndex = 0; }
      if (kind === "select") element.innerHTML = "<option>example</option>";
      document.getElementById("viewerContainer").append(element);
      element.focus();
    }, kind);
    await page.keyboard.press("q");
    assert.equal(await closeCount(), 2, `${kind} must retain q`);
    if (["input", "textarea"].includes(kind)) assert.equal(await page.locator("#keyboard-fixture").inputValue(), "q");
    if (kind === "editable") {
      assert.match(await page.locator("#keyboard-fixture").textContent(), /q/);
      assert.equal(await page.locator("#keyboard-fixture-child").evaluate(element => {
        const event = new KeyboardEvent("keydown", { key: "q", bubbles: true, cancelable: true });
        element.dispatchEvent(event);
        return event.defaultPrevented;
      }), false);
    }
    await page.locator("#keyboard-fixture").evaluate(element => element.remove());
  }
  assert.equal(await closeCount(), 2);
  results.push("q emits a revision-scoped close request from PDF/document focus; Escape, modifiers, IME, repeats and editable controls are preserved");

  await command({ action: "close", revision: 1 });
  const messagesAfterClose = await page.evaluate(() => __messages.length);
  await page.keyboard.press("q");
  await page.waitForTimeout(100);
  assert.equal(await page.evaluate(() => __messages.length), messagesAfterClose);
  assert.equal(await command({ action: "next" }), false);
  results.push("Close cancels work and suppresses further messages");
  const report = { passed: results, mappings, canvasCount, pdfRequests, requests, network, errors, consoleMessages };
  await writeFile(path.join(output, "browser-results.json"), JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify({ passed: results, mappings, canvasCount, pdfRequests }, null, 2));
} catch (error) {
  await page.screenshot({ path: path.join(output, "failure.png") }).catch(() => {});
  await writeFile(path.join(output, "browser-failure.json"), JSON.stringify({ error: String(error), errors, consoleMessages, messages: await page.evaluate(() => globalThis.__messages).catch(() => []), requests }, null, 2));
  throw error;
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
