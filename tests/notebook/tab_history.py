#!/usr/bin/env python3
"""Real Molten: unsaved outputs and kernel state survive buffer/tab switching.

Run with the existing glow-notebook-venv Python; creates only temporary notebooks
and owned test kernels. GLOW_TEST_CONFIG selects local or portable configuration.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

import nbformat
import pynvim

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get('GLOW_TEST_CONFIG', ROOT / 'portable/payload/nvim'))
DATA = Path.home() / '.local/share/nvim'
with tempfile.TemporaryDirectory(prefix='glow-tab-history-') as directory:
    work = Path(directory)
    notebook = work / 'history.ipynb'
    second = work / 'other.ipynb'
    nbformat.write(nbformat.v4.new_notebook(cells=[
        nbformat.v4.new_code_cell('value = 41\nvalue + 1'),
        nbformat.v4.new_code_cell("raise ValueError('unsaved-tab-error')"),
        nbformat.v4.new_code_cell('value + 1'),
    ]), notebook)
    nbformat.write(nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell('7 * 7')]), second)
    disk = notebook.read_bytes()
    manifest, init = work / 'rplugin.vim', work / 'init.lua'
    init.write_text('\n'.join([
        'vim.o.hidden=true;vim.g.mapleader=" "',
        '_G.history_messages={};vim.notify=function(m) history_messages[#history_messages+1]=m end',
        'vim.opt.rtp:prepend(' + json.dumps(str(CONFIG)) + ')',
        *['vim.opt.rtp:append(' + json.dumps(str(DATA / 'lazy' / plugin)) + ')'
          for plugin in ('molten-nvim', 'nvim-treesitter', 'jupytext.nvim')],
        "require('config.media.runtime').configure_molten()",
        "require('config.media.runtime').configure_jupytext()",
        "require('config.media.notebook_edit').setup()",
    ]))
    env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
    subprocess.run(['nvim', '--headless', '-u', str(init), '-i', 'NONE', '-n', '+UpdateRemotePlugins', '+qa'],
                   env=env, check=True, timeout=20, capture_output=True, text=True)
    previous = os.environ.get('NVIM_RPLUGIN_MANIFEST')
    os.environ['NVIM_RPLUGIN_MANIFEST'] = str(manifest)
    editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', str(init), '-i', 'NONE', '-n'])
    try:
        editor.ui_attach(120, 40, rgb=True)
        def lua(code, *args):
            return editor.exec_lua(code, *args)
        def wait(predicate, description):
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                if predicate(): return
                time.sleep(.1)
            raise AssertionError(description + ': ' + str(lua('return history_messages')))
        def output(buf):
            return str([mark[3].get('virt_lines', []) for mark in editor.api.buf_get_extmarks(buf, -1, 0, -1, {'details': True})])
        def run_cell(index):
            cells = lua("return require('config.media.notebook_edit').cells(0)")
            editor.current.window.cursor = (cells[index]['first'], 0)
            editor.command('GlowNotebookRun')
        assert lua("return require('config.media.notebook_edit').open(...)", str(notebook))
        first = editor.current.buffer.number
        run_cell(0)
        wait(lambda: '42' in output(first) and 'Done' in output(first), 'fresh arithmetic output')
        run_cell(1)
        wait(lambda: 'unsaved-tab-error' in output(first) and 'Failed' in output(first), 'fresh error output')
        kernel = lua("return require('config.media.notebook_edit').status().kernel")
        assert kernel and notebook.read_bytes() == disk
        def raw_outputs():
            snapshot = work / 'observed.ipynb'
            snapshot.write_bytes(disk)
            lua("local path,kernel=...;vim.cmd({cmd='MoltenExportOutput',args={path,kernel},bang=true})", str(snapshot), kernel)
            return [(cell.outputs, cell.execution_count) for cell in nbformat.read(snapshot, 4).cells]
        original_outputs = raw_outputs()
        editor.command('enew')  # Same BufHidden path as switching top bufferline files.
        lua('vim.wait(250)')
        assert kernel in editor.funcs.MoltenRunningKernels(), 'hiding the Notebook destroyed its kernel'
        editor.command('buffer ' + str(first))
        wait(lambda: '42' in output(first) and 'unsaved-tab-error' in output(first), 'buffer return restores both outputs')
        assert lua("return require('config.media.notebook_edit').status().kernel") == kernel
        assert 'Out[1]' in output(first) and 'Out[2]' in output(first), 'execution history numbering changed'
        assert raw_outputs() == original_outputs, 'buffer switching changed original output payloads'
        editor.command('tabnew')
        lua('vim.wait(150)')
        editor.command('tabprevious')
        wait(lambda: '42' in output(first) and 'unsaved-tab-error' in output(first), 'Tab return restores outputs')
        assert lua("return require('config.media.notebook_edit').status().kernel") == kernel
        assert raw_outputs() == original_outputs, 'Tab switching changed original results or full traceback'
        # A second Notebook owns a separate live kernel; neither replaces the other.
        assert lua("return require('config.media.notebook_edit').open(...,{command=''})", str(second))
        other = editor.current.buffer.number
        run_cell(0)
        wait(lambda: '49' in output(other) and 'Done' in output(other), 'second Notebook output')
        other_kernel = lua("return require('config.media.notebook_edit').status().kernel")
        assert other_kernel != kernel
        editor.command('buffer ' + str(first))
        wait(lambda: '42' in output(first) and 'unsaved-tab-error' in output(first), 'second Notebook leaves original history intact')
        assert raw_outputs() == original_outputs, 'another Notebook changed original output payloads'
        run_cell(2)
        wait(lambda: 'Out[3]' in output(first) and 'Done' in output(first), 'original kernel namespace and counter survive')
        assert 'NameError' not in output(first)
        editor.command('bdelete! ' + str(other))
        wait(lambda: other_kernel not in editor.funcs.MoltenRunningKernels(), 'closing second buffer releases only its kernel')
        assert kernel in editor.funcs.MoltenRunningKernels()
        editor.command('bdelete! ' + str(first))
        wait(lambda: kernel not in editor.funcs.MoltenRunningKernels(), 'closing original buffer releases owned kernel')
        assert notebook.read_bytes() == disk, 'switching or closing implicitly overwrote the Notebook'
        print('PASS: bufferline hide/return; real Tab leave/return; two Notebooks; unsaved result/error/Out[n]; live variables; close releases only owned kernel; disk unchanged')
    finally:
        try: editor.command('qa!')
        except (EOFError, OSError): pass
        editor.close()
        if previous is None: os.environ.pop('NVIM_RPLUGIN_MANIFEST', None)
        else: os.environ['NVIM_RPLUGIN_MANIFEST'] = previous
