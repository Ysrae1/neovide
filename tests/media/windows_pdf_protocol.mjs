import test from "node:test";
import assert from "node:assert/strict";
import { validCommand, synctexToPdf, synctexBoxToPdf, pdfToSynctex, clientToSynctex } from "../../src/native_preview/pdf_viewer/protocol.mjs";

test("commands reject invalid versions, paths, coordinates and scale", () => {
  for (const value of [null, [], {}, { action: "open", url: "file:///secret" }, { action: "page", page: 0 },
    { action: "page", page: 1.1 }, { action: "zoom", value: Infinity }, { action: "zoom", value: 9 },
    { action: "reload", revision: -1 }, { action: "reload", revision: Number.MAX_SAFE_INTEGER + 1 },
    { action: "next", version: 2 }, { action: "pdf_sync", page: 1, x: NaN, y: 0 },
    { action: "pdf_sync", page: 1, x: 1, y: 2, width: -1 },
    { action: "pdf_sync", page: 1, x: 1, y: 2, media_box: [0, 0, 0, 500] }]) {
    assert.equal(validCommand(value), false, JSON.stringify(value));
  }
  assert.equal(validCommand({ action: "pdf_sync", version: 1, revision: 0, page: 2, x: 10, y: 20 }), true);
  assert.equal(validCommand({ action: "fit", value: "page-width" }), true);
});

test("PDF point mapping preserves media origin and top-left convention", () => {
  const box = [-20, 10, 580, 810];
  assert.deepEqual(synctexToPdf(125, 240, box), [105, 570]);
  assert.deepEqual(pdfToSynctex(105, 570, box), [125, 240]);
});

test("SyncTeX CLI box height extends above its bottom edge", () => {
  assert.deepEqual(synctexBoxToPdf(120, 200, 60, 20, [0, 0, 600, 800]), [120, 600, 180, 620]);
});

test("DOM click mapping accounts for CSS zoom without device pixel ratio", () => {
  const viewport = { width: 1200, height: 1600, convertToPdfPoint(x, y) { return [x / 2 - 20, 810 - y / 2]; } };
  assert.deepEqual(clientToSynctex(110, 140, { left: 10, top: 20, width: 600, height: 800 }, viewport, [-20, 10, 580, 810]), [100, 120]);
});
