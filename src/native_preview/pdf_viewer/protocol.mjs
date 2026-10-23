// SyncTeX coordinates are unrotated PDF points from the page's top-left.
export const PROTOCOL_VERSION = 1;
const actions = new Set(["pdf_sync", "page", "next", "previous", "zoom", "fit", "reload", "close"]);
const finite = value => typeof value === "number" && Number.isFinite(value);
const point = value => finite(value) && Math.abs(value) <= 1e7;
export function mediaBox(value) {
  return Array.isArray(value) && value.length === 4 && value.every(point) && value[2] > value[0] && value[3] > value[1];
}
export function validCommand(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) || !actions.has(value.action)) return false;
  if (value.version !== undefined && value.version !== PROTOCOL_VERSION) return false;
  if (value.revision !== undefined && (!Number.isSafeInteger(value.revision) || value.revision < 0)) return false;
  if (["pdf_sync", "page"].includes(value.action) && (!Number.isInteger(value.page) || value.page < 1 || value.page > 1000000)) return false;
  if (value.action === "pdf_sync") {
    if (!point(value.x) || !point(value.y)) return false;
    if (["width", "height"].some(key => value[key] !== undefined && (!finite(value[key]) || value[key] < 0 || value[key] > 1e7))) return false;
    if (value.media_box !== undefined && !mediaBox(value.media_box)) return false;
  }
  if (value.action === "zoom" && (!finite(value.value) || value.value < 0.1 || value.value > 8)) return false;
  if (value.action === "fit" && value.value !== undefined && !["page-fit", "page-width", "auto"].includes(value.value)) return false;
  return true;
}
export function synctexToPdf(x, y, box) { return [box[0] + x, box[3] - y]; }
// `synctex view` emits h/v/W/H for an enclosing box: v is its bottom
// (baseline + depth), and H extends upwards. Point inverse coordinates keep
// the ordinary top-left origin and must not receive this box-only offset.
export function synctexBoxToPdf(x, y, width, height, box) {
  const [left, bottom] = synctexToPdf(x, y, box);
  return [left, bottom, left + width, bottom + height];
}
export function pdfToSynctex(x, y, box) { return [x - box[0], box[3] - y]; }
// Use the viewport's full inverse transform, including rotation, crop origin,
// UserUnit and CSS scale. Device-pixel ratio never enters DOM click positions.
export function clientToSynctex(clientX, clientY, rect, viewport, box) {
  const x = (clientX - rect.left) * viewport.width / rect.width;
  const y = (clientY - rect.top) * viewport.height / rect.height;
  return pdfToSynctex(...viewport.convertToPdfPoint(x, y), box);
}
