#!/usr/bin/env python3
"""Exercise the real GTK/X11 helper in a disposable Xvfb display.

Ubuntu 24.04 prerequisites: python3-gi python3-gi-cairo python3-cairo
gir1.2-gtk-3.0 gir1.2-webkit2-4.1 gir1.2-poppler-0.18 libx11-6 xvfb xauth.
Use the system Python so isolated child processes can import distribution GI:

    xvfb-run -a /usr/bin/python3 -B tests/linux_native_integration.py --require-runtime

Missing prerequisites normally produce SKIP (exit 0); --require-runtime makes
them failures. Only a same-user local Xvfb display is accepted. The temporary
Gtk.Window deliberately provides a bare native XID, not a Gtk.Socket, matching
the helper's winit parent. This is an embedded runtime smoke check, not physical
Linux desktop, Wayland, media-codec, input, accessibility, or full Neovide QA.
Only temporary sample documents and this test's own child processes are touched.
"""

import argparse
from collections import deque
import ctypes
import ctypes.util
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "src/native_preview/linux_helper.py"
MAX_LINE = 65536
MAX_OUTPUT = 1024 * 1024


class RuntimeUnavailable(Exception):
    pass


def require_xvfb():
    """Never create test windows on a user's ordinary desktop display."""
    if sys.platform != "linux":
        raise RuntimeUnavailable("requires Linux; this host is " + sys.platform)
    display = os.environ.get("DISPLAY", "")
    match = re.fullmatch(r"(?:unix)?:([0-9]+)(?:\.[0-9]+)?", display)
    if not match:
        raise RuntimeUnavailable("requires a local DISPLAY started by xvfb-run")
    display_arg = ":" + match.group(1)
    try:
        processes = Path("/proc").iterdir()
        for process in processes:
            if not process.name.isdecimal():
                continue
            try:
                if process.stat().st_uid != os.geteuid():
                    continue
                if (process / "comm").read_text().strip() != "Xvfb":
                    continue
                arguments = (process / "cmdline").read_bytes().split(b"\0")
                if display_arg.encode() in arguments:
                    return
            except (OSError, UnicodeError):
                continue
    except OSError as error:
        raise RuntimeUnavailable("cannot verify a disposable Xvfb display: " + str(error)) from error
    raise RuntimeUnavailable("DISPLAY is not owned by a same-user Xvfb process; use xvfb-run -a")


def bindings():
    try:
        import gi
        import cairo

        gi.require_foreign("cairo")
        for name, version in (("Gtk", "3.0"), ("Gdk", "3.0"),
                              ("GdkX11", "3.0"), ("Poppler", "0.18")):
            gi.require_version(name, version)
        webkit_errors = []
        for version in ("4.1", "4.0"):
            try:
                gi.require_version("WebKit2", version)
                from gi.repository import WebKit2  # noqa: F401
                break
            except (ImportError, ValueError) as error:
                webkit_errors.append(str(error))
        else:
            raise ImportError("WebKit2: " + "; ".join(webkit_errors))
        from gi.repository import Gdk, GdkX11, GLib, Gtk, Poppler  # noqa: F401
    except (ImportError, ValueError) as error:
        raise RuntimeUnavailable("missing system GI/Cairo bindings: " + str(error)) from error
    # Set this only for our process and children, before initializing GTK.
    os.environ["GDK_BACKEND"] = "x11"
    os.environ["GDK_SCALE"] = "1"
    os.environ["GDK_DPI_SCALE"] = "1"
    initialized = Gtk.init_check([])
    if not (initialized[0] if isinstance(initialized, tuple) else initialized):
        raise RuntimeUnavailable("GTK could not initialize the disposable X11 display")
    if not isinstance(Gdk.Display.get_default(), GdkX11.X11Display):
        raise RuntimeUnavailable("requires the GDK X11 backend")
    return Gtk, GdkX11, GLib, cairo


class X11:
    """Small libX11 queries avoid adding python-xlib to the runtime contract."""

    def __init__(self):
        library = ctypes.util.find_library("X11")
        if not library:
            raise RuntimeUnavailable("libX11 is unavailable")
        try:
            self.x = ctypes.CDLL(library)
        except OSError as error:
            raise RuntimeUnavailable("cannot load libX11: " + str(error)) from error
        ulong = ctypes.c_ulong
        uint = ctypes.c_uint
        self.x.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x.XOpenDisplay.restype = ctypes.c_void_p
        self.x.XCloseDisplay.argtypes = [ctypes.c_void_p]
        self.x.XQueryTree.argtypes = [ctypes.c_void_p, ulong, ctypes.POINTER(ulong),
                                     ctypes.POINTER(ulong), ctypes.POINTER(ctypes.POINTER(ulong)),
                                     ctypes.POINTER(uint)]
        self.x.XQueryTree.restype = ctypes.c_int
        self.x.XGetGeometry.argtypes = [ctypes.c_void_p, ulong, ctypes.POINTER(ulong),
                                       ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
                                       ctypes.POINTER(uint), ctypes.POINTER(uint),
                                       ctypes.POINTER(uint), ctypes.POINTER(uint)]
        self.x.XGetGeometry.restype = ctypes.c_int
        self.x.XFree.argtypes = [ctypes.c_void_p]
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise RuntimeUnavailable("libX11 could not open DISPLAY")

    def tree(self, window):
        root, parent, count = ctypes.c_ulong(), ctypes.c_ulong(), ctypes.c_uint()
        children = ctypes.POINTER(ctypes.c_ulong)()
        if not self.x.XQueryTree(self.display, window, ctypes.byref(root), ctypes.byref(parent),
                                 ctypes.byref(children), ctypes.byref(count)):
            raise AssertionError("XQueryTree failed for live window " + str(window))
        try:
            return parent.value, {children[index] for index in range(count.value)}
        finally:
            if children:
                self.x.XFree(children)

    def geometry(self, window):
        root, x, y = ctypes.c_ulong(), ctypes.c_int(), ctypes.c_int()
        width, height, border, depth = (ctypes.c_uint() for _ in range(4))
        if not self.x.XGetGeometry(self.display, window, ctypes.byref(root), ctypes.byref(x),
                                   ctypes.byref(y), ctypes.byref(width), ctypes.byref(height),
                                   ctypes.byref(border), ctypes.byref(depth)):
            raise AssertionError("XGetGeometry failed for live window " + str(window))
        return x.value, y.value, width.value, height.value

    def close(self):
        if self.display:
            self.x.XCloseDisplay(self.display)
            self.display = None


class Helper:
    def __init__(self, glib, parent, kind, source):
        self.context = glib.MainContext.default()
        self.process = subprocess.Popen(
            [sys.executable, "-I", "-u", str(HELPER), "--parent", str(parent),
             "--kind", kind, "--source", str(source)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            bufsize=0,
        )
        self.selector = selectors.DefaultSelector()
        self.buffers = {"stdout": bytearray(), "stderr": bytearray()}
        self.output_size = 0
        self.events = deque(maxlen=256)
        self.sequence = 0
        for name in ("stdout", "stderr"):
            stream = getattr(self.process, name)
            os.set_blocking(stream.fileno(), False)
            self.selector.register(stream, selectors.EVENT_READ, name)

    def send(self, command):
        data = (json.dumps(command, allow_nan=False) + "\n").encode()
        assert len(data) <= MAX_LINE
        try:
            self.process.stdin.write(data)
        except (BrokenPipeError, OSError) as error:
            raise AssertionError("helper closed stdin: " + self.diagnostics()) from error

    def tick(self):
        # Both GTK and pipe reads stay bounded; a partial JSON line never blocks
        # the parent's GTK loop or defeats the deadline in wait().
        for _ in range(32):
            if not self.context.pending():
                break
            self.context.iteration(False)
        for key, _ in self.selector.select(timeout=.01):
            data = os.read(key.fileobj.fileno(), 65536)
            if not data:
                self.selector.unregister(key.fileobj)
                continue
            self.output_size += len(data)
            assert self.output_size <= MAX_OUTPUT, "helper exceeded bounded output budget"
            name = key.data
            self.buffers[name].extend(data)
            if name == "stderr":
                self.buffers[name] = self.buffers[name][-16384:]
                continue
            while b"\n" in self.buffers[name]:
                line, _, remainder = self.buffers[name].partition(b"\n")
                self.buffers[name] = bytearray(remainder)
                assert len(line) <= MAX_LINE, "helper emitted an oversized JSON line"
                try:
                    status = json.loads(line)
                except (ValueError, UnicodeError) as error:
                    raise AssertionError("helper stdout is not JSONL: " + repr(line[:300])) from error
                assert isinstance(status, dict), "helper status is not an object"
                self.sequence += 1
                self.events.append((self.sequence, status))
                assert status.get("state") != "error", "helper error: " + self.diagnostics()
                assert not status.get("protocol_error"), "helper rejected a valid command: " + repr(status)
            assert len(self.buffers[name]) <= MAX_LINE, "helper emitted an unbounded partial JSON line"

    def wait(self, predicate, label, *, after=0, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.tick()
            for sequence, status in self.events:
                if sequence > after and predicate(status):
                    return sequence, status
            if self.process.poll() is not None:
                raise AssertionError(label + ": helper exited early: " + self.diagnostics())
        raise AssertionError(label + ": timed out: " + self.diagnostics())

    def action(self, action, value=0, predicate=lambda status: True):
        after = self.sequence
        self.send({"type": "action", "action": action, "value": value})
        return self.wait(predicate, action, after=after)

    def diagnostics(self):
        return json.dumps({"returncode": self.process.poll(), "statuses": list(self.events)[-6:],
                           "stderr": self.buffers["stderr"].decode("utf-8", errors="replace")[-4000:]},
                          ensure_ascii=False)

    def close_and_check(self):
        self.send({"type": "close"})
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and self.process.poll() is None:
            self.tick()
        assert self.process.poll() == 0, "close did not exit cleanly: " + self.diagnostics()

    def cleanup(self):
        try:
            self.process.stdin.close()
        except OSError:
            pass
        if self.process.poll() is None:
            try:
                self.process.wait(timeout=.5)
            except subprocess.TimeoutExpired:
                self.process.terminate()  # Only the subprocess created above.
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=2)
        self.selector.close()
        self.process.stdout.close()
        self.process.stderr.close()


def pdf_fixture(cairo, path, pages):
    replacement = path.with_suffix(".new.pdf")
    surface = cairo.PDFSurface(str(replacement), 300, 200)
    context = cairo.Context(surface)
    for page in range(pages):
        context.set_source_rgb(1, 1, 1)
        context.paint()
        context.set_source_rgb(.15 + page * .2, .3, .7)
        context.rectangle(30, 30, 240, 140)
        context.fill()
        context.show_page()
    surface.finish()
    replacement.replace(path)  # Do not rewrite a file Poppler may still map.


def embed(helper, x11, parent, baseline):
    helper.send({"type": "layout", "bounds": [24, 32, 420, 280], "holes": [], "dpi": 1})
    helper.action("status", predicate=lambda status: status.get("state") == "ready")
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        helper.tick()
        children = x11.tree(parent)[1] - baseline
        for child in children:
            if x11.geometry(child) == (24, 32, 420, 280):
                assert x11.tree(child)[0] == parent, "preview is not embedded in the bare parent XID"
                return child
    raise AssertionError("no embedded child has the requested X11 layout: " + helper.diagnostics())


def check_kind(glib, cairo, x11, parent, directory, kind):
    baseline = x11.tree(parent)[1]
    source = directory / ("sample.pdf" if kind == "pdf" else "sample.html")
    if kind == "pdf":
        pdf_fixture(cairo, source, 1)
    else:
        (directory / "sample.css").write_text("body { background: #ced8f4; color: #123; }\n")
        source.write_text('<!doctype html><meta charset="utf-8"><title>Glow Linux smoke</title>'
                          '<link rel="stylesheet" href="sample.css"><p>Temporary local preview</p>\n')
    helper = Helper(glib, parent, kind, source)
    try:
        _, ready = helper.wait(lambda status: status.get("state") == "ready", kind + " ready")
        assert ready.get("kind") == kind and ready.get("backend") == "gtk3-xembed", ready
        assert ready.get("gui_verified") is False, "runtime helper must not claim desktop QA"
        child = embed(helper, x11, parent, baseline)
        if kind == "pdf":
            assert ready.get("page") == 1 and ready.get("pages") == 1, ready
            # Rewrite only our fixture, proving reload and navigation rather
            # than accepting a next command clamped to a one-page document.
            pdf_fixture(cairo, source, 2)
            helper.action("reload", predicate=lambda status: status.get("pages") == 2)
            helper.action("next", predicate=lambda status: status.get("page") == 2)
            helper.action("previous", predicate=lambda status: status.get("page") == 1)
            helper.action("zoom", 1.5, lambda status: abs(status.get("zoom", 0) - 1.5) < 1e-6)
            helper.send({"type": "sync", "page": 2, "x": 50, "y": 50, "width": 20, "height": 10})
            helper.wait(lambda status: status.get("page") == 2, "PDF forward sync", after=helper.sequence)
            helper.action("fit", predicate=lambda status: 0 < status.get("zoom", 0) < 1.5)
        else:
            assert ready.get("read_root") == str(directory), ready
            assert ready.get("url", "").startswith("glow-file://local/"), ready
            helper.action("zoom", 1.5, lambda status: abs(status.get("zoom", 0) - 1.5) < 1e-6)
            after = helper.sequence
            helper.send({"type": "action", "action": "reload", "value": 0})
            sequence, _ = helper.wait(lambda status: status.get("state") == "loading", "web reload start", after=after)
            helper.wait(lambda status: status.get("state") == "ready", "web reload finish", after=sequence)
        helper.close_and_check()
        deadline = time.monotonic() + 2
        while child in x11.tree(parent)[1] and time.monotonic() < deadline:
            helper.tick()
        assert x11.tree(parent)[1] == baseline, "preview child survived close or modified the parent"
        return kind + ": ready, bare-XID embedding/layout, reload, zoom, close" + (
            ", page count, next/previous, forward sync, fit" if kind == "pdf" else ", rooted local HTML")
    finally:
        helper.cleanup()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-runtime", action="store_true",
                        help="fail instead of skip when the isolated Linux runtime is unavailable")
    args = parser.parse_args(argv)
    try:
        require_xvfb()
        Gtk, GdkX11, GLib, cairo = bindings()
        x11 = X11()
    except RuntimeUnavailable as error:
        print(("FAIL" if args.require_runtime else "SKIP") + ": " + str(error))
        return 1 if args.require_runtime else 0
    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    try:
        window.set_title("Glow isolated Linux helper smoke")
        window.set_default_size(640, 480)
        window.show_all()
        window.realize()
        context = GLib.MainContext.default()
        for _ in range(32):
            if not context.pending():
                break
            context.iteration(False)
        parent = GdkX11.X11Window.get_xid(window.get_window())
        with tempfile.TemporaryDirectory(prefix="glow-linux-x11-") as temporary:
            for kind in ("pdf", "web"):
                result = check_kind(GLib, cairo, x11, parent, Path(temporary).resolve(), kind)
                print("PASS: " + result, flush=True)
        print("PASS: isolated Xvfb runtime smoke only; physical Linux GUI and media codecs remain unverified")
        return 0
    finally:
        window.destroy()
        x11.close()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, ValueError) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        raise SystemExit(1)
