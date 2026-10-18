#!/usr/bin/env python3
"""Native Notebook edit/run/save smoke in an isolated embedded Neovim session.

Run with ~/.local/share/nvim/glow-notebook-venv/bin/python. Requires the pinned
Notebook plugins, installed runtime and Python Treesitter parser.
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
    with tempfile.TemporaryDirectory(prefix="glow notebook edit ") as temporary:
        work = Path(temporary)
        notebook = work / "native notebook's result.ipynb"
        companion = notebook.with_suffix(".py")
        companion.write_text("USER COMPANION: do not change or delete\n")
        original = nbformat.v4.new_notebook(
            metadata={"kernelspec": {"name": "python3", "language": "python", "display_name": "Python 3"},
                      "glow_preserved": {"owner": "user", "version": 17}},
            cells=[
                nbformat.v4.new_markdown_cell("# Native Notebook\n\nPreserved Markdown.", metadata={"tags": ["keep-markdown"]}),
                nbformat.v4.new_code_cell("a = 6\na * 6", metadata={"tags": ["keep-code"]}, execution_count=7,
                                          outputs=[nbformat.v4.new_output("execute_result", data={"text/plain": "36"}, execution_count=7)]),
                nbformat.v4.new_code_cell("raise ValueError('native expected error')"),
                nbformat.v4.new_code_cell("99", execution_count=8,
                                          outputs=[nbformat.v4.new_output("execute_result", data={"text/plain": "99"}, execution_count=8)]),
            ],
        )
        nbformat.write(original, notebook)
        manifest, init = work / "rplugin.vim", work / "init.lua"
        init.write_text("\n".join([
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / plugin)) + ")"
              for plugin in ["molten-nvim", "nvim-treesitter", "jupytext.nvim"]],
            "require('config.media.runtime').configure_molten()",
            "require('config.media.runtime').configure_jupytext()",
            "require('config.media.notebook_edit').setup()",
            "vim.o.hidden=true",
        ]))
        env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
        subprocess.run(["nvim", "--headless", "-i", "NONE", "-n", "-u", str(init),
                        "+UpdateRemotePlugins", "+qa"], env=env, check=True, timeout=20, capture_output=True, text=True)
        previous = os.environ.get("NVIM_RPLUGIN_MANIFEST")
        os.environ["NVIM_RPLUGIN_MANIFEST"] = str(manifest)
        editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-i", "NONE", "-n", "-u", str(init)])
        try:
            def wait_until(predicate, description):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if predicate(): return
                    time.sleep(.1)
                raise AssertionError(description + ": " + editor.command_output("messages"))

            def output_text():
                return str([mark[3].get("virt_lines", []) for mark in editor.api.buf_get_extmarks(buf, -1, 0, -1, {"details": True})])

            assert editor.exec_lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            buf = editor.current.buffer.number
            assert editor.funcs.MoltenRunningKernels() == [], "opening launched kernel"
            assert editor.current.buffer.options["filetype"] == "python"
            cells = editor.exec_lua("return require('config.media.notebook_edit').cells(0)")
            assert [cell["kind"] for cell in cells] == ["markdown", "code", "code", "code"], cells
            arithmetic = cells[1]
            editor.api.buf_set_lines(buf, arithmetic["last"] - 1, arithmetic["last"], False, ["a * 7"])
            editor.current.window.cursor = (arithmetic["first"], 0)
            editor.command("GlowNotebookRun")  # Starts + waits + imports + runs, no separate manual initialization.
            wait_until(lambda: "42" in output_text() and "Done" in output_text(), "first-run result")
            cells = editor.exec_lua("return require('config.media.notebook_edit').cells(0)")
            editor.current.window.cursor = (cells[2]["first"], 0)
            editor.command("GlowNotebookRun")
            wait_until(lambda: "[Error] ValueError: native expected error" in output_text(), "error output")
            editor.command("write")
            saved = nbformat.read(notebook, 4)
            assert saved.metadata.glow_preserved == original.metadata.glow_preserved
            assert saved.cells[0].source == original.cells[0].source
            assert saved.cells[0].metadata.tags == ["keep-markdown"]
            assert saved.cells[1].source == "a = 6\na * 7"
            assert saved.cells[1].metadata.tags == ["keep-code"]
            assert saved.cells[1].outputs[0].data["text/plain"] == "42", (saved.cells, editor.command_output("messages"))
            assert saved.cells[2].outputs[0].ename == "ValueError", saved.cells
            assert saved.cells[3].outputs[0].data["text/plain"] == "99", saved.cells
            assert companion.read_text() == "USER COMPANION: do not change or delete\n"
            editor.command("GlowNotebookAddMarkdown")
            assert editor.current.buffer.options["modified"]
            editor.current.buffer[editor.current.window.cursor[0] - 1] = "# Added native Markdown."
            editor.command("write")
            saved = nbformat.read(notebook, 4)
            assert any(cell.cell_type == "markdown" and cell.source == "Added native Markdown." for cell in saved.cells)
            # A second unrelated kernel must survive closing our Notebook.
            editor.command("new")
            editor.command("MoltenInit glow-python")
            unrelated = editor.funcs.MoltenRunningKernels(True)[0]
            editor.command("buffer " + str(buf))
            editor.command("bdelete " + str(buf))
            wait_until(lambda: editor.funcs.MoltenRunningKernels() == [unrelated], "owned kernel release")
            editor.command("MoltenDeinit")
            assert editor.funcs.MoltenRunningKernels() == []
            assert companion.read_text() == "USER COMPANION: do not change or delete\n"
            print(json.dumps({"edit_and_run": 42, "error": "ValueError", "saved_output": 99,
                              "metadata_and_markdown": "preserved", "new_markdown": "saved", "space_and_apostrophe_path": "passed",
                              "unrelated_kernel": "retained", "kernels_after_cleanup": []}))
        finally:
            try: editor.command("qa!")
            except (EOFError, OSError): pass
            if previous is None: os.environ.pop("NVIM_RPLUGIN_MANIFEST", None)
            else: os.environ["NVIM_RPLUGIN_MANIFEST"] = previous


if __name__ == "__main__":
    main()
