#!/usr/bin/env python3
"""Repeatable Glow checks; defaults to isolated, offline headless Lua tests."""

import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
HEADLESS = (
    "media/capsule_backgrounds.lua",
    "media/glass_controls.lua",
    "media/highlight_roles.lua",
    "media/image_title.lua",
    "media/image_transport.lua",
    "media/notebook_book.lua",
    "media/open_spec.lua",
    "media/popup_materials.lua",
    "media/preview_spec.lua",
    "media/preview_fairness.lua",
    "notebook/output_highlights.lua",
    "notebook/output_scroll.lua",
    "notebook/title_capsules.lua",
)


def run(argv, *, env=None, timeout=None):
    print("+ " + " ".join(map(str, argv)), flush=True)
    process = subprocess.Popen(argv, cwd=ROOT, env=env, start_new_session=os.name != "nt")
    try:
        code = process.wait(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        # Only this check's process group is ours to stop (including fixtures).
        if os.name != "nt":
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            if os.name != "nt":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
            process.wait()
        raise
    if code:
        raise RuntimeError(f"check exited with status {code}")


def config_root(value):
    if value == "portable":
        result = ROOT / "portable/payload/nvim"
    elif value == "local":
        if os.name == "nt":
            result = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "nvim"
        else:
            result = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "nvim"
    else:
        result = Path(value).expanduser().resolve()
    if not (result / "lua/config/media").is_dir():
        raise RuntimeError(f"not a Glow nvim config: {result}")
    return result


def headless(args):
    nvim = shutil.which(args.nvim)
    if not nvim:
        raise RuntimeError(f"Neovim executable missing: {args.nvim}")
    count = 0
    for selected in args.config or ["portable"]:
        config = config_root(selected)
        print(f"\nHeadless config: {config}", flush=True)
        for test in HEADLESS:
            with tempfile.TemporaryDirectory(prefix="glow-check-") as temporary:
                work = Path(temporary)
                env = os.environ.copy()
                for name in ("LUA_PATH", "LUA_CPATH", "LUA_INIT", "VIMINIT", "EXINIT"):
                    env.pop(name, None)
                for kind in ("CONFIG", "DATA", "STATE", "CACHE"):
                    directory = work / kind.lower()
                    directory.mkdir()
                    env[f"XDG_{kind}_HOME"] = str(directory)
                # Neovim uses LOCALAPPDATA for these locations on Windows.
                env["LOCALAPPDATA"] = str(work / "data")
                env["NVIM_LOG_FILE"] = str(work / "nvim.log")
                env["GLOW_TEST_CONFIG"] = str(config)
                env["GLOW_TEST_PYTHON"] = sys.executable
                run([
                    nvim, "--headless", "--noplugin", "-u", "NONE", "-i", "NONE",
                    "--cmd", "lua vim.opt.rtp = {vim.env.GLOW_TEST_CONFIG, vim.env.VIMRUNTIME}",
                    "-l", str(ROOT / "tests" / test),
                ], env=env, timeout=args.timeout)
                count += 1
    print(f"\nPASS: {count} isolated headless checks", flush=True)


def rust(args):
    if not shutil.which("cargo"):
        raise RuntimeError("cargo is missing; prepare the Rust toolchain separately")
    run(["cargo", "fmt", "--all", "--", "--check"])
    target = ["--target", args.target] if args.target else []
    for name in args.rust_filter or [None]:
        command = ["cargo", "test", "--release", "--locked", "--offline", *target]
        if name:
            command.append(name)
        run(command)
    if args.clippy:
        run(["cargo", "clippy", "--all-targets", "--locked", "--offline", *target, "--", "-D", "warnings"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", nargs="?", choices=("headless", "rust", "all"), default="headless")
    parser.add_argument("--config", action="append", help="portable (default), local, or config path; repeat to check both")
    parser.add_argument("--nvim", default="nvim", help="Neovim executable (0.12+)")
    parser.add_argument("--timeout", type=float, default=60, help="seconds per headless test (default: 60)")
    parser.add_argument("--target", help="Rust target triple; default: host")
    parser.add_argument("--rust-filter", action="append", help="Rust test name filter; repeat for targeted checks")
    parser.add_argument("--clippy", action="store_true", help="also run installed clippy; never installs it")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    try:
        if args.suite in ("headless", "all"):
            headless(args)
        if args.suite in ("rust", "all"):
            rust(args)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
