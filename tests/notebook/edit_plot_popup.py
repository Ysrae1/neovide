#!/usr/bin/env python3
"""Live Molten Matplotlib output popup, with native image RPC mocked.

Checks real embedded Neovim window lifecycle and native adapter geometry. This
is not a Neovide pixel/Metal rendering check.
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
    with tempfile.TemporaryDirectory(prefix="glow-notebook-popup-") as temporary:
        work = Path(temporary)
        notebook = work / "plot.ipynb"
        code = "import matplotlib.pyplot as plt\nplt.plot([0, 1, 2], [1, 3, 2])\nplt.show()"
        nbformat.write(nbformat.v4.new_notebook(metadata={"kernelspec": {"name": "python3", "language": "python", "display_name": "Python 3"}},
                                               cells=[nbformat.v4.new_code_cell(code)]), notebook)
        manifest, init = work / "rplugin.vim", work / "init.lua"
        init.write_text("\n".join([
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / plugin)) + ")"
              for plugin in ["molten-nvim", "nvim-treesitter", "jupytext.nvim"]],
            "vim.g.neovide_native_image=true; vim.g.neovide_channel_id=9999",
            "_calls={};vim.rpcnotify=function(_,m,...)table.insert(_calls,{m,...});return true end",
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
        editor.ui_attach(120, 50, rgb=True)
        try:
            def wait_until(predicate, description):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if predicate(): return
                    time.sleep(.1)
                raise AssertionError(description + ": " + editor.command_output("messages"))

            assert editor.exec_lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            source = editor.current.buffer.number
            cell = editor.exec_lua("return require('config.media.notebook_edit').cells(0)[1]")
            editor.current.window.cursor = (cell["first"], 0)
            editor.command("GlowNotebookRun")
            wait_until(lambda: "Done" in str(editor.api.buf_get_extmarks(source, -1, 0, -1, {"details": True})), "Matplotlib completion")
            editor.command("GlowNotebookOutput")
            editor.command("redraw")
            wait_until(lambda: len(editor.api.tabpage_list_wins(0)) == 2, "output float creation")
            wait_until(lambda: any(call[0] == "neovide.image.show" for call in editor.exec_lua("return _calls")), "native image show")
            output_win = next(win for win in editor.api.tabpage_list_wins(0) if editor.api.win_get_buf(win).number != source)
            assert editor.api.win_get_config(output_win)["relative"] != ""
            time.sleep(.3)
            assert editor.api.win_is_valid(output_win), "output float closed immediately"
            calls = editor.exec_lua("return _calls")
            show = next(call for call in reversed(calls) if call[0] == "neovide.image.show")
            assert show[2]["overlay"] is True
            # Molten near the bottom of the editor can only allocate a short
            # float. Native padding must refit instead of hiding the whole plot.
            editor.api.win_set_config(output_win, {"relative": "editor", "row": 35, "col": 0, "width": 110, "height": 12})
            editor.command("redraw")
            editor.exec_lua("require('config.media.molten_images').refresh()")
            wait_until(lambda: any(call[0] == "neovide.image.show" and call[2]["height"] <= 10 for call in editor.exec_lua("return _calls")), "short float refit")
            short = next(call for call in reversed(editor.exec_lua("return _calls")) if call[0] == "neovide.image.show")
            assert short[2]["height"] <= 10
            editor.api.win_close(output_win, True)
            wait_until(lambda: any(call[0] == "neovide.image.close" for call in editor.exec_lua("return _calls")), "image release")
            editor.command("MoltenDeinit")
            print(json.dumps({"matplotlib": "Done", "native_output_float": "remains open", "overlay_geometry": show[2], "12_row_float_image_height": short[2]["height"], "close_releases_image": True}))
        finally:
            try: editor.command("qa!")
            except (EOFError, OSError): pass
            if previous is None: os.environ.pop("NVIM_RPLUGIN_MANIFEST", None)
            else: os.environ["NVIM_RPLUGIN_MANIFEST"] = previous


if __name__ == "__main__":
    main()
