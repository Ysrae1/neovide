#!/usr/bin/env python3
"""Open persisted text/errors/PNG via real Molten writers, without starting a kernel."""
import base64
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

import nbformat
from PIL import Image
import pynvim

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get('GLOW_TEST_CONFIG', ROOT / 'portable/payload/nvim'))
DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nvim'


def main():
    with tempfile.TemporaryDirectory(prefix="glow saved outputs ") as temporary:
        work = Path(temporary)
        png = io.BytesIO()
        Image.new('RGB', (120, 80), (30, 140, 220)).save(png, format='PNG')
        marker = work / 'code-must-not-run'
        source = f"from pathlib import Path\nPath({str(marker)!r}).write_text('executed')"
        notebook = nbformat.v4.new_notebook(cells=[
            nbformat.v4.new_code_cell(source, execution_count=7, outputs=[
                nbformat.v4.new_output('stream', name='stdout', text='persisted stream\n'),
                nbformat.v4.new_output('execute_result', execution_count=7, data={'text/plain': 'persisted result'})]),
            nbformat.v4.new_code_cell("raise ValueError('saved-error')", execution_count=8, outputs=[
                nbformat.v4.new_output('error', ename='ValueError', evalue='saved-error',
                                      traceback=['exact saved traceback', 'ValueError: saved-error'])]),
            nbformat.v4.new_code_cell('saved_plot()', execution_count=9, outputs=[
                nbformat.v4.new_output('display_data', data={'image/png': base64.b64encode(png.getvalue()).decode(),
                                                            'text/plain': '<saved image>'})]),
            nbformat.v4.new_code_cell('same_code', execution_count=10, outputs=[
                nbformat.v4.new_output('execute_result', execution_count=10, data={'text/plain': 'original duplicate result'})]),
        ], metadata={'kernelspec': {'name': 'python3', 'language': 'python', 'display_name': 'Python 3'},
                     'preserved': {'owner': 'user'}})
        path = work / "saved notebook's 图.ipynb"
        nbformat.write(notebook, path)
        disk = path.read_bytes()
        init, manifest = work / 'init.lua', work / 'rplugin.vim'
        init.write_text('\n'.join([
            'vim.g.mapleader=" ";vim.o.hidden=true;vim.o.swapfile=false',
            '_messages={};vim.notify=function(msg)_messages[#_messages+1]=msg end',
            'vim.opt.rtp:prepend(' + json.dumps(str(CONFIG)) + ')',
            *['vim.opt.rtp:append(' + json.dumps(str(DATA / 'lazy' / name)) + ')'
              for name in ['molten-nvim', 'nvim-treesitter', 'jupytext.nvim']],
            'vim.g.neovide=true;vim.g.neovide_native_notebook=true',
            'vim.g.neovide_native_image=true;vim.g.neovide_native_image_anchor=true;vim.g.neovide_channel_id=77',
            '_calls={};vim.rpcnotify=function(_,method,...)_calls[#_calls+1]={method,...};return true end',
            "require('config.media.runtime').configure_molten()",
            "require('config.media.runtime').configure_jupytext()",
            "require('config.media.notebook_edit').setup()",
        ]))
        env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
        subprocess.run(['nvim', '--headless', '-i', 'NONE', '-n', '-u', str(init), '+UpdateRemotePlugins', '+qa'],
                       env=env, check=True, timeout=25, capture_output=True, text=True)
        previous = os.environ.get('NVIM_RPLUGIN_MANIFEST')
        os.environ['NVIM_RPLUGIN_MANIFEST'] = str(manifest)
        editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-i', 'NONE', '-n', '-u', str(init)])
        try:
            editor.ui_attach(110, 44, rgb=True)
            def lua(code, *args):
                return editor.exec_lua(code, *args)
            def wait(predicate, description):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(.05)
                raise AssertionError(description + ': ' + str(lua("return {_messages,vim.fn.exists('*GlowNotebookSavedOutputs'),require('config.media.notebook_edit').cells(0),vim.api.nvim_buf_get_lines(0,0,-1,false)}")) + '\n' + editor.command_output('messages'))
            lua((ROOT / 'lua/cell_metrics.lua').read_text(), 10., 20.)
            assert lua("return require('config.media.notebook_edit').open(...)", str(path))
            buf = editor.current.buffer.number
            def marks():
                return [mark for mark in editor.api.buf_get_extmarks(buf, -1, 0, -1, {'details': True})
                        if any('Out[' in ''.join(chunk[0] for chunk in row) for row in mark[3].get('virt_lines', []))]
            def text():
                return '\n'.join(''.join(chunk[0] for chunk in row) for mark in marks() for row in mark[3]['virt_lines'])
            wait(lambda: 'persisted result' in text() and 'exact saved traceback' in text() and len(marks()) == 4,
                 'saved outputs appear immediately')
            assert 'Out[7]' in text() and 'Out[8]' in text() and 'persisted stream' in text()
            assert editor.funcs.MoltenRunningKernels() == [] and not marker.exists(), 'opening executed code or started kernel'
            assert lua("return require('config.media.notebook_edit').status().ready") is False
            assert not editor.current.buffer.options['modified'] and path.read_bytes() == disk
            wait(lambda: len(lua("return require('config.media.molten_images').inline_output_marks(...)", buf)) == 1,
                 'saved PNG uses native inline adapter')
            calls = lua('return _calls')
            images = [Path(call[2]) for call in calls if call[0] == 'neovide.image.load']
            assert images and images[-1].read_bytes() == png.getvalue(), 'saved PNG bytes changed'
            original_source = editor.current.buffer[:]
            lua("""
              _saved_requests={}
              local original=vim.fn.GlowNotebookSavedOutputs
              vim.fn.GlowNotebookSavedOutputs=function(action,owner,cells,...)
                local payloads=0
                if action=='render' then
                  for _,cell in ipairs(cells) do if cell.outputs~=nil then payloads=payloads+1 end end
                  _saved_requests[#_saved_requests+1]=payloads
                end
                return original(action,owner,cells,...)
              end
              require('config.media.notebook_saved').refresh(...)
            """, buf)
            assert lua('return #_saved_requests') == 0, 'unchanged layout issued duplicate RPC'
            original_text = text()
            editor.command('enew')
            editor.command('buffer ' + str(buf))
            wait(lambda: text() == original_text, 'hidden saved output retained')
            cells = lua("return require('config.media.notebook_edit').cells(...)", buf)
            last = cells[-1]
            # Insert a new identical source cell before the existing cell. Its
            # saved result must move with the old span, never to the new copy.
            editor.api.buf_set_lines(buf, last['header'] - 1, last['header'] - 1, False, ['# %%', 'same_code', ''])
            wait(lambda: len(marks()) == 4, 'inserted duplicate retains four old results')
            lua("require('config.media.notebook_saved').refresh(...)", buf)
            cells = lua("return require('config.media.notebook_edit').cells(...)", buf)
            duplicate = [mark for mark in marks() if any('original duplicate result' in ''.join(c[0] for c in row)
                                                        for row in mark[3]['virt_lines'])]
            assert len(duplicate) == 1 and duplicate[0][1] == cells[-1]['last'] - 1, 'old output moved to new identical cell'
            assert all(count == 0 for count in lua('return _saved_requests')), 'refresh resent saved base64 payloads'
            editor.api.buf_set_lines(buf, cells[-1]['first'] - 1, cells[-1]['last'], False, ['changed_code'])
            wait(lambda: 'original duplicate result' not in text(), 'edited source hides stale output')
            assert path.read_bytes() == disk and not marker.exists()
            # Close without saving the deliberate source edits, then reopen in
            # a fresh buffer: persisted output must still be available.
            editor.command('bwipeout!')
            assert lua("return require('config.media.notebook_edit').open(...)", str(path))
            buf = editor.current.buffer.number
            wait(lambda: len(marks()) == 4, 'reopen saved output')
            editor.command('GlowNotebookKernel glow-python')
            wait(lambda: lua("return require('config.media.notebook_edit').status().ready"), 'explicit kernel attachment')
            wait(lambda: len(marks()) == 4 and 'persisted result' in text(), 'live import replaces static output without duplication')
            assert not marker.exists() and path.read_bytes() == disk, 'kernel import executed source or saved implicitly'
            assert not editor.current.buffer.options['modified'], 'saved import marked notebook dirty'
            editor.command('bwipeout!')
            wait(lambda: editor.funcs.MoltenRunningKernels() == [], 'owned kernel cleanup')
            print(json.dumps({'saved_text_result_error_png': True, 'opening_starts_kernel': False,
                              'source_span_binding': True, 'hidden_and_reopen': True,
                              'live_import_single_layer': True, 'disk_outputs_exact': True}))
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
