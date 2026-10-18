#!/usr/bin/env python3
"""Real Molten RUNNING is the only source of a filled cell play label."""
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
    with tempfile.TemporaryDirectory(prefix="glow-label-state-") as temporary:
        work = Path(temporary)
        notebook = work / "labels.ipynb"
        nbformat.write(nbformat.v4.new_notebook(
            metadata={"kernelspec": {"name": "python3", "language": "python", "display_name": "Python 3"}},
            cells=[nbformat.v4.new_markdown_cell("# Labels"),
                   nbformat.v4.new_code_cell("import time\ntime.sleep(0.8)\nprint('Out[99]: ... Running')\n42"),
                   nbformat.v4.new_code_cell("raise ValueError('label expected error')")]), notebook)
        manifest, init = work / "rplugin.vim", work / "init.lua"
        init.write_text("\n".join([
            "vim.g.mapleader=' '; vim.o.hidden=true",
            "vim.g.neovide_native_notebook=true; vim.g.neovide_channel_id=9999",
            "_native_frames=0; vim.rpcnotify=function(_,method,...) if method=='neovide.notebook.frames' then _native_frames=_native_frames+1 end; return true end",
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / plugin)) + ")"
              for plugin in ["molten-nvim", "nvim-treesitter", "jupytext.nvim"]],
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
        editor.ui_attach(120, 45, rgb=True)
        try:
            assert editor.exec_lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            source = editor.current.buffer.number
            original = editor.current.buffer[:]

            def labels():
                return editor.exec_lua("""
                  local buf=...
                  local ret={}
                  for _,label in ipairs(require('config.media.notebook_edit').cell_labels(buf)) do
                    local text='';for _,chunk in ipairs(label.chunks) do text=text..chunk[1] end
                    -- Segment padding is presentation; status assertions use normalized spaces.
                    if label.cell.kind=='code' then ret[#ret+1]=text:gsub('%s+',' ') end
                  end
                  return ret
                """, source)

            def headers():
                return editor.exec_lua("""
                  local ns=vim.api.nvim_get_namespaces()['molten-extmarks']
                  local ret={}
                  if not ns then return ret end
                  for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(...,ns,0,-1,{details=true})) do
                    for _,line in ipairs(mark[4].virt_lines or {}) do
                      local text=''; for _,chunk in ipairs(line) do text=text..chunk[1] end
                      if not text:match('^%s*$') then
                        if text:match('^Out%[') then ret[#ret+1]=text end
                        break
                      end
                    end
                  end
                  return ret
                """, source)

            def wait(predicate, description):
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(.04)
                raise AssertionError(description + ": " + editor.command_output("messages"))

            assert len(labels()) == 2 and all("󰼛 󰘶󰌑" in label for label in labels())
            editor.command("GlowNotebookRunAll")
            wait(lambda: len(headers()) == 2 and "Running" in headers()[0] and "On Hold" in headers()[1], "running and queued")
            playing = labels()
            assert "󰐊 󰘶󰌑" in playing[0] and "󰼛 󰘶󰌑" in playing[1], (headers(), playing)
            # Native refresh observes Molten's exact output without rewriting
            # its virtual lines, and must preserve the real RUNNING label.
            stable_native_refresh = editor.exec_lua("""
              local buf=...
              local ui=require('config.media.notebook_ui')
              local edit=require('config.media.notebook_edit')
              local ns=vim.api.nvim_get_namespaces()['molten-extmarks']
              local original=vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{details=true})
              for _=1,3 do
                ui.refresh(); edit.refresh_labels(buf)
                assert(vim.deep_equal(original,vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{details=true})),
                  'native refresh changed Molten output marks')
                local filled=false
                for _,label in ipairs(edit.cell_labels(buf)) do
                  if label.index==2 and label.running then filled=true end
                end
                assert(filled,'native refresh reset real RUNNING label')
              end
              return _native_frames>0
            """, source)
            assert stable_native_refresh, "native frame refresh was not actually exercised"
            wait(lambda: len(headers()) == 2 and "Done" in headers()[0] and "Failed" in headers()[1], "done and error")
            finished = labels()
            assert all("󰼛 󰘶󰌑" in label for label in finished), (headers(), finished)
            assert editor.current.buffer[:] == original and not editor.current.buffer.options["modified"]
            editor.command("MoltenDeinit")
            assert editor.funcs.MoltenRunningKernels() == []
            print(json.dumps({"idle": "outline", "queued": "outline", "real_running": "filled",
                              "done": "outline", "error": "outline", "printed_running_text_ignored": True,
                              "stable_native_refresh": stable_native_refresh,
                              "type_icon_and_shift_enter": "preserved", "source_unchanged": True}))
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
