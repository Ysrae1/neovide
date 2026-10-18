#!/usr/bin/env python3
"""Real Yazi converter paths all enter one native ya.image_show bridge.

Uses the parent GUI fixtures without changing them. Native Neovide RPC is
mocked; Yazi's PDF/ImageMagick/FFmpeg/font converters and cache files are real.
"""
import json
import os
import shutil
import tempfile
import time
from pathlib import Path

import pynvim
from PIL import Image


def main():
    root = Path(__file__).resolve().parents[2]
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"
    fixtures = Path(os.environ.get("GLOW_YAZI_FIXTURES", "/tmp/neovide-glow-formats-qa/files"))
    names = ["01 image.png", "02 document.pdf", "03 vector.svg", "04 video.mp4", "05 font.ttf", "06 image.avif"]
    with tempfile.TemporaryDirectory(prefix="glow-yazi-image-show-") as temporary:
        work = Path(temporary)
        files, home = work / "files", work / "user-config"
        files.mkdir(); home.mkdir(); (home / "plugins").mkdir()
        for name in names: shutil.copyfile(fixtures / name, files / name)
        custom = files / "07 custom.glow-test"
        custom.write_text("custom non-image source\n")
        text = files / "99 text.txt"
        text.write_text("ordinary text preview\n")
        user_home = Path.home() / ".config/yazi"
        content = (user_home / "yazi.toml").read_text()
        assert "prepend_previewers" not in content
        content = content.replace("[plugin]", '[plugin]\nprepend_previewers = [{ url = "*.glow-test", run = "glow-test-preview --label=preserved" }]', 1)
        (home / "yazi.toml").write_text(content)
        for plugin in (user_home / "plugins").iterdir():
            (home / "plugins" / plugin.name).symlink_to(plugin)
        plugin = home / "plugins/glow-test-preview.yazi"
        plugin.mkdir()
        Image.new("RGB", (80, 60), (170, 90, 205)).save(home / "custom-cover.png")
        (plugin / "main.lua").write_text('''local show = ya.image_show
local M = {}
function M:peek(job)
  assert(job.args.label == "preserved", "previewer args were lost")
  local cache = ya.file_cache(job)
  assert(fs.copy(Url(os.getenv("YAZI_CONFIG_HOME") .. "/custom-cover.png"), cache))
  local rect, err = show(cache, job.area)
  assert(rect.x == job.area.x and rect.w > 0 and rect.w <= job.area.w and rect.h < job.area.h and err == nil, "actual Rect/error convention changed")
  ya.preview_widget(job, ui.Text("custom metadata beneath image"):area(ui.Rect {x=job.area.x,y=job.area.y+rect.h,w=job.area.w,h=job.area.h-rect.h}))
end
function M:seek() end
return M
''')
        init = work / "init.lua"
        init.write_text("\n".join([
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / plugin)) + ")" for plugin in ["plenary.nvim", "yazi.nvim"]],
            "vim.g.neovide_native_image=true;vim.g.neovide_channel_id=9999;_calls={};_events={}",
            "vim.rpcnotify=function(_,m,...)table.insert(_calls,{m,...});return true end",
            "vim.api.nvim_create_autocmd('User',{pattern='YaziDDSCustom',callback=function(e)table.insert(_events,e.data)end})",
            "_opts=require('config.media.yazi').configure({config_home=" + json.dumps(str(home)) + ",hooks={on_yazi_ready=function(_,_,api)_api=api end}})",
            "require('yazi').setup(_opts)",
        ]))
        editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-i", "NONE", "-n", "-u", str(init)])
        editor.ui_attach(120, 50, rgb=True)
        results = {}
        try:
            def statuses():
                result = editor.exec_lua("return require('config.media.yazi').status()")
                return [value for value in (result.values() if isinstance(result, dict) else result) if value is not None]

            def wait_until(predicate, description, seconds=20):
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    if predicate(): return
                    time.sleep(.1)
                details = editor.exec_lua("return {status=require('config.media.yazi').status(),calls=_calls,events=_events,lines=vim.api.nvim_buf_get_lines(0,0,-1,false)}")
                raise AssertionError(description + ": " + str(details) + "\n" + editor.command_output("messages"))

            def selected(path, previous=None):
                state = statuses()
                return bool(state and state[0].get("source") == str(path) and state[0].get("id") and state[0].get("id") != previous)

            editor.exec_lua("require('yazi').yazi(nil,...)", str(files / names[0]))
            owner = editor.current.window.handle
            terminal = editor.current.buffer.number
            for index, name in enumerate([*names, custom.name]):
                source = files / name
                if index: editor.exec_lua("_api:reveal(...)", str(source))
                wait_until(lambda: selected(source), name + " native image")
                state = statuses()[0]
                rendered = Path(state["path"])
                assert rendered.is_file(), rendered
                with Image.open(rendered) as image:
                    results[name] = {"native_id": state["id"], "format": image.format, "size": list(image.size), "converted_cache": rendered != source}
                if source.suffix == ".pdf":
                    previous, cached = state["id"], state["path"]
                    editor.exec_lua("_api:emit_to_yazi({'seek','1'})")
                    wait_until(lambda: selected(source, previous), "PDF original seek")
                    assert statuses()[0]["path"] != cached, "PDF seek reused old page cache"
                    results[name]["original_seek"] = "new cached page"
                if source.suffix == ".glow-test":
                    label = "custom metadata beneath image"
                    wait_until(lambda: any(label in line for line in editor.api.buf_get_lines(terminal, 0, -1, False)), "custom metadata text")
                    lines = editor.api.buf_get_lines(terminal, 0, -1, False)
                    metadata_line = next(i + 1 for i, line in enumerate(lines) if label in line)
                    text_position = editor.funcs.screenpos(owner, metadata_line, 1)
                    show = next(call for call in reversed(editor.exec_lua("return _calls")) if call[0] == "neovide.image.show" and call[1] == state["id"])
                    assert show[2]["row"] + show[2]["height"] <= text_position["row"] - 1, (show, text_position)
                    results[name]["metadata_below_native_rect"] = True
            editor.exec_lua("_api:reveal(...)", str(text))
            wait_until(lambda: all("id" not in state for state in statuses()), "text leaves no native pixels")
            assert (home / "yazi.toml").read_text() == content
            overlay = Path(editor.exec_lua("return _opts.config_home"))
            editor.exec_lua("_api:emit_to_yazi({'quit'})")
            wait_until(lambda: not editor.api.win_is_valid(owner), "Yazi close")
            wait_until(lambda: not overlay.exists(), "private config cleanup")
            print(json.dumps({"image_show_matrix": results, "text_cleanup": True, "user_rules_and_args": "preserved", "private_overlay": "removed"}))
        finally:
            try: editor.command("qa!")
            except (EOFError, OSError): pass


if __name__ == "__main__": main()
