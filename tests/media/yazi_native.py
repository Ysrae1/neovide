#!/usr/bin/env python3
"""Actual Yazi events + embedded Neovim native-preview lifecycle (RPC mocked)."""
import json
import os
import tempfile
import time
import sys
import tomllib
from pathlib import Path

import pynvim
from PIL import Image


def main():
    root = Path(__file__).resolve().parents[2]
    data = Path(os.environ["GLOW_TEST_DATA"]) if os.environ.get("GLOW_TEST_DATA") else Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"
    with tempfile.TemporaryDirectory(prefix="glow-yazi-native-") as temporary:
        work = Path(temporary)
        files = work / "files"
        files.mkdir()
        picture = files / "a native picture's $.png"
        Image.new("RGB", (96, 64), (30, 145, 200)).save(picture)
        second = files / "b another image.png"
        Image.new("RGB", (64, 96), (200, 90, 30)).save(second)
        text = files / "c plain.txt"
        text.write_text("normal text preview\n")
        navigation = "--navigation-only" in sys.argv
        if navigation:
            for name in ["a-directory", "b-directory"]:
                (files / name).mkdir()
            (files / "a-directory" / "inner.txt").write_text("directory navigation\n")
        config_home = work / "user yazi's config"
        config_home.mkdir()
        original_config = "[mgr]\nratio=[1,4,3]\n[preview]\nimage_delay=0\n"
        (config_home / "yazi.toml").write_text(original_config)
        (config_home / "init.lua").write_text("-- User configuration must remain untouched.\n")
        init = work / "init.lua"
        init.write_text("\n".join([
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / plugin)) + ")"
              for plugin in ["plenary.nvim", "yazi.nvim"]],
            "vim.g.neovide_native_image=true;vim.g.neovide_channel_id=9999;_calls={};_events={}",
            "vim.env.NO_COLOR=nil;vim.env.TERM='xterm-256color';vim.env.COLORTERM='truecolor'" if navigation else "",
            "vim.rpcnotify=function(_,m,...)table.insert(_calls,{m,...});return true end",
            "vim.api.nvim_create_autocmd('User',{pattern='YaziDDSCustom',callback=function(e)table.insert(_events,e.data)end})",
            "vim.api.nvim_create_autocmd('User',{pattern='YaziDDSHover',callback=function(e)_hover=e.data.url end})" if navigation else "",
            "_opts=require('config.media.yazi').configure({config_home=" + json.dumps(str(config_home)) + ",hooks={on_yazi_ready=function(_,_,api)_api=api end}})",
            "require('yazi').setup(_opts)",
        ]))
        editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-i", "NONE", "-n", "-u", str(init)])
        editor.ui_attach(120, 50, rgb=True)
        try:
            def wait_until(predicate, description, seconds=12):
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    if predicate(): return
                    time.sleep(.1)
                details = editor.exec_lua("return {status=require('config.media.yazi').status(),calls=_calls,events=_events,lines=vim.api.nvim_buf_get_lines(0,0,-1,false)}")
                raise AssertionError(description + ": " + str(details) + "\n" + editor.command_output("messages"))

            def statuses():
                result = editor.exec_lua("return require('config.media.yazi').status()")
                return [value for value in (result.values() if isinstance(result, dict) else result) if value is not None]

            if navigation:
                editor.exec_lua("require('yazi').yazi(nil,...)", str(files))
                wait_until(lambda: bool(editor.exec_lua("return table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\\n'):find('c plain.txt',1,true)~=nil")), "directory list ready")
                terminal = editor.current.buffer.number
                owner_win = editor.current.window.handle
                assert editor.funcs.mode() == "t", "Yazi must receive terminal input"
                editor.input("j")
                wait_until(lambda: editor.exec_lua("return _hover") == str(files / "b-directory"), "j next directory")
                editor.input("k")
                wait_until(lambda: editor.exec_lua("return _hover") == str(files / "a-directory"), "k previous directory")
                editor.input("l")
                wait_until(lambda: str(files / "a-directory") in editor.current.buffer[0], "l enter directory")
                editor.input("h")
                wait_until(lambda: editor.exec_lua("return _hover") == str(files / "a-directory"), "h parent directory")
                overlay = Path(editor.exec_lua("return _opts.config_home"))
                rules = tomllib.loads((overlay / "yazi.toml").read_text())["plugin"]["previewers"]
                assert next(rule for rule in rules if rule.get("url") == "*/")["run"] == "folder"
                assert any(rule["run"].startswith("neovide-glow-native-preview.") for rule in rules if rule.get("mime") == "image/*")
                editor.input("G")
                wait_until(lambda: editor.exec_lua("return _hover") == str(text), "G final text file")
                editor.input("\r")
                wait_until(lambda: not editor.api.win_is_valid(owner_win) and Path(editor.current.buffer.name).resolve() == text.resolve(), "Enter opens chosen file")
                assert editor.current.buffer[:] == ["normal text preview"]
                assert (config_home / "yazi.toml").read_text() == original_config
                print(json.dumps({"real_yazi_terminal_mode": "t", "hjkl_and_enter": "passed", "file_open": "passed", "folder_sync_preview": "original", "image_previewer_wrappers": "preserved", "user_config": "preserved"}))
                return

            editor.exec_lua("require('yazi').yazi(nil,...)", str(picture))
            wait_until(lambda: any(call[0] == "neovide.image.show" for call in editor.exec_lua("return _calls")), "initial image show")
            terminal = editor.current.buffer.number
            owner_win = editor.current.window.handle
            calls = editor.exec_lua("return _calls")
            show = next(call for call in reversed(calls) if call[0] == "neovide.image.show")
            first_id = show[1]
            assert first_id >= 2000000 and show[2]["overlay"]
            status = statuses()[0]
            assert status["source"] == str(picture)
            assert status["region"]["w"] == show[2]["width"]
            # Real Yazi popup layer: rename opens its own dialog inside the
            # terminal, rather than a Neovim floating window.
            editor.exec_lua("_api:emit_to_yazi({'rename'})")
            wait_until(lambda: any(call[0] == "neovide.image.close" and call[1] == first_id for call in editor.exec_lua("return _calls")), "rename popup suppression")
            editor.exec_lua("vim.api.nvim_chan_send(vim.bo[...].channel, string.char(3))", terminal)
            wait_until(lambda: any(call[0] == "neovide.image.load" and call[1] != first_id for call in editor.exec_lua("return _calls")), "popup dismiss restoration")
            editor.exec_lua("_api:reveal(...)", str(second))
            wait_until(lambda: any(value.get("source") == str(second) and "id" in value for value in statuses()), "second image selection")
            editor.exec_lua("_api:reveal(...)", str(text))
            wait_until(lambda: all("id" not in value for value in statuses()), "non-image release")
            assert (config_home / "yazi.toml").read_text() == original_config
            overlay = editor.exec_lua("return _opts.config_home")
            assert Path(overlay).exists()
            editor.exec_lua("_api:emit_to_yazi({'quit'})")
            wait_until(lambda: not editor.api.win_is_valid(owner_win), "Yazi close")
            wait_until(lambda: not Path(overlay).exists(), "private overlay cleanup")
            assert (config_home / "yazi.toml").read_text() == original_config
            print(json.dumps({"real_yazi_events": "passed", "native_geometry": show[2], "internal_modal": "hidden/restored",
                              "image_selection": "updated", "non_image": "released", "user_config": "preserved", "private_overlay": "removed"}))
        finally:
            try: editor.command("qa!")
            except (EOFError, OSError): pass


if __name__ == "__main__":
    main()
