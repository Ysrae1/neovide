#!/usr/bin/env python3
"""Private X11 Gtk.Plug preview process. JSONL stdin/stdout, GTK on one thread.

Runtime packages: python3-gi, python3-gi-cairo, python3-cairo,
gir1.2-gtk-3.0, gir1.2-webkit2-4.1 (or 4.0), gir1.2-poppler-0.18.
Media decoding additionally uses the distribution's GStreamer plugins.
--probe imports bindings only: it never initializes GTK or verifies a GUI.
"""
import argparse
import html
import importlib
import json
import math
import mimetypes
import os
from pathlib import Path
import sys
from urllib.parse import quote, unquote, urlsplit


MAX_LINE = 65536
MAX_COORD = 1_000_000
KINDS = ("audio", "video", "web", "pdf")
ACTIONS = {"play", "pause", "toggle", "seek", "volume", "status", "reload",
           "zoom", "focus", "blur", "back", "forward", "page", "next", "previous", "fit"}


def number(value, low=-MAX_COORD, high=MAX_COORD):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
        raise ValueError("Expected a finite number in [%s, %s]" % (low, high))
    return float(value)


def parse_command(line):
    if len(line.encode("utf-8") if isinstance(line, str) else line) > MAX_LINE:
        raise ValueError("Command exceeds 64 KiB")
    command = json.loads(line)
    if not isinstance(command, dict):
        raise ValueError("Command must be an object")
    kind = command.get("type")
    if kind == "layout":
        bounds, holes = command.get("bounds"), command.get("holes", [])
        if not isinstance(bounds, list) or len(bounds) != 4 or not isinstance(holes, list) or len(holes) > 128:
            raise ValueError("Invalid layout bounds/holes")
        bounds = [number(value) for value in bounds]
        if not 0 <= bounds[2] <= 32768 or not 0 <= bounds[3] <= 32768:
            raise ValueError("Layout size must be between 0 and 32768 pixels")
        regions = []
        for hole in holes:
            if not isinstance(hole, list) or len(hole) != 4:
                raise ValueError("Invalid occlusion rectangle")
            values = [number(value) for value in hole]
            if values[2] < values[0] or values[3] < values[1]:
                raise ValueError("Inverted occlusion rectangle")
            regions.append(values)
        return {"type": kind, "bounds": bounds, "holes": regions, "dpi": number(command.get("dpi", 1), .25, 8)}
    if kind == "action":
        action = command.get("action")
        if not isinstance(action, str) or action not in ACTIONS:
            raise ValueError("Unknown action")
        return {"type": kind, "action": action, "value": number(command.get("value", 0))}
    if kind == "sync":
        page = number(command.get("page"), 1, MAX_COORD)
        if not page.is_integer():
            raise ValueError("PDF page must be an integer")
        return {"type": kind, "page": int(page), **{key: number(command.get(key, 0), 0) for key in ("x", "y", "width", "height")}}
    if kind == "close":
        return {"type": kind}
    raise ValueError("Unknown command type")


def logical_layout(command, scale=None):
    """Physical X pixels -> GDK coordinates, using the child's actual GDK scale.

    Fractional parent DPI and integer GDK scaling may differ; dividing by the
    parent DPI in that case would move/resize the child incorrectly.
    """
    scale = number(command["dpi"] if scale is None else scale, .25, 8)
    x, y, width, height = command["bounds"]
    bounds = (math.floor(x / scale), math.floor(y / scale), math.ceil(width / scale), math.ceil(height / scale))
    holes = []
    for x1, y1, x2, y2 in command["holes"]:
        left, top = max(0, math.floor(x1 / scale)), max(0, math.floor(y1 / scale))
        right, bottom = min(bounds[2], math.ceil(x2 / scale)), min(bounds[3], math.ceil(y2 / scale))
        if right > left and bottom > top:
            holes.append((left, top, right - left, bottom - top))
    return bounds, holes


def pdf_transform(page_size, viewport, zoom=1, fit=True):
    pw, ph = (number(value, .01, 100000) for value in page_size)
    vw, vh = (number(value, 1, 32768) for value in viewport)
    scale = min(vw / pw, vh / ph) if fit else number(zoom, .01, 32)
    scale = max(.01, min(32, scale))
    if pw * scale > 32768 or ph * scale > 32768:
        raise ValueError("PDF page exceeds the bounded drawing area")
    return scale, max(0, (vw - pw * scale) / 2), max(0, (vh - ph * scale) / 2)


def pdf_point(x, y, transform, page_size):
    scale, left, top = transform
    point = ((number(x) - left) / scale, (number(y) - top) / scale)
    return point if 0 <= point[0] <= page_size[0] and 0 <= point[1] <= page_size[1] else None


def source_uri(source, kind):
    if not isinstance(source, str) or not source or len(source) > 8192 or "\0" in source:
        raise ValueError("Invalid preview source")
    parts = urlsplit(source)
    if parts.scheme.lower() in ("http", "https"):
        if kind == "pdf" or not parts.hostname or parts.username or parts.password:
            raise ValueError("PDF requires a local file; remote URLs must have a host and no embedded credentials")
        return source, None
    if parts.scheme and parts.scheme.lower() != "file":
        raise ValueError("Only local files and HTTP(S) sources are supported")
    if parts.scheme:
        if parts.netloc not in ("", "localhost"):
            raise ValueError("Remote file authorities are not supported")
        filename = unquote(parts.path, errors="strict")
    else:
        filename = source
    if "\0" in filename:
        raise ValueError("Invalid local path")
    path = Path(filename).expanduser().resolve(strict=True)
    if not path.is_file():
        raise ValueError("Preview source is not a regular file")
    return path.as_uri(), path


def rooted_asset(root, uri):
    parts = urlsplit(uri)
    if parts.scheme != "glow-file" or parts.netloc != "local":
        raise ValueError("Invalid private asset URL")
    name = unquote(parts.path, errors="strict").lstrip("/")
    if "\0" in name:
        raise ValueError("Invalid asset path")
    path = (root / name).resolve(strict=True)
    if not path.is_relative_to(root) or not path.is_file():
        raise ValueError("Asset is outside the opened document directory")
    return path


def media_script(action="status", value=0):
    if action not in ACTIONS:
        raise ValueError("Unknown media action")
    value = number(value)
    operation = {"play": "m.play().catch(()=>{});", "pause": "m.pause();",
                 "toggle": "if(m.paused)m.play().catch(()=>{});else m.pause();",
                 "seek": "m.currentTime=Math.max(0,Math.min(v,Number.isFinite(m.duration)?m.duration:v));",
                 "volume": "m.volume=Math.max(0,Math.min(1,v));"}.get(action, "")
    return """(()=>{const m=document.querySelector('audio,video');if(!m)return JSON.stringify({state:'loading'});
const v=%s;%s
return JSON.stringify({state:m.error?'error':m.ended?'ended':m.paused?'paused':'playing',
error:m.error?(m.error.message||'Media decoder failed'):'',position:Number.isFinite(m.currentTime)?m.currentTime:0,
duration:Number.isFinite(m.duration)?m.duration:0,volume:m.volume});})()""" % (json.dumps(value), operation)


def emit(status):
    encoded = json.dumps(status, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > MAX_LINE - 1:
        encoded = '{"state":"error","error":"Preview status exceeds protocol limit","gui_verified":false}'
    print(encoded, flush=True)


def load_bindings():
    # No import-time GI or display access: this function is called only by run.
    modules, errors = {}, {}
    try:
        import gi
    except ImportError as error:
        return modules, {"gi": str(error)}
    for name, version in (("Gtk", "3.0"), ("Gdk", "3.0"), ("GdkX11", "3.0"), ("GLib", "2.0"), ("Gio", "2.0"), ("Poppler", "0.18")):
        try:
            gi.require_version(name, version)
            modules[name] = importlib.import_module("gi.repository." + name)
        except (ImportError, ValueError, AttributeError) as error:
            errors[name] = str(error)
    for version in ("4.1", "4.0"):
        try:
            gi.require_version("WebKit2", version)
            modules["WebKit2"] = importlib.import_module("gi.repository.WebKit2")
            break
        except (ImportError, ValueError, AttributeError) as error:
            errors["WebKit2"] = str(error)
    if "WebKit2" in modules:
        errors.pop("WebKit2", None)
    try:
        import cairo
        gi.require_foreign("cairo")
        modules["cairo"] = cairo
    except ImportError as error:
        errors["cairo"] = str(error)
    return modules, errors


def capabilities(modules, errors):
    base = all(name in modules for name in ("Gtk", "Gdk", "GdkX11", "GLib", "Gio", "cairo"))
    kinds = [kind for kind in KINDS if base and ("Poppler" in modules if kind == "pdf" else "WebKit2" in modules)]
    return {"backend": "gtk3-xembed", "kinds": kinds, "synctex_supported": "pdf" in kinds,
            "requires_x11": True, "gui_verified": False, "media_codecs_verified": False,
            "dependencies": {name: name in modules for name in ("Gtk", "GdkX11", "WebKit2", "Poppler", "cairo")},
            "errors": {key: str(value)[:1000] for key, value in errors.items()}}


class Preview:
    def __init__(self, modules, parent, kind, source):
        self.m = modules
        self.Gtk, self.Gdk, self.GLib = (modules[name] for name in ("Gtk", "Gdk", "GLib"))
        self.kind, self.parent = kind, parent
        self.uri, self.file = source_uri(source, kind)
        self.root = self.file.parent if self.file else None
        self.state, self.error, self.zoom = "loading", "", 1.0
        self.page, self.pages, self.fit, self.transform = 1, 0, True, (1, 0, 0)
        self.inverse, self.sync_marker, self.sync_sequence = None, None, 0
        self.buffer, self.layout = bytearray(), None
        self.closed, self.js_pending = False, False
        self.pending_media = []
        self.status_values = {}
        self.plug = self.Gtk.Plug.new(parent)
        self.plug.set_decorated(False)
        self.plug.set_focus_on_map(False)
        self.plug.connect("delete-event", self.delete)
        self.plug.connect("destroy", lambda *_: self.Gtk.main_quit())
        self.plug.connect("key-press-event", self.key)
        if kind == "pdf":
            self.create_pdf()
        else:
            self.create_web()
        self.plug.add(self.widget)
        self.widget.show_all()
        self.plug.realize()  # Native child exists but stays hidden until layout.
        self.plug.hide()

    def status(self, **extra):
        result = {"kind": self.kind, "backend": "gtk3-xembed", "state": self.state,
                  "error": self.error[:4000], "source": self.uri, "zoom": self.zoom,
                  "gui_verified": False, "synctex_supported": self.kind == "pdf"}
        if self.kind == "pdf":
            result.update(page=self.page, pages=self.pages)
            if self.inverse:
                result["synctex"] = self.inverse
        else:
            result.update(self.status_values)
            result["url"] = self.web.get_uri() or self.uri
            if self.kind == "web" and self.root:
                result["read_root"] = str(self.root)
        result.update(extra)
        emit(result)

    def fail(self, error):
        self.state, self.error = "error", str(error)[:4000]
        self.status()

    def delete(self, *_):
        self.status(close_requested=True)
        self.close()
        return True

    def key(self, _widget, event):
        if event.keyval == self.Gdk.KEY_Escape:
            self.focus_parent()
            return True
        return False

    def focus_parent(self):
        socket = self.plug.get_socket_window()
        if socket is not None:
            socket.focus(self.Gdk.CURRENT_TIME)
        else:
            display = self.plug.get_display()
            parent = self.m["GdkX11"].X11Window.foreign_new_for_display(display, self.parent)
            if parent:
                parent.focus(self.Gdk.CURRENT_TIME)

    def create_pdf(self):
        self.widget = self.Gtk.ScrolledWindow()
        self.widget.set_policy(self.Gtk.PolicyType.AUTOMATIC, self.Gtk.PolicyType.AUTOMATIC)
        self.area = self.Gtk.DrawingArea()
        self.area.set_can_focus(True)
        self.area.add_events(self.Gdk.EventMask.BUTTON_PRESS_MASK)
        self.area.connect("draw", self.draw_pdf)
        self.area.connect("button-press-event", self.pdf_click)
        self.widget.add_with_viewport(self.area)
        self.load_pdf()

    def load_pdf(self):
        self.document = self.m["Poppler"].Document.new_from_file(self.uri, None)
        self.pages = self.document.get_n_pages()
        if not 0 < self.pages <= 100000:
            raise ValueError("PDF has no pages or exceeds the page limit")
        self.page = min(self.page, self.pages)
        self.current_page = self.document.get_page(self.page - 1)
        self.state, self.error = "ready", ""

    def update_pdf(self):
        self.current_page = self.document.get_page(self.page - 1)
        width, height = self.current_page.get_size()
        viewport = (max(1, self.widget.get_allocated_width()), max(1, self.widget.get_allocated_height()))
        self.transform = pdf_transform((width, height), viewport, self.zoom, self.fit)
        self.zoom = self.transform[0]
        self.area.set_size_request(max(viewport[0], math.ceil(width * self.zoom)), max(viewport[1], math.ceil(height * self.zoom)))
        self.area.queue_draw()

    def draw_pdf(self, area, context):
        try:
            width, height = self.current_page.get_size()
            viewport = (max(1, self.widget.get_allocated_width()), max(1, self.widget.get_allocated_height()))
            self.transform = pdf_transform((width, height), viewport, self.zoom, self.fit)
            self.zoom = self.transform[0]
            scale, left, top = self.transform
            context.set_source_rgb(.16, .16, .16)
            context.paint()
            context.save()
            context.translate(left, top)
            context.scale(scale, scale)
            context.set_source_rgb(1, 1, 1)
            context.rectangle(0, 0, width, height)
            context.fill()
            self.current_page.render(context)
            if self.sync_marker:
                x, y, w, h = self.sync_marker
                context.set_source_rgba(.2, .5, 1, .22)
                context.rectangle(x, y, max(8, w), max(10, h))
                context.fill_preserve()
                context.set_source_rgba(.2, .5, 1, .8)
                context.set_line_width(1 / scale)
                context.stroke()
            context.restore()
        except Exception as error:
            self.fail(error)
        return False

    def pdf_click(self, _area, event):
        double = event.type in (getattr(self.Gdk.EventType, "_2BUTTON_PRESS", None),
                                getattr(self.Gdk.EventType, "DOUBLE_BUTTON_PRESS", None))
        if event.button != 1 or not (event.state & self.Gdk.ModifierType.CONTROL_MASK or double):
            return False
        point = pdf_point(event.x, event.y, self.transform, self.current_page.get_size())
        if point:
            self.sync_sequence += 1
            self.inverse = {"seq": self.sync_sequence, "page": self.page, "x": point[0], "y": point[1]}
            self.status()
            self.focus_parent()
        return True

    def sync_pdf(self, command):
        if self.kind != "pdf":
            raise ValueError("Coordinate synchronization requires a PDF")
        if command["page"] > self.pages:
            raise ValueError("PDF synchronization page is out of range")
        self.page = command["page"]
        self.update_pdf()
        pw, ph = self.current_page.get_size()
        if command["x"] > pw or command["y"] > ph:
            raise ValueError("PDF synchronization point is outside the page")
        self.sync_marker = tuple(command[key] for key in ("x", "y", "width", "height"))
        marker = self.sync_marker
        def scroll_to_point():
            scale, left, top = self.transform
            for adjustment, value in ((self.widget.get_hadjustment(), left + command["x"] * scale),
                                      (self.widget.get_vadjustment(), top + command["y"] * scale)):
                adjustment.set_value(max(adjustment.get_lower(), min(adjustment.get_upper() - adjustment.get_page_size(), value - adjustment.get_page_size() / 2)))
            return False
        def clear_marker():
            if self.sync_marker is marker:
                self.sync_marker = None
                self.area.queue_draw()
            return False
        self.GLib.idle_add(scroll_to_point)
        self.GLib.timeout_add(2000, clear_marker)
        self.area.queue_draw()
        self.status()

    def create_web(self):
        webkit = self.m["WebKit2"]
        self.context = webkit.WebContext.new_ephemeral()
        self.context.connect("download-started", lambda _ctx, download: download.cancel())
        if self.kind == "web" and self.root:
            self.context.register_uri_scheme("glow-file", self.asset_request, None)
            security = self.context.get_security_manager()
            security.register_uri_scheme_as_local("glow-file")
            security.register_uri_scheme_as_secure("glow-file")
            security.register_uri_scheme_as_cors_enabled("glow-file")
        self.web = webkit.WebView.new_with_context(self.context)
        settings = self.web.get_settings()
        for prop, value in (("enable-developer-extras", False), ("javascript-can-open-windows-automatically", False),
                            ("allow-universal-access-from-file-urls", False), ("enable-html5-local-storage", False),
                            ("media-playback-requires-user-gesture", False)):
            if settings.find_property(prop):
                settings.set_property(prop, value)
        self.web.connect("decide-policy", self.web_policy)
        self.web.connect("permission-request", lambda _web, request: (request.deny(), True)[1])
        self.web.connect("create", lambda *_: None)
        self.web.connect("load-changed", self.web_loaded)
        self.web.connect("load-failed", self.web_failed)
        self.widget = self.web
        if self.kind == "web":
            uri = "glow-file://local/" + quote(self.file.name) if self.file else self.uri
            self.web.load_uri(uri)
        else:
            # Only trusted markup references this one media file; no user HTML
            # gains general file-origin access through this player document.
            markup = ('<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#181818;height:100%;}'
                      'audio,video{display:block;width:100%;height:100%;object-fit:contain}</style><'
                      + self.kind + ' controls autoplay src="' + html.escape(self.uri, quote=True) + '"></' + self.kind + '>')
            self.web.load_html(markup, self.uri)

    def asset_request(self, request, _data=None):
        try:
            path = rooted_asset(self.root, request.get_uri())
            size = path.stat().st_size
            if size > 64 * 1024 * 1024:
                raise ValueError("Web asset exceeds 64 MiB")
            stream = self.m["Gio"].File.new_for_path(str(path)).read(None)
            request.finish(stream, size, mimetypes.guess_type(str(path))[0] or "application/octet-stream")
        except Exception as error:
            # Finishing with an empty body avoids exposing any outside path.
            stream = self.m["Gio"].MemoryInputStream.new_from_bytes(self.GLib.Bytes.new(b""))
            request.finish(stream, 0, "text/plain")
            self.status(blocked_asset=str(error)[:1000])

    def navigation_allowed(self, uri):
        try:
            parts = urlsplit(uri)
        except ValueError:
            return False
        if parts.scheme in ("http", "https"):
            return bool(parts.hostname) and not parts.username and not parts.password
        if self.kind == "web" and self.root:
            try:
                rooted_asset(self.root, uri)
                return True
            except (OSError, ValueError):
                return False
        return self.kind in ("audio", "video") and (uri == "about:blank" or uri.split("#")[0] == self.uri)

    def web_policy(self, _web, decision, policy):
        webkit = self.m["WebKit2"]
        if policy == webkit.PolicyDecisionType.NEW_WINDOW_ACTION:
            decision.ignore()
            return True
        if policy == webkit.PolicyDecisionType.NAVIGATION_ACTION:
            uri = decision.get_navigation_action().get_request().get_uri()
            if self.navigation_allowed(uri):
                decision.use()
            else:
                decision.ignore()
                self.status(navigation_blocked=True)
            return True
        return False

    def web_loaded(self, _web, event):
        if event == self.m["WebKit2"].LoadEvent.FINISHED and self.state != "error":
            self.state, self.error = "ready", ""
            self.poll_media()
            self.status()

    def web_failed(self, _web, _event, _uri, error):
        self.fail(error)
        return True

    def poll_media(self, action="status", value=0):
        if self.kind == "web" or self.closed:
            return
        if self.js_pending:
            if action != "status":
                if len(self.pending_media) >= 16:
                    raise ValueError("Too many pending media actions")
                self.pending_media.append((action, value))
            return
        self.js_pending = True
        def completed(web, result, _data=None):
            self.js_pending = False
            if self.closed:
                return
            try:
                js = web.run_javascript_finish(result)
                raw = js.get_js_value().to_string()
                if len(raw) > MAX_LINE:
                    raise ValueError("Media state is too large")
                state = json.loads(raw)
                self.state = state.get("state", "ready")
                self.error = str(state.get("error", ""))[:4000]
                self.status_values = {name: number(state[name], 0) for name in ("position", "duration", "volume") if name in state}
                self.status()
            except Exception as error:
                self.fail(error)
            if self.pending_media and not self.closed:
                pending_action, pending_value = self.pending_media.pop(0)
                self.poll_media(pending_action, pending_value)
        self.web.run_javascript(media_script(action, value), None, completed, None)

    def apply_layout(self, command):
        self.layout = command
        (x, y, width, height), holes = logical_layout(command, self.plug.get_scale_factor())
        if width <= 0 or height <= 0:
            self.plug.hide()
            return
        self.plug.resize(width, height)
        window = self.plug.get_window()
        window.move_resize(x, y, width, height)
        cairo = self.m["cairo"]
        region = cairo.Region(cairo.RectangleInt(0, 0, width, height))
        for hole in holes:
            region.subtract(cairo.Region(cairo.RectangleInt(*hole)))
        window.shape_combine_region(region, 0, 0)
        window.input_shape_combine_region(region, 0, 0)
        self.plug.show()
        if self.kind == "pdf":
            self.update_pdf()

    def action(self, action, value):
        if action == "focus":
            self.widget.grab_focus()
            self.plug.get_window().focus(self.Gdk.CURRENT_TIME)
        elif action == "blur":
            self.focus_parent()
        elif self.kind == "pdf":
            if action == "reload":
                self.load_pdf()
            elif action in ("page", "next", "previous"):
                self.page = max(1, min(self.pages, int(value) if action == "page" else self.page + (1 if action == "next" else -1)))
                self.sync_marker = None
            elif action == "zoom":
                self.zoom, self.fit = max(.25, min(5, value)), False
            elif action == "fit":
                self.fit = True
            if action != "status":
                self.update_pdf()
        elif action in ("reload", "back", "forward", "zoom"):
            if action == "reload":
                self.state, self.error = "loading", ""
                self.web.reload()
            elif action == "back" and self.web.can_go_back():
                self.web.go_back()
            elif action == "forward" and self.web.can_go_forward():
                self.web.go_forward()
            elif action == "zoom":
                self.zoom = max(.25, min(5, value))
                self.web.set_zoom_level(self.zoom)
        else:
            self.poll_media(action, value)
        self.status()

    def command(self, command):
        if command["type"] == "layout":
            self.apply_layout(command)
        elif command["type"] == "action":
            self.action(command["action"], command["value"])
        elif command["type"] == "sync":
            self.sync_pdf(command)
        else:
            self.close()

    def close(self):
        if not self.closed:
            self.closed = True
            if self.kind != "pdf":
                self.web.stop_loading()
            self.plug.destroy()
            self.Gtk.main_quit()

    def stdin_ready(self, fd, condition):
        try:
            if condition & self.GLib.IO_ERR:
                self.close()
                return False
            data = os.read(fd, 8192)
            if not data:
                self.close()
                return False
            self.buffer.extend(data)
            while b"\n" in self.buffer:
                line, _, rest = self.buffer.partition(b"\n")
                self.buffer = bytearray(rest)
                try:
                    self.command(parse_command(line))
                except (ValueError, OSError, TypeError) as error:
                    self.status(protocol_error=str(error)[:1000])
                if self.closed:
                    return False
            if len(self.buffer) > MAX_LINE:
                self.fail("Unterminated command exceeds 64 KiB")
                self.close()
                return False
        except BlockingIOError:
            pass
        except Exception as error:
            self.fail(error)
            self.close()
            return False
        return not self.closed


def run(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--parent", type=int)
    parser.add_argument("--kind", choices=KINDS)
    parser.add_argument("--source")
    args = parser.parse_args(argv)
    if not args.probe:
        os.environ["GDK_BACKEND"] = "x11"  # This subprocess alone; parent must supply a real XID.
    modules, errors = load_bindings()
    report = capabilities(modules, errors)
    if args.probe:
        emit(report)
        return 0
    if not args.parent or not 0 < args.parent < 2 ** 32 or args.kind is None or not args.source:
        raise ValueError("--parent XID, --kind and --source are required")
    if args.kind not in report["kinds"]:
        raise ValueError("Missing GTK preview dependencies: " + json.dumps(errors))
    # Gtk.Plug supports X11/XWayland only; never pretend to embed in Wayland.
    initialized = modules["Gtk"].init_check([])
    if not (initialized[0] if isinstance(initialized, tuple) else initialized):
        raise ValueError("GTK could not open the X11 display")
    display = modules["Gdk"].Display.get_default()
    if display is None or not isinstance(display, modules["GdkX11"].X11Display):
        raise ValueError("GTK preview requires an X11 display; native Wayland is unsupported")
    preview = Preview(modules, args.parent, args.kind, args.source)
    preview.status()
    fd = sys.stdin.fileno()
    os.set_blocking(fd, False)
    modules["GLib"].io_add_watch(fd, modules["GLib"].IO_IN | modules["GLib"].IO_HUP | modules["GLib"].IO_ERR, preview.stdin_ready)
    try:
        modules["Gtk"].main()
    finally:
        preview.close()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except Exception as error:
        emit({"state": "error", "error": str(error)[:4000], "backend": "gtk3-xembed", "gui_verified": False})
        raise SystemExit(1)
