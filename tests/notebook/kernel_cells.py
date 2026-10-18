#!/usr/bin/env python3
"""One live kernel-selection/cell-edit workflow; no user editor or env changes."""
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
    with tempfile.TemporaryDirectory(prefix="glow-kernel-cells-") as temporary:
        work = Path(temporary)
        notebook = work / "selection.ipynb"
        nbformat.write(nbformat.v4.new_notebook(
            metadata={"kernelspec": {"name": "python3", "language": "python", "display_name": "Python 3"}},
            cells=[nbformat.v4.new_code_cell("a = 6\na * 7", metadata={"tags": ["original-a"]}, execution_count=7,
                        outputs=[nbformat.v4.new_output("execute_result", data={"text/plain": "36"}, execution_count=7)]),
                   nbformat.v4.new_code_cell("99", metadata={"tags": ["original-b"]}, execution_count=8,
                        outputs=[nbformat.v4.new_output("execute_result", data={"text/plain": "99"}, execution_count=8)])]), notebook)
        manifest, init = work / "rplugin.vim", work / "init.lua"
        init.write_text("\n".join([
            "vim.g.mapleader=' '; vim.o.hidden=true",
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / plugin)) + ")"
              for plugin in ["molten-nvim", "nvim-treesitter", "jupytext.nvim"]],
            "package.loaded['which-key']={add=function(spec) _G.kernel_test_group=spec end}",
            "require('config.media.runtime').configure_molten()",
            "require('config.media.runtime').configure_jupytext()",
            "require('config.media.notebook_edit').setup()",
            "vim.ui.select=function(items,opts,callback) _G.kernel_test_items=items;_G.kernel_test_select=callback end",
        ]))
        env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
        subprocess.run(["nvim", "--headless", "-i", "NONE", "-n", "-u", str(init), "+UpdateRemotePlugins", "+qa"],
                       env=env, check=True, timeout=20, capture_output=True, text=True)
        previous = os.environ.get("NVIM_RPLUGIN_MANIFEST")
        os.environ["NVIM_RPLUGIN_MANIFEST"] = str(manifest)
        editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-i", "NONE", "-n", "-u", str(init)])
        try:
            def lua(code, *args):
                return editor.exec_lua(code, *args)

            def wait(predicate, description):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(.1)
                raise AssertionError(description + ": " + editor.command_output("messages"))

            def cells():
                return lua("return require('config.media.notebook_edit').cells(0)")

            def select_cell(index):
                cell = cells()[index]
                editor.current.window.cursor = (max(cell["first"], cell["header"]), 0)

            def output():
                return str([mark[3].get("virt_lines", []) for mark in editor.api.buf_get_extmarks(buf, -1, 0, -1, {"details": True})])

            assert lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            buf = editor.current.buffer.number
            mappings = {item["lhs"] for item in editor.api.buf_get_keymap(buf, "n")}
            assert {" jk", " jr", " jA", " jo", " ji", " j00", " ja", " jb", " jm", " jy", " jdd"} <= mappings, mappings
            assert not {"a", "b", "m", "y", "dd"} & mappings
            assert lua("return kernel_test_group[1].group") == "Jupyter Notebook"
            editor.command("GlowNotebookKernel")
            wait(lambda: lua("return kernel_test_items ~= nil"), "kernel discovery")
            items = lua("return kernel_test_items")
            base = next(item for item in items if item["executable"] == str(Path.home() / "miniconda3/bin/python"))
            assert base["name"] == "python3" and "ipykernel" in base["display_name"]
            assert editor.funcs.MoltenRunningKernels() == [], "picker opened a kernel"
            lua("kernel_test_select(nil)")
            assert editor.funcs.MoltenRunningKernels() == [], "picker cancel opened a kernel"
            # A real explicit choice starts our isolated kernel.
            lua("for _,item in ipairs(kernel_test_items) do if item.name=='glow-python' then kernel_test_select(item);break end end")
            wait(lambda: lua("return require('config.media.notebook_edit').status().ready"), "isolated ready")
            select_cell(0)
            editor.command("GlowNotebookRun")
            wait(lambda: "42" in output() and "Done" in output(), "isolated result")
            old = lua("return require('config.media.notebook_edit').status().kernel")
            # Switch owned kernel, preserving new outputs without implicitly saving source.
            lua("kernel_test_select(...)", base)
            wait(lambda: lua("return require('config.media.notebook_edit').status().ready"), "Conda base ready")
            wait(lambda: "42" in output(), "switch preserved completed output")
            current = lua("return require('config.media.notebook_edit').status()")
            assert current["kernel"] != old and current["environment"] == base["executable"]
            assert old not in editor.funcs.MoltenRunningKernels()
            assert nbformat.read(notebook, 4).cells[0].outputs[0].data["text/plain"] == "36", "switch saved source implicitly"
            # Confirm the selected alias executes the actual Conda interpreter.
            select_cell(0)
            lua("require('config.media.notebook_edit').add('code')")
            row = editor.current.window.cursor[0]
            editor.api.buf_set_lines(buf, row - 1, row, False, ["import sys", "sys.executable"])
            editor.command("GlowNotebookRun")
            wait(lambda: base["executable"] in output(), "actual selected interpreter")
            lua("require('config.media.notebook_edit').delete_cell()")
            assert base["executable"] not in output(), "deleted output drifted"
            # Add above/below; convert only the selected cell; undo a deletion.
            select_cell(0)
            lua("require('config.media.notebook_edit').add('code','above')")
            editor.current.buffer[editor.current.window.cursor[0] - 1] = "above = 1"
            lua("require('config.media.notebook_edit').add('code')")
            editor.current.buffer[editor.current.window.cursor[0] - 1] = "below = 2"
            lua("require('config.media.notebook_edit').convert_cell('markdown')")
            assert [cell["kind"] for cell in cells()] == ["code", "markdown", "code", "code"]
            lua("require('config.media.notebook_edit').convert_cell('code')")
            before = editor.current.buffer[:]
            editor.command("GlowNotebookDeleteCell")
            assert len(cells()) == 3
            editor.command("undo")
            assert editor.current.buffer[:] == before, "u did not restore cell source"
            editor.command("GlowNotebookDeleteCell")
            editor.command("write")
            saved = nbformat.read(notebook, 4)
            assert [cell.source for cell in saved.cells] == ["above = 1", "a = 6\na * 7", "99"], saved.cells
            assert saved.cells[1].metadata.tags == ["original-a"]
            assert saved.cells[2].metadata.tags == ["original-b"]
            # Delete a cell with completed output; the other output stays put.
            select_cell(1)
            editor.command("GlowNotebookDeleteCell")
            assert "42" not in output() and "99" in output(), output()
            editor.command("write")
            saved = nbformat.read(notebook, 4)
            assert [cell.source for cell in saved.cells] == ["above = 1", "99"]
            assert saved.cells[1].metadata.tags == ["original-b"]
            assert saved.cells[1].outputs[0].data["text/plain"] == "99"
            editor.command("bwipeout!")
            wait(lambda: editor.funcs.MoltenRunningKernels() == [], "owned kernel cleanup")
            assert lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            assert len(cells()) == 2
            print(json.dumps({"picker_without_start": True, "conda_base": base["executable"], "switch_preserved_output": 42,
                              "cell_add_convert_delete_undo_save_reopen": "passed", "other_cell_metadata_and_output": 99,
                              "normal_keys_preserved": True}))
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
