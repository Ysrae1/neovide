#!/usr/bin/env python3
"""Actual Yazi 26.5.6 output uses editor RGB colors despite opposite terminal mode.

Runs only temporary configs; the standalone Yazi config is never modified.
Python 3.11+, Neovim, and Yazi are required. PTY check requires Unix.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time
import tomllib

ROOT = Path(__file__).resolve().parents[2]
LOCAL = Path.home() / ".config/nvim"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def palette(config, background):
    path = config / ("lua/config/appearance/themes/ayu_" + background + "_customed.lua")
    lua = ("vim.g.neovide=true; local c=dofile(" + json.dumps(str(path)) + "); "
           "io.write(vim.json.encode({background=" + json.dumps(background) +
           ",ui=c.base_30,syntax=c.base_16})); vim.cmd('qa!')")
    result = subprocess.run(["nvim", "--headless", "-u", "NONE", "-l", "-"],
                            input=lua, text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def render(target, files, foreground, background):
    env = {**os.environ, "YAZI_CONFIG_HOME": str(target), "TERM": "xterm-256color", "COLORTERM": "truecolor"}
    env.pop("NO_COLOR", None)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 140, 0, 0))
    process = subprocess.Popen(["yazi", str(files)], stdin=slave, stdout=slave, stderr=slave, env=env)
    os.close(slave)
    output = b""
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                chunk = os.read(master, 65536)
                output += chunk
                if b"\x1b]11;?" in chunk:
                    # Deliberately report the opposite mode. Editor palette wins.
                    rgb = b"0000/0000/0000" if background == "light" else b"ffff/ffff/ffff"
                    os.write(master, b"\x1b]11;rgb:" + rgb + b"\x1b\\")
                if b"\x1b[0c" in chunk:
                    os.write(master, b"\x1b[?1;2c")
                if b"\x1b[16t" in chunk:
                    os.write(master, b"\x1b[6;16;8t")
                if b"readable.txt" in output:
                    break
        os.write(master, b"q")
        deadline = time.monotonic() + 3
        while process.poll() is None and time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                try:
                    output += os.read(master, 65536)
                except OSError:
                    break
        assert process.poll() is not None, repr(output[-5000:])
        assert process.returncode == 0, output[-2000:]
        rgb = [int(foreground[index:index + 2], 16) for index in (1, 3, 5)]
        color = ("38;2;" + ";".join(map(str, rgb))).encode()
        assert color in output and b"readable.txt" in output, output[-3000:]
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=3)
        os.close(master)


def main():
    with tempfile.TemporaryDirectory(prefix="glow-yazi-theme-") as directory:
        work = Path(directory)
        files = work / "files"
        files.mkdir()
        (files / "readable.txt").write_text("preview text\n")
        source = work / "standalone"
        shutil.copytree(ROOT / "portable/payload/yazi", source)
        (source / "glow-editor.tmTheme").write_text("standalone reserved-name fixture")
        original = {str(p.relative_to(source)): sha(p) for p in source.rglob("*") if p.is_file()}
        light = palette(LOCAL, "light")
        render(source, files, light["ui"]["white"], "dark")
        print("bundled light flavor PASS: actual Yazi output")
        for name, config in (("local", LOCAL), ("portable", ROOT / "portable/payload/nvim")):
            for background in ("light", "dark"):
                target = work / (name + "-" + background)
                (target / "plugins/neovide-glow-native-preview.yazi").mkdir(parents=True)
                # Lua normally links entries into the private config. Reproduce
                # that to catch accidental writes through to standalone theme.
                (target / "theme.toml").symlink_to(source / "theme.toml")
                (target / "glow-editor.tmTheme").symlink_to(source / "glow-editor.tmTheme")
                data = palette(config, background)
                palette_file = work / "palette.json"
                palette_file.write_text(json.dumps(data))
                bridge = config / "lua/config/media/yazi"
                shutil.copyfile(bridge / "neovide-glow-native-preview.yazi/main.lua",
                                target / "plugins/neovide-glow-native-preview.yazi/main.lua")
                subprocess.run([sys.executable, str(bridge / "overlay.py"), str(source), str(target),
                                str(bridge), str(palette_file)], check=True)
                theme = tomllib.loads((target / "theme.toml").read_text())
                assert theme["flavor"] == {"dark": "", "light": ""}
                assert theme["filetype"]["rules"][-1]["fg"] == data["ui"]["white"]
                assert theme["icon"] == tomllib.loads((source / "theme.toml").read_text())["icon"]
                code = plistlib.loads((target / "glow-editor.tmTheme").read_bytes())
                assert code["settings"][0]["settings"]["background"] == data["syntax"]["base00"]
                allowed = {color.lower() for table in (data["ui"], data["syntax"]) for color in table.values()}
                def colors(value):
                    if isinstance(value, dict):
                        for key, item in value.items():
                            if key in ("fg", "bg") and isinstance(item, str) and item.startswith("#"):
                                assert item.lower() in allowed, item
                            elif key != "icon":
                                colors(item)
                    elif isinstance(value, list):
                        for item in value:
                            colors(item)
                colors(theme)
                render(target, files, data["ui"]["white"], background)
                assert original == {str(p.relative_to(source)): sha(p) for p in source.rglob("*") if p.is_file()}
                print(name, background, "PASS: actual Yazi output, editor palette, opposite terminal mode, source untouched")


if __name__ == "__main__":
    main()
