#!/usr/bin/env python3
"""Real Molten: restoring output executes nothing; run submits only one cell."""
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

import nbformat
import pynvim


PROBE = '''
import pynvim
from jupyter_client.blocking import BlockingKernelClient

submissions = []
original = BlockingKernelClient.execute

def execute(self, code, *args, **kwargs):
    message_id = original(self, code, *args, **kwargs)
    submissions.append(dict(code=code, message_id=message_id))
    return message_id

BlockingKernelClient.execute = execute

@pynvim.function("GlowManualExecutionSubmissions", sync=True)
def submitted(_nvim, _args):
    return submissions
'''


def main():
    root = Path(__file__).resolve().parents[2]
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nvim'
    with tempfile.TemporaryDirectory(prefix="glow manual execution's ") as temporary:
        work = Path(temporary)
        notebook = work / 'three independent cells.ipynb'
        sentinels = [work / f'cell-{index}-executed.txt' for index in range(1, 4)]
        sources = ["from pathlib import Path\n"
                   f"Path({str(path)!r}).write_text('ONLY_CELL_{index}')\n"
                   f"'EXPLICIT_RESULT_{index}'" for index, path in enumerate(sentinels, 1)]
        nbformat.write(nbformat.v4.new_notebook(
            metadata={'kernelspec': {'name': 'python3', 'display_name': 'Python 3', 'language': 'python'}},
            cells=[nbformat.v4.new_code_cell(source, execution_count=100 + index,
                        outputs=[nbformat.v4.new_output('execute_result', execution_count=100 + index,
                                                       data={'text/plain': f'SAVED_ONLY_CELL_{index}'})])
                   for index, source in enumerate(sources, 1)]), notebook)
        original_disk = notebook.read_bytes()
        manifest, init, probe = work / 'rplugin.vim', work / 'init.lua', work / 'manual_execution_probe.py'
        probe.write_text(PROBE)
        init.write_text('\n'.join([
            "vim.g.mapleader=' ';vim.o.hidden=true",
            "_G.manual_test_notifications={};vim.notify=function(msg) manual_test_notifications[#manual_test_notifications+1]=msg end",
            'vim.opt.rtp:prepend(' + json.dumps(str(root / 'portable/payload/nvim')) + ')',
            *['vim.opt.rtp:append(' + json.dumps(str(data / 'lazy' / plugin)) + ')'
              for plugin in ['molten-nvim', 'nvim-treesitter', 'jupytext.nvim']],
            "require('config.media.runtime').configure_molten()",
            "require('config.media.runtime').configure_jupytext()",
            "require('config.media.notebook_edit').setup()",
            "vim.fn['remote#host#RegisterPlugin']('python3'," + json.dumps(str(probe))
            + ",{{type='function',name='GlowManualExecutionSubmissions',sync=1,opts=vim.empty_dict()}})",
        ]))
        env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
        subprocess.run(['nvim', '--headless', '-i', 'NONE', '-n', '-u', str(init), '+UpdateRemotePlugins', '+qa'],
                       env=env, check=True, timeout=20, capture_output=True, text=True)
        previous = os.environ.get('NVIM_RPLUGIN_MANIFEST')
        os.environ['NVIM_RPLUGIN_MANIFEST'] = str(manifest)
        editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-i', 'NONE', '-n', '-u', str(init)])
        try:
            editor.ui_attach(100, 30, rgb=True)

            def lua(code, *args):
                return editor.exec_lua(code, *args)

            def wait(predicate, description):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(.05)
                raise AssertionError(description + ': ' + str(lua('return manual_test_notifications')))

            def output_cells():
                return [str(mark[3]['virt_lines']) for mark in editor.api.buf_get_extmarks(buf, -1, 0, -1, {'details': True})
                        if mark[3].get('virt_lines')]

            def outputs():
                return '\n'.join(output_cells())

            def submissions():
                return editor.funcs.GlowManualExecutionSubmissions()

            assert lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            buf = editor.current.buffer.number
            source, changedtick = editor.current.buffer[:], editor.api.buf_get_changedtick(buf)
            assert editor.funcs.MoltenRunningKernels() == [], 'opening started a kernel'
            editor.command('GlowNotebookKernel glow-python')
            wait(lambda: lua("return require('config.media.notebook_edit').status().ready")
                 and all(f'SAVED_ONLY_CELL_{index}' in outputs() for index in range(1, 4)), 'saved outputs restored')
            assert submissions() == [], 'kernel selection/import submitted execute requests'
            assert not any(path.exists() for path in sentinels), 'kernel selection ran cell code'

            cells = lua("return require('config.media.notebook_edit').cells(0)")
            assert len(cells) == 3 and all(cell['kind'] == 'code' for cell in cells)
            editor.current.window.cursor = (cells[1]['first'], 0)
            editor.command('GlowNotebookRun')
            wait(lambda: sentinels[1].exists() and any('EXPLICIT_RESULT_2' in cell and 'Done' in cell for cell in output_cells()),
                 'explicit second cell itself completed')
            submitted = submissions()
            assert len(submitted) == 1 and submitted[0]['code'].strip() == sources[1], submitted
            assert submitted[0]['message_id'], 'probe did not observe a real kernel execute submission'
            assert [path.exists() for path in sentinels] == [False, True, False], 'single run executed a neighbor'
            assert sentinels[1].read_text() == 'ONLY_CELL_2'
            assert 'SAVED_ONLY_CELL_1' in outputs() and 'SAVED_ONLY_CELL_3' in outputs(), 'unrun saved outputs changed'
            assert editor.current.buffer[:] == source and editor.api.buf_get_changedtick(buf) == changedtick
            assert notebook.read_bytes() == original_disk, 'selection/execution implicitly saved source'
            editor.command('bwipeout!')
            wait(lambda: editor.funcs.MoltenRunningKernels() == [], 'owned kernel cleanup')
            print(json.dumps({'kernel_selection_execute_requests': 0, 'restored_saved_outputs': 3,
                              'after_single_cell_execute_requests': len(submitted), 'only_executed_cell': 2,
                              'sentinels': [False, True, False], 'source_and_notebook_unchanged': True,
                              'kernels_after_close': []}))
        finally:
            try:
                editor.command('qa!')
            except (EOFError, OSError):
                pass
            if previous is None:
                os.environ.pop('NVIM_RPLUGIN_MANIFEST', None)
            else:
                os.environ['NVIM_RPLUGIN_MANIFEST'] = previous


if __name__ == '__main__':
    main()
