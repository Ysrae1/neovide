#!/usr/bin/env python3
"""Real owned kernel: output-only/hidden streaming edits are unsaved until :write.

Needs the Notebook venv (nbformat/pynvim), pinned Molten/Jupytext/Treesitter and
a Python kernel. Uses a temporary Notebook and remote-plugin manifest; never
opens a GUI or writes an existing document. GLOW_TEST_CONFIG selects a config.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

import nbformat
import pynvim


def main():
    root = Path(__file__).resolve().parents[2]
    config = Path(os.environ.get("GLOW_TEST_CONFIG", root / "portable/payload/nvim"))
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"
    with tempfile.TemporaryDirectory(prefix="glow output dirty ") as temporary:
        work = Path(temporary)
        notebook = work / "output-only.ipynb"
        code = 'import time\nprint("stream-first", flush=True)\ntime.sleep(1.2)\nprint("stream-last", flush=True)'
        document = nbformat.v4.new_notebook(
            metadata={"kernelspec": {"name": "python3", "language": "python", "display_name": "Python 3"}},
            cells=[nbformat.v4.new_code_cell(
                code,
                execution_count=4,
                outputs=[nbformat.v4.new_output("stream", name="stdout", text="saved output\n")],
            ), nbformat.v4.new_code_cell(
                code,
                execution_count=8,
                outputs=[nbformat.v4.new_output("stream", name="stdout", text="duplicate keep\n")],
            )],
        )
        nbformat.write(document, notebook)
        initial_disk = notebook.read_bytes()
        manifest, init = work / "rplugin.vim", work / "init.lua"
        init.write_text("\n".join([
            "vim.g.mapleader=' ';vim.o.hidden=true",
            "_dirty_messages={};vim.notify=function(msg)_dirty_messages[#_dirty_messages+1]=msg end",
            "vim.opt.rtp:prepend(" + json.dumps(str(config)) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / plugin)) + ")"
              for plugin in ("molten-nvim", "nvim-treesitter", "jupytext.nvim")],
            "require('config.media.runtime').configure_molten()",
            "require('config.media.runtime').configure_jupytext()",
            "require('config.media.notebook_edit').setup()",
        ]))
        environment = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
        subprocess.run(["nvim", "--headless", "-i", "NONE", "-n", "-u", str(init),
                        "+UpdateRemotePlugins", "+qa"], env=environment, check=True,
                       timeout=20, capture_output=True, text=True)
        previous = os.environ.get("NVIM_RPLUGIN_MANIFEST")
        os.environ["NVIM_RPLUGIN_MANIFEST"] = str(manifest)
        editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-i", "NONE", "-n", "-u", str(init)])
        try:
            editor.ui_attach(110, 34, rgb=True)

            def lua(code, *args):
                return editor.exec_lua(code, *args)

            def wait(predicate, description):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(.06)
                raise AssertionError(description + ": " + str(lua("return _dirty_messages"))
                                     + "\n" + editor.command_output("messages"))

            assert lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            buf = editor.current.buffer.number
            source = editor.current.buffer[:]
            changedtick = editor.api.buf_get_changedtick(buf)

            def modified():
                return lua("return vim.bo[...].modified", buf)

            def output():
                last = lua("return require('config.media.notebook_edit').cells(...)[1].last-1", buf)
                return str([mark[3].get("virt_lines", []) for mark in
                            editor.api.buf_get_extmarks(buf, -1, 0, -1, {"details": True}) if mark[1] <= last])

            def dirty():
                return lua("return require('config.media.notebook_dirty').status(...)", buf)

            def close_is_protected():
                result = lua("local ok,err=pcall(vim.cmd,{cmd='bdelete',args={tostring(...)}});return {ok,tostring(err)}", buf)
                assert not result[0] and ("E89" in result[1] or "E37" in result[1]), result
                assert editor.api.buf_is_loaded(buf), "close discarded unsaved output"

            assert not modified(), ("opening saved Notebook set modified", dirty(), lua("return _dirty_messages"))
            editor.command("GlowNotebookKernel glow-python")
            wait(lambda: lua("return require('config.media.notebook_edit').status().ready")
                 and "saved output" in output(), "saved output import")
            assert not modified() and not dirty()["dirty"], ("import marked an unchanged Notebook dirty", modified(), dirty(),
                lua("return _dirty_messages"))
            assert notebook.read_bytes() == initial_disk
            clean_revision = dirty()["revision"]
            editor.command("redraw!")
            editor.funcs.MoltenUpdateInterface()
            editor.command("enew")
            editor.command("buffer " + str(buf))
            assert not modified() and dirty()["revision"] == clean_revision, "repaint or buffer switch dirtied saved output"

            def run():
                editor.current.window.cursor = (lua("return require('config.media.notebook_edit').cells(0)[1].first"), 0)
                editor.command("GlowNotebookRun")

            run()
            wait(lambda: "stream-first" in output() and "Running" in output(), "first streaming chunk")
            assert modified() and dirty()["dirty"], "streaming output must immediately set modified"
            close_is_protected()
            wait(lambda: "stream-last" in output() and "Done" in output(), "completed output")
            assert editor.current.buffer[:] == source and editor.api.buf_get_changedtick(buf) == changedtick
            assert notebook.read_bytes() == initial_disk, "execution implicitly saved Notebook"
            editor.command("write")
            assert not modified() and not dirty()["dirty"], "successful output save left modified"
            saved = nbformat.read(notebook, 4)
            assert "stream-last" in str(saved.cells[0].outputs) and saved.cells[0].execution_count != 4
            assert saved.cells[1].outputs == document.cells[1].outputs
            assert saved.cells[1].execution_count == document.cells[1].execution_count

            # Virtual output can be hidden while execution continues. No
            # rendering callback should be required to notice its mutations.
            revision = dirty()["revision"]
            run()
            editor.command("MoltenToggleVirtual")
            wait(lambda: dirty()["revision"] > revision and modified(), "hidden output mutation")
            assert "stream-first" not in output(), "test output is still rendered"
            # The pinned provider polls the current buffer only. Switching
            # away must retain the unsaved state; consume later messages when
            # returning, without claiming background-kernel polling support.
            editor.command("enew")
            assert modified() and dirty()["dirty"]
            editor.command("buffer " + str(buf))
            wait(lambda: dirty()["revision"] > revision + 1, "hidden execution receives later chunks")
            editor.command("MoltenToggleVirtual")
            wait(lambda: "stream-last" in output() and "Done" in output(), "hidden execution completes")
            close_is_protected()

            # The source conversion can succeed while output export fails. Do
            # not let its nomodified reset silence the close protection.
            lua("_dirty_parser=vim.treesitter.get_string_parser;vim.treesitter.get_string_parser=function()error('controlled parser failure')end")
            result = lua("local ok,err=pcall(vim.cmd.wq);return {ok,tostring(err)}")
            assert not result[0] and "controlled parser failure" in result[1], result
            assert modified() and dirty()["dirty"], ("failed output export cleared unsaved state", modified(), dirty(),
                lua("return _dirty_messages"), lua("return require('config.media.notebook_edit').status()"))
            close_is_protected()
            lua("vim.treesitter.get_string_parser=_dirty_parser")
            editor.command("write")
            assert not modified() and not dirty()["dirty"]
            assert nbformat.read(notebook, 4).cells[0].execution_count > saved.cells[0].execution_count

            # An older save acknowledgement must never erase a newer output
            # notification or a newer source edit.
            lua("local d=require('config.media.notebook_dirty');local t=d.token(...);d.changed(...);assert(not d.saved(...,t));assert(vim.bo[...].modified)", buf)
            editor.command("write")
            assert not modified()

            # Identical source is deliberately repeated in the second cell.
            # Clear only the selected cell, then all, without touching source
            # text or letting the original content matcher clear its sibling.
            before_clear = notebook.read_bytes()
            editor.current.window.cursor = (lua("return require('config.media.notebook_edit').cells(0)[1].first"), 0)
            editor.funcs.MoltenOnCursorMoved()
            editor.command("MoltenDelete")
            assert modified() and dirty()["dirty"], "output removal did not mark Notebook dirty"
            assert editor.current.buffer[:] == source and notebook.read_bytes() == before_clear
            close_is_protected()
            old_kernel = lua("return require('config.media.notebook_edit').status().kernel")
            editor.command("GlowNotebookKernel python3")
            wait(lambda: lua("local s=require('config.media.notebook_edit').status();return s.ready and s.kernel~=...", old_kernel),
                 "pending output clear survives owned-kernel switch")
            wait(lambda: "duplicate keep" in str(editor.api.buf_get_extmarks(buf, -1, 0, -1, {"details": True})),
                 "kernel switch restores unchanged sibling")
            assert dirty()["dirty"] and modified() and notebook.read_bytes() == before_clear
            editor.command("write")
            cleared = nbformat.read(notebook, 4)
            assert cleared.cells[0].outputs == [] and cleared.cells[0].execution_count is None
            assert cleared.cells[1].outputs == document.cells[1].outputs
            assert cleared.cells[1].execution_count == document.cells[1].execution_count
            assert not modified() and not dirty()["dirty"]
            editor.command("MoltenDelete!")
            assert modified() and dirty()["dirty"]
            editor.command("write")
            assert all(not cell.outputs and cell.execution_count is None for cell in nbformat.read(notebook, 4).cells)
            assert not modified() and not dirty()["dirty"]
            editor.command("bwipeout")
            wait(lambda: editor.funcs.MoltenRunningKernels() == [], "owned kernel cleanup")

            # Source undo and output state use different histories. Returning
            # source text to its saved version must retain dirty output.
            scratch = lua("""
              local b=vim.api.nvim_create_buf(true,false)
              vim.api.nvim_set_current_buf(b)
              vim.api.nvim_buf_set_lines(b,0,-1,false,{'saved source'})
              vim.bo[b].modified=false
              require('config.media.notebook_dirty').attach(b)
              return b
            """)
            lua("vim.api.nvim_buf_set_lines(...,0,-1,false,{'new source'});require('config.media.notebook_dirty').changed(...)", scratch)
            editor.command("undo")
            wait(lambda: lua("return vim.bo[...].modified", scratch), "undo retains output dirty protection")
            lua("""
              local b=...
              local d=require('config.media.notebook_dirty');local t=d.token(b)
              vim.api.nvim_buf_set_lines(b,0,-1,false,{'even newer source'})
              assert(d.saved(b,t) and vim.bo[b].modified,'saved output erased newer source edits')
              d.detach(b);vim.api.nvim_buf_delete(b,{force=true})
            """, scratch)
            print(json.dumps({"import_clean": True, "streaming_and_hidden_output_dirty": True,
                              "source_and_disk_unchanged_before_save": True, "close_protected": True,
                              "successful_write_clean": True, "failed_export_stays_dirty": True,
                              "single_and_all_output_clear_saved": True, "duplicate_source_sibling_preserved": True,
                              "pending_clear_survives_kernel_switch": True,
                              "repaint_and_buffer_switch_stay_clean": True,
                              "newer_revision_preserved": True, "source_undo_and_newer_edits_preserved": True,
                              "owned_kernels_after_close": []}))
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
