#!/usr/bin/env python3
"""Real Snacks picker confirmation followed by actual Neovim mapping input.

Checks mode/source safety and readable navigation descriptions, not CUA text
injection or Neovide pixels. Uses its own embedded editor and real Conda kernel.
"""
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

import nbformat
import pynvim


def main():
    root = Path(__file__).resolve().parents[2]
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"
    with tempfile.TemporaryDirectory(prefix="glow-picker-mode-") as temporary:
        work = Path(temporary)
        notebook = work / "picker.ipynb"
        nbformat.write(nbformat.v4.new_notebook(
            metadata={"kernelspec": {"name": "python3", "language": "python", "display_name": "Python 3"}},
            cells=[nbformat.v4.new_markdown_cell("# Mode test"), nbformat.v4.new_code_cell("6 * 7"),
                   nbformat.v4.new_code_cell("def later_function():\n    return 1")]), notebook)
        manifest, init = work / "rplugin.vim", work / "init.lua"
        init.write_text("\n".join([
            "vim.g.mapleader=' '; vim.o.hidden=true; vim.o.timeoutlen=1000",
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / plugin)) + ")"
              for plugin in ["molten-nvim", "nvim-treesitter", "jupytext.nvim", "snacks.nvim"]],
            "filetype_plugin = true; vim.cmd('filetype plugin on')",
            "vim.keymap.set('n',']l','<cmd>lnext<cr>')",
            "vim.api.nvim_create_autocmd('FileType',{pattern='python',callback=function() _G.original_python_mapping=vim.fn.maparg('][','n',false,true) end})",
            "require('snacks').setup({picker={enabled=true,ui_select=true}})",
            "require('config.media.runtime').configure_molten()",
            "require('config.media.runtime').configure_jupytext()",
            "require('config.media.notebook_edit').setup()",
        ]))
        env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
        subprocess.run(["nvim", "--headless", "-i", "NONE", "-n", "-u", str(init), "+UpdateRemotePlugins", "+qa"],
                       env=env, check=True, timeout=20, capture_output=True, text=True)
        previous = os.environ.get("NVIM_RPLUGIN_MANIFEST")
        os.environ["NVIM_RPLUGIN_MANIFEST"] = str(manifest)
        editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-i", "NONE", "-n", "-u", str(init)])
        editor.ui_attach(150, 45, rgb=True)
        try:
            def lua(code, *args):
                return editor.exec_lua(code, *args)

            def wait(predicate, description):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(.05)
                raise AssertionError(description + ": " + editor.command_output("messages"))

            assert lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            source = editor.current.buffer.number
            original = editor.current.buffer[:]
            first_cell = lua("return require('config.media.notebook_edit').cells(0)[1]")
            editor.current.window.cursor = (first_cell["header"], 0)
            python_before = lua("return original_python_mapping")
            python_after = editor.funcs.maparg("][", "n", False, True)
            assert python_before["rhs"] == python_after["rhs"] and python_before["sid"] == python_after["sid"]
            assert python_after["desc"] == "下一个 Python 顶层定义结尾"
            location = editor.funcs.maparg("]l", "n", False, True)
            assert location["rhs"] == "<cmd>lnext<cr>" and location["desc"] == "下一条位置列表结果"
            winbar = editor.current.window.options["winbar"]
            assert "SELECT ␣jk" in winbar and "GlowNotebookMenuValue# ␣j" in winbar and "<Leader>" not in winbar
            assert notebook.name not in winbar and "Shift+Enter" not in winbar
            assert editor.api.get_mode()["mode"] == "n"
            editor.command("GlowNotebookKernel")
            wait(lambda: lua("return #Snacks.picker.get({source='select'}) == 1"), "real Snacks selector")
            wait(lambda: editor.api.get_mode()["mode"] == "i", "real picker input mode")
            editor.input("miniconda3")
            wait(lambda: lua("local p=Snacks.picker.get({source='select'})[1]; local i=p and p:current(); return i and i.item and i.item.executable:find('/miniconda3/',1,true) ~= nil"), "base filter")
            editor.input("\r")
            wait(lambda: editor.current.buffer.number == source and lua("return require('config.media.notebook_edit').status().ready"), "base selected and ready")
            returned_mode = editor.api.get_mode()["mode"]
            assert returned_mode == "n", f"picker returned {returned_mode}"
            assert editor.current.buffer[:] == original
            assert not editor.current.buffer.options["modified"]
            # Use Neovim key input, not a native automation paste/typeText API.
            start_row = editor.current.window.cursor[0]
            for key in ["]", "c"]:
                editor.input(key)
            wait(lambda: editor.current.window.cursor[0] != start_row, "normal ]c navigation")
            for key in [" ", "j", "r"]:
                editor.input(key)
            def output():
                return str([mark[3].get("virt_lines", []) for mark in editor.api.buf_get_extmarks(source, -1, 0, -1, {"details": True})])
            wait(lambda: "42" in output() and "Done" in output(), "normal leader-j-r run")
            assert editor.api.get_mode()["mode"] == "n" and editor.current.buffer[:] == original
            assert not editor.current.buffer.options["modified"]
            for key in ["]", "m"]:
                editor.input(key)
            wait(lambda: "later_function" in editor.current.line, "original Python navigation behavior")
            print(json.dumps({"real_snacks_confirmation_mode": returned_mode, "normal_key_run": 42,
                              "source_unchanged": True, "python_mapping_rhs_sid": "preserved",
                              "navigation_descriptions": "readable", "title_leader": "space"}))
        finally:
            try:
                editor.command("qa!")
            except (EOFError, OSError):
                pass
            if previous is None:
                os.environ.pop("NVIM_RPLUGIN_MANIFEST", None)
            else:
                os.environ["NVIM_RPLUGIN_MANIFEST"] = previous


if __name__ == "__main__":
    main()
