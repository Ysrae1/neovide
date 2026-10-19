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
            "vim.g.neovide_native_image=true; vim.g.neovide_native_notebook=true; vim.g.neovide_channel_id=9999",
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
        editor.ui_attach(120, 50, rgb=True, ext_multigrid=True)
        try:
            def wait_until(predicate, description):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if predicate(): return
                    time.sleep(.1)
                raise AssertionError(description + ": " + editor.command_output("messages"))

            assert editor.exec_lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            source = editor.current.buffer.number
            source_window = editor.current.window
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
            presentation = editor.api.win_get_config(output_win)
            assert presentation['relative'] == 'editor', 'output view stays at the measured source output position'
            assert presentation['border'] != 'none', 'invisible top/left padding aligns the original inline text'
            assert editor.current.window == output_win and not editor.current.buffer.options['modifiable']
            # The focused output buffer is not a source kernel buffer. Molten's
            # real periodic callback must leave this presentation alone rather
            # than racing its row/width/height back to its ordinary popup model.
            for _ in range(3):
                editor.funcs.MoltenTick(0)
                editor.command('redraw')
                assert editor.api.win_get_config(output_win) == presentation, 'MoltenTick changed expanded output geometry'
            frames = editor.exec_lua("return require('config.media.notebook_ui').refresh()")
            popup = next(frame for frame in frames if frame.get('overlay') and frame['kind'] == 'output')
            source_frame = editor.exec_lua("return require('config.media.notebook_ui').output_frame_geometry(...)",
                                           source_window.handle, source, 1)
            popup_origin = editor.api.win_get_position(output_win)
            assert abs(popup_origin[1] + popup['rect']['col'] - source_frame['rect']['col']) < 1e-6
            assert abs(popup['rect']['width'] - source_frame['rect']['width']) < 1e-6, 'green left/right outlines must align exactly'
            assert abs(popup_origin[0] + popup['rect']['row'] - source_frame['rect']['row']) < 1e-6, 'output expands from original joint'
            def assert_owner_bounds(frame, window):
                editor.command('redraw')
                editor.eval('1')  # Drain the UI notifications for this geometry.
                sizes, floating = {}, {}
                for message in editor._session._pending_messages:
                    if message[0] != 'notification' or message[1] != 'redraw':
                        continue
                    for event in message[2]:
                        if event[0] == 'grid_resize':
                            for grid, width, height in event[1:]: sizes[grid] = (width, height)
                        elif event[0] == 'win_float_pos':
                            for value in event[1:]: floating[int.from_bytes(value[1].data[1:], 'big')] = value
                owner = floating[window.handle]
                width, height = sizes[owner[0]]
                clip = frame['clip']
                origin = editor.api.win_get_position(window)
                # Native frame coordinates are owner-local; win_float_pos's
                # screen row/column are absolute. Compare in the same space.
                assert (origin[0] + clip['row'], origin[1] + clip['col'], clip['width'], clip['height']) == (owner[9], owner[10], width, height), (frame, owner, sizes)
            assert_owner_bounds(popup, output_win)
            # Also match an existing host's one-sided border exactly; content
            # bounds alone differ by one row and are rejected by the renderer.
            editor.api.win_set_config(output_win, {'border':['','━','','','','','','']})
            frames = editor.exec_lua("return require('config.media.notebook_ui').refresh()")
            assert_owner_bounds(next(frame for frame in frames if frame.get('overlay') and frame['kind'] == 'output'), output_win)
            editor.api.win_set_config(output_win, {'border':'none'})
            calls = editor.exec_lua("return _calls")
            show = next(call for call in reversed(calls) if call[0] == "neovide.image.show")
            assert show[2]["overlay"] is True
            # Shrinking the source editor leaves only a short area below the
            # original output seam. The viewer refits there, rather than moving
            # away from the cell or hiding the whole plot.
            editor.api.ui_try_resize(120, 21)
            editor.command("redraw")
            editor.exec_lua("require('config.media.molten_images').refresh()")
            def latest_image():
                return next(call for call in reversed(editor.exec_lua("return _calls")) if call[0] == "neovide.image.show")
            wait_until(lambda: latest_image()[2]["height"] <= 10, "short float refit")
            short = next(call for call in reversed(editor.exec_lua("return _calls")) if call[0] == "neovide.image.show")
            assert short[2]["height"] <= 10
            editor.api.win_close(output_win, True)
            wait_until(lambda: any(call[0] == "neovide.image.close" for call in editor.exec_lua("return _calls")), "image release")
            editor.command("MoltenDeinit")
            print(json.dumps({"matplotlib": "Done", "native_output_float": "remains open", "frame_matches_real_multigrid": True,
                              "three_molten_ticks_preserve_presentation": True, "source_outline_alignment": "exact",
                              "overlay_geometry": show[2], "12_row_float_image_height": short[2]["height"], "close_releases_image": True}))
        finally:
            # Only this isolated editor owns these kernel(s); do not address any
            # running user editor or its kernel processes.
            try:
                if 'source_window' in locals() and editor.api.win_is_valid(source_window):
                    editor.api.set_current_win(source_window)
                    editor.command('silent! MoltenDeinit')
            except (EOFError, OSError, pynvim.api.common.NvimError): pass
            try: editor.command("qa!")
            except (EOFError, OSError): pass
            if previous is None: os.environ.pop("NVIM_RPLUGIN_MANIFEST", None)
            else: os.environ["NVIM_RPLUGIN_MANIFEST"] = previous


if __name__ == "__main__":
    main()
