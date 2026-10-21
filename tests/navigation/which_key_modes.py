#!/usr/bin/env python3
"""Real operator-pending and Visual renderer checks in one owned embedded child.

Run with existing notebook Python (pynvim), GLOW_TEST_CONFIG=/path/to/config.
Does not attach to a user session or use the OS clipboard.
"""
import json
import os
from pathlib import Path
import shutil
import tempfile
import time

import pynvim

with tempfile.TemporaryDirectory(prefix="glow-which-modes-") as temporary:
    original = os.environ.copy()
    for kind in ("STATE", "CACHE", "DATA"):
        os.environ[f"XDG_{kind}_HOME"] = temporary + "/" + kind.lower()
    os.environ["GLOW_TEST_STATE"] = temporary
    child = pynvim.attach("child", argv=[shutil.which("nvim"), "--embed", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n"])
    try:
        child.exec_lua(Path(__file__).with_suffix(".lua").read_text())
        audit = child.exec_lua("return GlowModes.audit()")
        results = []

        def wait_mode(expected):
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                actual = child.api.get_mode()["mode"]
                if (expected == "o" and "o" in actual) or actual == expected:
                    return
                time.sleep(0.01)
            raise AssertionError((expected, actual))

        for mode, enter in (("o", "d"), ("x", "v")):
            child.input("<Esc>")
            child.input(enter)
            wait_mode(mode if mode == "o" else "v")
            for prefix in ("", "a", "i"):
                samples = [child.exec_lua("return GlowModes.render(...)", mode, prefix, lang) for lang in ("en", "zh", "en")]
                assert samples[0]["rows"] == samples[2]["rows"], (mode, prefix, "not reversible")
                for row in samples[1]["rows"]:
                    if row["original"]:
                        assert row["desc"] != row["original"], (mode, prefix, row)
                        assert row["desc"] in samples[1]["rendered"], ("not actually drawn", row)
                results.append({"mode": mode, "prefix": prefix, "items": len(samples[1]["rows"]), "actual": samples[1]["actual_mode"]})
            child.input("<Esc>")
            wait_mode("n")

        for prefix in ('"', "'", " a", " r"):
            samples = [child.exec_lua("return GlowModes.render(...)", "n", prefix, lang) for lang in ("en", "zh", "en")]
            assert samples[0]["rows"] == samples[2]["rows"]
            if prefix == '"':
                for row in samples[1]["rows"]:
                    if row["keys"][-1:] in ("+", "*", "0", "a", "/"):
                        assert row["value"] in ("Start of line", "Prev word", "Remote Flash", "Find Files"), row
            if prefix == "'":
                for row in samples[1]["rows"]:
                    assert row.get("value") == row.get("original_value"), "mark file/line contents translated"
                    if row["original"].startswith("file: "):
                        assert row["desc"] == "文件：" + row["original"][6:]
            if prefix == " a":
                assert "Avante AI功能" in samples[1]["title"]
                assert "Avante AI功能" not in samples[0]["title"] and "Avante" in samples[0]["title"]
            if prefix == " r":
                assert "重命名功能" in samples[1]["title"] and "Renaming" in samples[0]["title"]
            results.append({"mode": "n", "prefix": prefix, "items": len(samples[1]["rows"])})
        child.exec_lua('vim.g.clipboard={name="OSC 52"}')
        osc = child.exec_lua('return GlowModes.render("n", [["]], "zh")')
        for row in osc["rows"]:
            if row["keys"][-1:] in ("+", "*"):
                assert row["value"].startswith("已检测到 OSC 52")
        print("PASS real operator-pending and Visual WhichKey windows en/zh/en; all pinned presets/provider descriptions, register values untouched: " + json.dumps({"audit": audit, "menus": results}, ensure_ascii=False))
    finally:
        try:
            child.command("qa!")
        except (EOFError, OSError):
            pass
        child.close()
        os.environ.clear()
        os.environ.update(original)
