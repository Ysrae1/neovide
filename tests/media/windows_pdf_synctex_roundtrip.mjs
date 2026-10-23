// Real XeLaTeX -> SyncTeX CLI -> PDF.js DOM -> SyncTeX CLI regression.
// Runs an isolated headless browser, never the user's Windows GUI.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { spawnSync } from "node:child_process";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
const { chromium } = createRequire(import.meta.url)("playwright");
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const root = path.join(repo, "src/native_preview/pdf_viewer");
const output = process.env.GLOW_PDF_TEST_OUTPUT || path.join(repo, "target/glow-windows-embedded-synctex-20261023/viewer");
const work = path.join(output, "tex-roundtrip");
const build = path.join(work, "build output");
await mkdir(build, { recursive: true });
const sourceName = "chapter source's 中文.tex";
const mainName = "main document's.tex";
const source = path.join(work, sourceName);
const pdfPath = path.join(build, "main document's.pdf");
const xelatex = process.env.GLOW_TEST_XELATEX || "/Library/TeX/texbin/xelatex";
const synctex = process.env.GLOW_TEST_SYNCTEX || "/Library/TeX/texbin/synctex";
const env = { ...process.env, SYNCTEX_VIEWER: "", SYNCTEX_EDITOR: "" };
function run(executable, args) {
  const result = spawnSync(executable, args, { cwd: work, env, encoding: "utf8", timeout: 30000 });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${executable}: ${result.stdout}\n${result.stderr}`);
  return result.stdout;
}
function record(text) {
  const body = text.split("SyncTeX result begin")[1]?.split("SyncTeX result end")[0];
  assert.ok(body, text);
  const result = {};
  for (const line of body.trim().split(/\r?\n/)) {
    const colon = line.indexOf(":");
    if (colon > 0 && !(line.slice(0, colon) in result)) result[line.slice(0, colon)] = line.slice(colon + 1);
  }
  return result;
}
await writeFile(source, "First paragraph.\n\nThe exact synchronization target is this sentence.\n\nLast paragraph.\n");
await writeFile(path.join(work, mainName), `\\documentclass{article}\n\\begin{document}\n\\input{${sourceName}}\n\\newpage\nSecond page.\n\\end{document}\n`);
await writeFile(path.join(work, "compile.stdout"), run(xelatex, ["-interaction=nonstopmode", "-halt-on-error", "-synctex=1", `-output-directory=${build}`, mainName]));
const forwardOutput = run(synctex, ["view", "-i", `3:8:${source}`, "-o", pdfPath]);
await writeFile(path.join(work, "forward.stdout"), forwardOutput);
const forward = record(forwardOutput);
const point = { action: "pdf_sync", page: Number(forward.Page), x: Number(forward.h), y: Number(forward.v), width: Number(forward.W), height: Number(forward.H) };
const pdf = await readFile(pdfPath);
const manifest = JSON.parse(await readFile(path.join(root, "vendor/pdfjs/manifest.json"), "utf8"));
const allow = new Set(["viewer.html", "viewer.css", "viewer.mjs", "protocol.mjs", ...manifest.files.map(f => `vendor/pdfjs/${f.path}`)]);
let documentRequests = 0;
const server = createServer(async (request, response) => {
  const name = new URL(request.url, "http://127.0.0.1").pathname.replace(/^\/fixture\//, "");
  if (request.method !== "GET" || (!allow.has(name) && name !== "document.pdf")) { response.writeHead(404).end(); return; }
  const types = { ".html": "text/html", ".css": "text/css", ".mjs": "text/javascript", ".wasm": "application/wasm" };
  const data = name === "document.pdf" ? (documentRequests++, pdf) : await readFile(path.join(root, name));
  response.writeHead(200, { "Content-Type": name === "document.pdf" ? "application/pdf" : types[path.extname(name)] || "application/octet-stream", "Cache-Control": "no-store" });
  response.end(data);
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const browser = await chromium.launch({ headless: true, executablePath: process.env.GLOW_TEST_CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" });
const page = await browser.newPage({ viewport: { width: 1000, height: 820 }, deviceScaleFactor: 2 });
page.setDefaultTimeout(10000);
const errors = [];
page.on("pageerror", error => errors.push(String(error)));
await page.addInitScript(() => {
  globalThis.__messages = [];
  globalThis.chrome ??= {};
  chrome.webview = { postMessage(message) { __messages.push(message); } };
});
const results = [];
try {
  await page.goto(`http://127.0.0.1:${server.address().port}/fixture/viewer.html`);
  await page.waitForFunction(() => __messages.some(m => m.type === "ready"));
  for (const zoom of [1.35, 0.5]) {
    await page.evaluate(zoom => glowPdf.command({ action: "zoom", value: zoom }), zoom);
    await page.evaluate(point => glowPdf.command(point), point);
    await page.waitForSelector(".glow-sync-marker");
    const geometry = await page.locator(".glow-sync-marker").evaluate(marker => {
      const rect = marker.getBoundingClientRect();
      const container = document.getElementById("viewerContainer").getBoundingClientRect();
      return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2,
        top: rect.top, bottom: rect.bottom, height: rect.height,
        containerTop: container.top, containerBottom: container.bottom };
    });
    assert.ok(geometry.top >= geometry.containerTop + 24 && geometry.bottom <= geometry.containerBottom - 24, JSON.stringify(geometry));
    const sequence = await page.evaluate(() => __messages.filter(m => m.type === "inverse").at(-1)?.seq || 0);
    await page.evaluate(({ x, y }) => document.elementFromPoint(x, y).dispatchEvent(new MouseEvent("click", {
      bubbles: true, cancelable: true, view: window, button: 0, ctrlKey: true, clientX: x, clientY: y,
    })), geometry);
    await page.waitForFunction(sequence => __messages.some(m => m.type === "inverse" && m.seq > sequence), sequence);
    const inverse = await page.evaluate(() => __messages.filter(m => m.type === "inverse").at(-1));
    const inverseOutput = run(synctex, ["edit", "-o", `${inverse.page}:${inverse.x}:${inverse.y}:${pdfPath}`]);
    await writeFile(path.join(work, `inverse-${zoom}.stdout`), inverseOutput);
    const match = record(inverseOutput);
    assert.equal(Number(match.Line), 3, inverseOutput);
    assert.ok(match.Input.endsWith(sourceName), inverseOutput);
    assert.ok(Math.abs(inverse.y - (point.y - point.height / 2)) < 1.5, JSON.stringify(inverse));
    if (zoom === 0.5) assert.equal(geometry.height, 12, "Minimum marker size must retain the real box center");
    assert.equal(documentRequests, 1);
    await page.screenshot({ path: path.join(work, `marker-${zoom}.png`) });
    results.push({ zoom, forward: point, marker: geometry, inverse, source: match.Input, line: Number(match.Line), documentRequests });
  }
  assert.deepEqual(errors, []);
  await writeFile(path.join(work, "results.json"), JSON.stringify({ passed: true, results, errors }, null, 2) + "\n");
  console.log(JSON.stringify({ passed: true, results }, null, 2));
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
