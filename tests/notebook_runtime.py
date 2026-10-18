#!/usr/bin/env python3
"""Focused live Molten smoke: async execution, error, export, and kernel cleanup.

Run with ~/.local/share/nvim/glow-notebook-venv/bin/python after installing the
runtime. Uses an isolated remote-plugin manifest; no user editor is contacted.
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
    root = Path(__file__).resolve().parents[1]
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"
    with tempfile.TemporaryDirectory(prefix="glow-notebook-runtime-") as temporary:
        work = Path(temporary)
        manifest = work / "rplugin.vim"
        init = work / "init.lua"
        init.write_text("\n".join([
            "vim.opt.rtp:prepend(" + json.dumps(str(root / "portable/payload/nvim")) + ")",
            *["vim.opt.rtp:append(" + json.dumps(str(data / "lazy" / plugin)) + ")"
              for plugin in ["molten-nvim", "nvim-treesitter", "jupytext.nvim"]],
            "require('config.media.runtime').configure_molten()",
            "vim.api.nvim_create_autocmd('User', {pattern='MoltenKernelReady', callback=function() vim.g.glow_test_ready=true end})",
        ]))
        env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
        subprocess.run(["nvim", "--headless", "-i", "NONE", "-n", "-u", str(init),
                        "+UpdateRemotePlugins", "+qa"], env=env, check=True, timeout=20,
                       capture_output=True, text=True)
        previous = os.environ.get("NVIM_RPLUGIN_MANIFEST")
        os.environ["NVIM_RPLUGIN_MANIFEST"] = str(manifest)
        editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-i", "NONE", "-n", "-u", str(init)])
        try:
            calculation = "import time\ntime.sleep(0.6)\n6 * 7"
            error = "raise ValueError('glow expected error')"
            editor.current.buffer[:] = ["# %%", *calculation.splitlines(), "", "# %%", error, ""]
            editor.current.buffer.options["filetype"] = "python"
            editor.command("MoltenInit glow-python")

            def wait_until(predicate, description):
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(0.1)
                raise AssertionError(description + ": " + editor.command_output("messages"))

            def output_text():
                marks = editor.api.buf_get_extmarks(0, -1, 0, -1, {"details": True})
                return str([mark[3].get("virt_lines", []) for mark in marks])

            # Running before this event can make Jupyter's readiness probe
            # consume a first result. The UI uses the same explicit ready gate.
            wait_until(lambda: editor.eval("get(g:, 'glow_test_ready', v:false)"), "kernel readiness")
            editor.funcs.MoltenEvaluateRange("glow-python", 2, 4, 1, len("6 * 7") + 1)
            start = time.monotonic()
            assert editor.exec_lua("return 6 * 7") == 42
            response = time.monotonic() - start
            assert response < 0.5, f"editor blocked during cell: {response:.3f}s"
            wait_until(lambda: "42" in output_text() and "Done" in output_text(), "calculation output")
            editor.funcs.MoltenEvaluateRange("glow-python", 7, 7, 1, len(error.encode()) + 1)
            wait_until(lambda: "[Error] ValueError: glow expected error" in output_text(), "error output")
            notebook = work / "output.ipynb"
            nbformat.write(nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell(calculation), nbformat.v4.new_code_cell(error)]), notebook)
            editor.command("MoltenExportOutput! " + editor.funcs.fnameescape(str(notebook)) + " glow-python")
            saved = nbformat.read(notebook, 4)
            assert saved.cells[0].outputs[0].data["text/plain"] == "42"
            assert saved.cells[1].outputs[0].ename == "ValueError"
            assert [cell.execution_count for cell in saved.cells] == [1, 2]
            editor.command("MoltenDeinit")
            assert editor.funcs.MoltenRunningKernels() == []
            print(json.dumps({"result": 42, "error": "ValueError", "execution_counts": [1, 2], "editor_response_seconds": round(response, 4), "kernels_after_close": []}))
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
