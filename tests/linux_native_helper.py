#!/usr/bin/env python3
"""Pure protocol/geometry and mocked lifecycle checks; no GI, display or Rust."""
import contextlib
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import MagicMock, patch


SOURCE = Path(__file__).resolve().parents[1] / "src/native_preview/linux_helper.py"
SPEC = importlib.util.spec_from_file_location("glow_linux_helper", SOURCE)
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


class Helper(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="linux-native-helper-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def test_import_compiles_without_loading_gi_or_connecting_display(self):
        compile(SOURCE.read_text(), str(SOURCE), "exec")
        self.assertNotIn("gi", helper.__dict__)
        self.assertNotIn("cairo", helper.__dict__)

    def test_parse_layout_action_sync_close(self):
        layout = {"type": "layout", "bounds": [20, 40, 600, 800], "holes": [[2, 3, 30, 40]], "dpi": 2}
        self.assertEqual(helper.parse_command(json.dumps(layout)), layout)
        self.assertEqual(helper.parse_command('{"type":"action","action":"zoom","value":1.5}'),
                         {"type": "action", "action": "zoom", "value": 1.5})
        self.assertEqual(helper.parse_command('{"type":"sync","page":2,"x":20,"y":30}'),
                         {"type": "sync", "page": 2, "x": 20, "y": 30, "width": 0, "height": 0})
        self.assertEqual(helper.parse_command('{"type":"close"}'), {"type": "close"})

    def test_reject_malformed_nonfinite_oversized_and_inverted_commands(self):
        cases = ["[]", "null", "{", '{"type":"unknown"}', '{"type":"action","action":[]}',
                 '{"type":"action","action":"exec"}', '{"type":"action","action":"zoom","value":NaN}',
                 '{"type":"sync","page":0}', '{"type":"sync","page":1.5}', '{"type":"sync","page":true}',
                 '{"type":"layout","bounds":[0,0,-1,3]}', '{"type":"layout","bounds":[0,0,3,3],"dpi":0}',
                 '{"type":"layout","bounds":[0,0,3,3],"holes":[[5,0,2,5]]}',
                 json.dumps({"type": "layout", "bounds": [0, 0, 3, 3], "holes": [[0, 0, 1, 1]] * 129}),
                 " " * (helper.MAX_LINE + 1)]
        for value in cases:
            with self.subTest(value=value[:100]):
                with self.assertRaises(ValueError):
                    helper.parse_command(value)

    def test_physical_geometry_holes_and_fractional_parent_dpi(self):
        layout = helper.parse_command(json.dumps({"type": "layout", "bounds": [101, 51, 600, 400],
                                                 "dpi": 1.5, "holes": [[-10, 20, 51, 100], [900, 900, 1000, 1000]]}))
        self.assertEqual(helper.logical_layout(layout, scale=2), ((50, 25, 300, 200), [(0, 10, 26, 40)]))
        # GDK scale=1 must preserve physical X geometry even if Winit dpi=1.5.
        self.assertEqual(helper.logical_layout(layout, scale=1)[0], (101, 51, 600, 400))
        self.assertEqual(helper.logical_layout(layout)[0], (67, 34, 400, 267))

    def test_pdf_transform_inverse_round_trip_and_page_margins(self):
        transform = helper.pdf_transform((600, 800), (1000, 1000), fit=True)
        self.assertEqual(transform, (1.25, 125, 0))
        point = (210, 350)
        x, y = point[0] * transform[0] + transform[1], point[1] * transform[0] + transform[2]
        self.assertEqual(helper.pdf_point(x, y, transform, (600, 800)), point)
        self.assertIsNone(helper.pdf_point(0, 100, transform, (600, 800)))
        self.assertEqual(helper.pdf_transform((600, 800), (1000, 1000), zoom=2, fit=False), (2, 0, 0))
        for page, viewport in [((0, 2), (100, 100)), ((600, 800), (math.nan, 100)), ((100000, 100000), (100, 100))]:
            with self.subTest(page=page, viewport=viewport), self.assertRaises(ValueError):
                helper.pdf_transform(page, viewport, zoom=5, fit=False)

    def test_sources_only_local_files_or_http_and_pdf_local_only(self):
        local = self.root / "中文 'quoted'.pdf"
        local.write_bytes(b"test")
        uri, path = helper.source_uri(str(local), "pdf")
        self.assertEqual(path, local)
        self.assertEqual(uri, local.as_uri())
        self.assertEqual(helper.source_uri(uri, "pdf"), (uri, local))
        self.assertEqual(helper.source_uri("https://example.invalid/test", "web"), ("https://example.invalid/test", None))
        for source, kind in [("https://example.invalid/a.pdf", "pdf"), ("javascript:alert(1)", "web"),
                             ("data:text/html,test", "web"), ("file://remote/path", "web"),
                             ("https://user:password@example.invalid", "web"), ("/tmp/none\0.pdf", "pdf")]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                helper.source_uri(source, kind)

    def test_private_web_assets_reject_escape_and_symlinks(self):
        root = self.root / "document"
        root.mkdir()
        (root / "index.html").write_text("<p>document</p>")
        outside = self.root / "private.txt"
        outside.write_text("private")
        (root / "link.txt").symlink_to(outside)
        self.assertEqual(helper.rooted_asset(root, "glow-file://local/index.html"), root / "index.html")
        for uri in ("glow-file://local/../private.txt", "glow-file://local/%2e%2e/private.txt",
                    "glow-file://local/link.txt", "glow-file://remote/index.html", "file:///private.txt"):
            with self.subTest(uri=uri), self.assertRaises(ValueError):
                helper.rooted_asset(root, uri)

    def test_web_navigation_policy_blocks_external_schemes_and_unrelated_local_files(self):
        (self.root / "index.html").write_text("test")
        preview = helper.Preview.__new__(helper.Preview)
        preview.kind, preview.root, preview.uri = "web", self.root, (self.root / "index.html").as_uri()
        self.assertTrue(preview.navigation_allowed("glow-file://local/index.html"))
        self.assertTrue(preview.navigation_allowed("https://example.invalid/path"))
        for uri in ("mailto:a@example.invalid", "javascript:alert(1)", "file:///etc/passwd", "glow-file://local/../outside", "https://[bad"):
            self.assertFalse(preview.navigation_allowed(uri), uri)
        preview.kind = "audio"
        self.assertTrue(preview.navigation_allowed(preview.uri))
        self.assertFalse(preview.navigation_allowed("file:///etc/passwd"))

    def test_media_scripts_have_bounded_numeric_actions(self):
        script = helper.media_script("seek", 12.5)
        self.assertIn("const v=12.5;", script)
        self.assertIn("m.currentTime=", script)
        self.assertIn("JSON.stringify", helper.media_script("status"))
        for action, value in (("exec", 0), ("volume", float("nan")), ("seek", "alert(1)")):
            with self.subTest(action=action, value=value), self.assertRaises(ValueError):
                helper.media_script(action, value)

    def test_probe_has_no_gtk_init_or_window_and_reports_partial_dependencies(self):
        modules = {name: MagicMock() for name in ("Gtk", "Gdk", "GdkX11", "GLib", "Gio", "cairo", "Poppler")}
        output = io.StringIO()
        with patch.object(helper, "load_bindings", return_value=(modules, {"WebKit2": "missing"})), \
                patch.object(helper, "Preview") as preview, contextlib.redirect_stdout(output):
            self.assertEqual(helper.run(["--probe"]), 0)
        report = json.loads(output.getvalue())
        self.assertEqual(report["kinds"], ["pdf"])
        self.assertTrue(report["requires_x11"])
        self.assertFalse(report["gui_verified"])
        self.assertFalse(report["media_codecs_verified"])
        self.assertEqual(modules["Gtk"].mock_calls, [])
        self.assertEqual(modules["Gdk"].mock_calls, [])
        preview.assert_not_called()

    def test_missing_gi_probe_is_honest_and_valid_status_is_line_bounded(self):
        self.assertEqual(helper.capabilities({}, {"gi": "missing"})["kinds"], [])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            helper.emit({"state": "ready", "source": "中文"})
            helper.emit({"source": "x" * helper.MAX_LINE})
        lines = output.getvalue().splitlines()
        self.assertEqual(json.loads(lines[0])["source"], "中文")
        self.assertEqual(json.loads(lines[1])["state"], "error")
        self.assertTrue(all(len(line.encode()) < helper.MAX_LINE for line in lines))

    def test_jsonl_reader_handles_fragmentation_malformed_command_and_eof(self):
        preview = helper.Preview.__new__(helper.Preview)
        preview.GLib = types.SimpleNamespace(IO_ERR=8)
        preview.buffer, preview.closed = bytearray(), False
        commands, reports = [], []
        preview.command = commands.append
        preview.status = lambda **values: reports.append(values)
        preview.close = lambda: setattr(preview, "closed", True)
        preview.fail = lambda error: self.fail(str(error))
        read_fd, write_fd = os.pipe()
        self.addCleanup(os.close, read_fd)
        self.addCleanup(lambda: os.close(write_fd) if write_fd is not None else None)
        os.set_blocking(read_fd, False)
        os.write(write_fd, b'{"type":"action","action":"status"}\nnot-json\n{"type":')
        self.assertTrue(preview.stdin_ready(read_fd, 1))
        self.assertEqual(commands, [{"type": "action", "action": "status", "value": 0}])
        self.assertEqual(len(reports), 1)
        self.assertIn("protocol_error", reports[0])
        os.write(write_fd, b'"close"}\n')
        self.assertTrue(preview.stdin_ready(read_fd, 1))
        self.assertEqual(commands[-1], {"type": "close"})
        os.close(write_fd)
        write_fd = None
        self.assertFalse(preview.stdin_ready(read_fd, 16))
        self.assertTrue(preview.closed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
