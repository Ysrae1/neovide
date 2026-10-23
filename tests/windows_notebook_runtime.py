#!/usr/bin/env python3
"""Native Windows Molten execution and PNG round-trip, using owned fixtures only."""
import argparse
import base64
from io import BytesIO
import json
import os
import shutil
import traceback
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import nbformat
import psutil
import pynvim
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--nvim', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    record = {'status': 'failed', 'python': sys.executable, 'native_image_pixels': 'not_checked_headless'}
    owned, editor, work = [], None, None
    environment = dict(os.environ)
    try:
        with tempfile.TemporaryDirectory(prefix='glow-arm64-notebook-', ignore_cleanup_errors=True) as temporary:
            work = Path(temporary)
            manifest = work / 'rplugin.vim'
            init = work / 'init.lua'
            init.write_text('\n'.join([
                'vim.opt.rtp:prepend(' + json.dumps(args.config.resolve().as_posix()) + ')',
                *['vim.opt.rtp:append(' + json.dumps((args.data / 'lazy' / plugin).resolve().as_posix()) + ')'
                  for plugin in ['molten-nvim', 'nvim-treesitter', 'jupytext.nvim']],
                'vim.g.python3_host_prog = ' + json.dumps(Path(sys.executable).as_posix()),
                'require("config.media.runtime").configure_molten()',
                'vim.api.nvim_create_autocmd("User", {pattern="MoltenKernelReady", callback=function() vim.g.glow_test_ready=true end})',
            ]), encoding='utf-8')
            env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest), PYTHONNOUSERSITE='1', PYTHONUTF8='1',
                       JUPYTER_PATH=str(args.data / 'glow-notebook-venv/share/jupyter'))
            for key in ('PYTHONHOME', 'PYTHONPATH', 'PYTHONSTARTUP'):
                env.pop(key, None)
            for key, name in [('JUPYTER_DATA_DIR', 'data'), ('JUPYTER_RUNTIME_DIR', 'runtime'),
                              ('JUPYTER_CONFIG_DIR', 'config'), ('IPYTHONDIR', 'ipython'), ('MPLCONFIGDIR', 'matplotlib')]:
                directory = work / name
                directory.mkdir()
                env[key] = str(directory)
            (work / 'data/runtime').mkdir()
            args.report.parent.mkdir(parents=True, exist_ok=True)
            registration = subprocess.run([str(args.nvim), '--headless', '-i', 'NONE', '-n', '-u', str(init),
                                           '+UpdateRemotePlugins', '+qa'], env=env, capture_output=True, timeout=60)
            (args.report.parent / 'live-register.log').write_bytes(registration.stdout + registration.stderr)
            assert registration.returncode == 0 and 'MoltenInit' in manifest.read_text(encoding='utf-8'), 'rplugin registration failed'
            os.environ.clear()
            os.environ.update(env)
            editor = pynvim.attach('child', argv=[str(args.nvim), '--embed', '--headless', '-i', 'NONE', '-n', '-u', str(init)])
            process = psutil.Process(editor.funcs.getpid())
            owned.append(process)
            calculation = 'import time\ntime.sleep(0.6)\n6 * 7'
            error = "raise ValueError('glow expected error')"
            image_code = "from IPython.display import display\nfrom PIL import Image\ndisplay(Image.new('RGB', (7, 5), (20, 80, 140)))"
            editor.current.buffer[:] = ['# %%', *calculation.splitlines(), '', '# %%', error, '', '# %%', *image_code.splitlines(), '']
            editor.current.buffer.options['filetype'] = 'python'
            editor.command('MoltenInit glow-python')

            def wait_until(predicate, label, timeout=30):
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(0.1)
                raise AssertionError(label + ': ' + editor.command_output('messages'))

            def output_text():
                return str([mark[3].get('virt_lines', []) for mark in editor.api.buf_get_extmarks(0, -1, 0, -1, {'details': True})])

            wait_until(lambda: editor.eval("get(g:, 'glow_test_ready', v:false)"), 'kernel readiness')
            owned.extend(process.children(recursive=True))
            editor.funcs.MoltenEvaluateRange('glow-python', 2, 4, 1, len('6 * 7') + 1)
            start = time.monotonic()
            assert editor.exec_lua('return 6 * 7') == 42
            response = time.monotonic() - start
            assert response < 0.5, f'editor blocked for {response:.3f}s'
            wait_until(lambda: '42' in output_text(), 'calculation output')
            editor.funcs.MoltenEvaluateRange('glow-python', 7, 7, 1, len(error) + 1)
            wait_until(lambda: 'glow expected error' in output_text(), 'error output')
            editor.funcs.MoltenEvaluateRange('glow-python', 10, 12, 1, len(image_code.splitlines()[-1]) + 1)
            notebook = work / '中文 fixture output.ipynb'
            nbformat.write(nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell(code) for code in [calculation, error, image_code]]), notebook)

            def exported_image():
                editor.command('MoltenExportOutput! ' + editor.funcs.fnameescape(str(notebook)) + ' glow-python')
                saved = nbformat.read(notebook, 4)
                return saved if saved.cells[2].outputs and 'image/png' in saved.cells[2].outputs[0].get('data', {}) else None

            saved = None
            def image_ready():
                nonlocal saved
                saved = exported_image()
                return saved is not None
            wait_until(image_ready, 'PNG output export')
            assert saved.cells[0].outputs[0].data['text/plain'] == '42'
            assert saved.cells[1].outputs[0].ename == 'ValueError'
            decoded = base64.b64decode(saved.cells[2].outputs[0].data['image/png'])
            image = Image.open(BytesIO(decoded))
            assert image.size == (7, 5) and image.convert('RGB').getpixel((0, 0)) == (20, 80, 140)
            assert [cell.execution_count for cell in saved.cells] == [1, 2, 3]
            (args.report.parent / 'computed-output.ipynb').write_bytes(notebook.read_bytes())
            (args.report.parent / 'computed-output.png').write_bytes(decoded)
            editor.command('MoltenDeinit')
            assert editor.funcs.MoltenRunningKernels() == []
            record.update(status='passed', provider=True, rplugin=True, result=42, expected_error='ValueError',
                          execution_counts=[1, 2, 3], editor_response_seconds=round(response, 4),
                          png_mime_export={'size': [7, 5], 'pixel': [20, 80, 140], 'bytes': len(decoded)},
                          kernel_list_after_deinit=[])
    except Exception as error:
        record['error'] = repr(error)
        record['traceback'] = traceback.format_exc()
    finally:
        if editor is not None:
            try:
                owned.extend(psutil.Process(editor.funcs.getpid()).children(recursive=True))
                editor.command('qa!')
            except (EOFError, OSError, psutil.Error):
                pass
        unique = {process.pid: process for process in owned}
        _, alive = psutil.wait_procs(list(unique.values()), timeout=10)
        cleanup = []
        for process in alive:
            try:
                process.terminate()
                cleanup.append(process.pid)
            except psutil.NoSuchProcess:
                pass
        _, remaining = psutil.wait_procs(alive, timeout=5)
        record['owned_processes'] = sorted(unique)
        record['cleanup_terminated'] = cleanup
        record['owned_processes_remaining'] = [process.pid for process in remaining]
        if remaining:
            record.update(status='failed', cleanup_error='owned processes remained after cleanup')
        if work is not None:
            try:
                shutil.rmtree(work)
            except FileNotFoundError:
                pass
            except OSError as error:
                record['fixture_cleanup_error'] = repr(error)
        os.environ.clear()
        os.environ.update(environment)
        args.report.write_text(json.dumps(record, indent=2), encoding='utf-8')
        print(json.dumps(record))
    return 0 if record['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
