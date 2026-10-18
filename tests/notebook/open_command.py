#!/usr/bin/env python3
"""Notebook user-command Ex escapes; literal backslashes remain authoritative."""
import json
import os
import tempfile
from pathlib import Path

import nbformat
import pynvim


def main():
    root = Path(__file__).resolve().parents[2]
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"
    with tempfile.TemporaryDirectory(prefix="glow-open-command-") as temporary:
        work = Path(temporary)
        escaped = work / "escaped notebook's $file.ipynb"
        literal = work / "literal\\ notebook's.ipynb"
        original = nbformat.v4.new_notebook(
            metadata={"kernelspec": {"name": "python3", "language": "python", "display_name": "Python 3"}},
            cells=[nbformat.v4.new_code_cell("42")])
        for path in [escaped, literal]:
            nbformat.write(original, path)
        init = work / "init.lua"
        init.write_text("\n".join([
            "vim.g.loaded_remote_plugins=''; vim.g.mapleader=' '; vim.o.hidden=true",
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            "vim.opt.rtp:append(" + json.dumps(str(data / "lazy/jupytext.nvim")) + ")",
            "require('config.media.runtime').configure_jupytext()",
            "require('config.media.notebook_edit').setup()",
        ]))
        editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-i", "NONE", "-n", "-u", str(init)])
        try:
            resolved = editor.exec_lua("return require('config.media.notebook_edit').resolve_path(...)", str(literal))
            assert Path(resolved) == literal.resolve()
            editor.command("GlowNotebook " + editor.funcs.fnameescape(str(escaped)))
            assert Path(editor.current.buffer.name) == escaped.resolve(), editor.command_output("messages")
            assert any(line == "42" for line in editor.current.buffer[:])
            title = editor.current.window.options["winbar"]
            assert " ␣jk" in title and "↑ [c" in title and "↓ ]c" in title and "GlowNotebookMenuValue# ␣j" in title
            assert escaped.name not in title and "Shift+Enter" not in title
            editor.command("bwipeout!")
            editor.command("GlowNotebook " + str(escaped))
            assert Path(editor.current.buffer.name) == escaped.resolve()
            assert nbformat.read(escaped, 4).cells[0].source == "42"
            assert nbformat.read(literal, 4).cells[0].source == "42"
            print(json.dumps({"fnameescape_user_command": "passed", "raw_space_apostrophe_dollar": "passed",
                              "literal_backslash_resolution": "preserved", "files_unchanged": True}))
        finally:
            try:
                editor.command("qa!")
            except (EOFError, OSError):
                pass


if __name__ == "__main__":
    main()
