#!/usr/bin/env python3
"""Real JPEG XL lossless codec round trip and embedded Yazi native preview."""
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

import pynvim
from PIL import Image


def main():
    root = Path(__file__).resolve().parents[2]
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"
    encoder = shutil.which("cjxl") or "/usr/local/bin/cjxl"
    decoder = shutil.which("djxl") or "/usr/local/bin/djxl"
    with tempfile.TemporaryDirectory(prefix="glow-yazi-jxl-") as temporary:
        work = Path(temporary)
        files, home = work / "files", work / "config"
        files.mkdir(); home.mkdir()
        png, jxl, back = work / "original.png", files / "01 real world's $ image.JxL", work / "round-trip.png"
        image = Image.new("RGBA", (256, 180))
        image.putdata([(x % 256, y % 256, (x + y) % 256, (x * 7 + y * 5) % 256) for y in range(180) for x in range(256)])
        image.save(png)
        subprocess.run([encoder, str(png), str(jxl), "--distance=0", "--effort=3", "--num_threads=1", "--quiet"], check=True, capture_output=True, timeout=20)
        subprocess.run([decoder, str(jxl), str(back), "--output_format=png", "--num_threads=1", "--bits_per_sample=8", "--quiet"], check=True, capture_output=True, timeout=20)
        restored = Image.open(back).convert("RGBA")
        assert restored.size == image.size and restored.tobytes() == image.tobytes(), "JXL lossless pixel round trip"
        mime_only = files / "02 content.bin"
        shutil.copyfile(jxl, mime_only)
        broken = files / "03 bad.JXL"
        broken.write_text("invalid JPEG XL payload\n")
        text = files / "99 plain.txt"
        text.write_text("ordinary text\n")
        original = "[mgr]\nratio=[1,4,3]\n[preview]\nimage_delay=0\nmax_width=64\nmax_height=48\n"
        (home / "yazi.toml").write_text(original)
        init = work / "init.lua"
        init.write_text("\n".join([
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / name)) + ")" for name in ["plenary.nvim", "yazi.nvim"]],
            "vim.g.neovide_native_image=true;vim.g.neovide_channel_id=9999;_calls={};_events={}",
            "vim.rpcnotify=function(_,m,...)table.insert(_calls,{m,...});return true end",
            "_opts=require('config.media.yazi').configure({config_home=" + json.dumps(str(home)) + ",hooks={on_yazi_ready=function(_,_,api)_api=api end}})",
            "require('yazi').setup(_opts)",
        ]))
        editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-i", "NONE", "-n", "-u", str(init)])
        editor.ui_attach(120, 50, rgb=True)
        try:
            def states():
                result = editor.exec_lua("return require('config.media.yazi').status()")
                return [value for value in (result.values() if isinstance(result, dict) else result) if value is not None]

            def selected(path):
                result = states()
                return result and result[0].get("source") == str(path) and result[0].get("id")

            def wait_until(predicate, description, seconds=20):
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    if predicate(): return
                    time.sleep(.1)
                detail = editor.exec_lua("return {status=require('config.media.yazi').status(),calls=_calls,lines=vim.api.nvim_buf_get_lines(0,0,-1,false)}")
                raise AssertionError(description + ": " + str(detail) + "\n" + editor.command_output("messages"))

            editor.exec_lua("require('yazi').yazi(nil,...)", str(jxl))
            owner, terminal = editor.current.window.handle, editor.current.buffer.number
            wait_until(lambda: selected(jxl), "mixed-case special-character JXL")
            state = states()[0]
            cache = Path(state["path"])
            with Image.open(cache) as bounded:
                assert bounded.format == "PNG", bounded.format
                assert bounded.width <= 64 and bounded.height <= 48, bounded.size
                size = list(bounded.size)
            modified = cache.stat().st_mtime_ns
            editor.exec_lua("_api:reveal(...)", str(text))
            wait_until(lambda: all("id" not in state for state in states()), "switch releases JXL")
            editor.exec_lua("_api:reveal(...)", str(jxl))
            wait_until(lambda: selected(jxl), "JXL cache reuse")
            assert states()[0]["path"] == str(cache) and cache.stat().st_mtime_ns == modified
            editor.exec_lua("_api:reveal(...)", str(mime_only))
            wait_until(lambda: selected(mime_only), "image/jxl MIME without JXL extension")
            editor.exec_lua("_api:reveal(...)", str(broken))
            wait_until(lambda: all("id" not in state for state in states()) and any("JPEG XL" in line and "无效" in line for line in editor.api.buf_get_lines(terminal, 0, -1, False)), "bad JXL failure feedback")
            overlay = Path(editor.exec_lua("return _opts.config_home"))
            editor.exec_lua("_api:emit_to_yazi({'quit'})")
            wait_until(lambda: not editor.api.win_is_valid(owner), "Yazi close")
            wait_until(lambda: not overlay.exists(), "private temporary PNG cleanup")
            assert (home / "yazi.toml").read_text() == original
            print(json.dumps({"real_jxl_lossless_pixels": "identical", "encoded_bytes": jxl.stat().st_size,
                              "native_png_cache": size, "mixed_case_and_special_path": "passed", "mime_only": "passed",
                              "cache_reuse": "passed", "bad_jxl": "visible failure", "close_cleanup": "passed", "global_config": "untouched"}))
        finally:
            try: editor.command("qa!")
            except (EOFError, OSError): pass


if __name__ == "__main__": main()
