#!/usr/bin/env python3
"""Real Jupytext saves survive lost handlers and a bare restored percent buffer."""
import json
import os
import tempfile
from pathlib import Path

import nbformat
import pynvim

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="glow writer's ") as temporary:
    work = Path(temporary)
    original = nbformat.v4.new_notebook(metadata={'preserved': {'owner': 'user'}}, cells=[
        nbformat.v4.new_code_cell('value = 36\nvalue', metadata={'tags': ['keep']}, execution_count=7,
            outputs=[nbformat.v4.new_output('execute_result', data={'text/plain': '36'}, execution_count=7)])])
    path, restored, invalid = work / "original's notebook.ipynb", work / 'bare restored.ipynb', work / 'invalid.ipynb'
    for target in (path, restored):
        nbformat.write(original, target)
    invalid.write_text('\n# ---\n# jupyter:\n# ---\n# %%\nprint("not JSON")\n')
    editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
    try:
        editor.ui_attach(100, 30, rgb=True)
        editor.exec_lua('''
          vim.opt.rtp:prepend(...)
          vim.opt.rtp:append(vim.fn.expand('~/.local/share/nvim/lazy/jupytext.nvim'))
          vim.o.hidden=true;_messages={};vim.notify=function(msg)_messages[#_messages+1]=msg end
          _runtime=require('config.media.runtime');_runtime.configure_jupytext()
          require('config.media.notebook_edit').setup()
          _convert=_runtime.convert;_conversions=0;_posts=0
          _runtime.convert=function(args)_conversions=_conversions+1;return _convert(args)end
          vim.api.nvim_create_autocmd('BufWritePost',{pattern='*.ipynb',callback=function()_posts=_posts+1 end})
        ''', str(Path(os.environ.get('GLOW_TEST_CONFIG', ROOT / 'portable/payload/nvim'))))
        assert editor.exec_lua("return require('config.media.notebook_edit').open(...)", str(path))
        source = editor.current.buffer[:]
        editor.exec_lua('_conversions=0;_posts=0')
        editor.command('write')
        assert editor.exec_lua('return {_conversions,_posts}') == [1, 1], 'upstream must remain the single writer'
        assert nbformat.read(path, 4).cells[0].outputs == original.cells[0].outputs
        editor.exec_lua("vim.api.nvim_clear_autocmds({group='jupytext-nvim',event='BufWriteCmd',buffer=0});_conversions=0;_posts=0")
        editor.current.buffer.append('# safe changed source')
        editor.command('write')
        assert editor.exec_lua('return {_conversions,_posts}') == [1, 1], 'fallback must convert/post exactly once'
        saved = nbformat.read(path, 4)
        assert saved.metadata.preserved == original.metadata.preserved
        assert saved.cells[0].metadata.tags == ['keep'] and saved.cells[0].outputs == original.cells[0].outputs

        editor.exec_lua('''
          local path,lines=...
          local buf=vim.api.nvim_create_buf(true,false)
          vim.api.nvim_buf_set_name(buf,path)
          vim.cmd('noautocmd buffer '..buf)
          vim.api.nvim_buf_set_lines(buf,0,-1,false,vim.list_extend({'',''},lines))
          assert(vim.bo.filetype=='' and not vim.b.glow_notebook_edit and not vim.b.glow_notebook_writer,'bare restore fixture')
          _conversions=0;_posts=0
        ''', str(restored), source)
        before = editor.current.buffer[:]
        editor.command('write!')  # E13 must not be the protection for a restored buffer.
        assert editor.exec_lua('return {_conversions,_posts}') == [1, 1]
        restored_nb = nbformat.read(restored, 4)
        assert len(restored_nb.cells) == 1 and restored_nb.cells[0].source == original.cells[0].source, restored_nb.cells
        assert restored_nb.metadata.preserved == original.metadata.preserved
        assert restored_nb.cells[0].outputs == original.cells[0].outputs
        assert editor.current.buffer[:] == before, 'serialization changed restored source/padding'
        # Conversion failure never replaces the original JSON, or clears edits.
        disk = restored.read_bytes()
        editor.current.buffer.append('# unsaved')
        editor.exec_lua("_runtime.convert=function()error('controlled conversion failure')end")
        result = editor.exec_lua("local ok,err=pcall(vim.cmd.write,{bang=true});return {ok,tostring(err),vim.bo.modified}")
        assert not result[0] and 'controlled conversion failure' in result[1] and result[2] and restored.read_bytes() == disk
        editor.exec_lua('_runtime.convert=_convert')
        bad_disk = invalid.read_bytes()
        assert not editor.exec_lua("return require('config.media.notebook_edit').open(...)", str(invalid))
        message = editor.exec_lua('return _messages[#_messages]')
        assert '不是有效的 JSON Notebook' in message and 'stack traceback' not in message and 'JSONDecode' not in message, message
        assert invalid.read_bytes() == bad_disk
        print(json.dumps({'upstream_single_writer': True, 'lost_handler_json_save': True,
                          'bare_restore_empty_filetype_no_flags': True, 'leading_blank_header': 'one real code cell',
                          'source_metadata_outputs_preserved': True, 'conversion_failure_disk_unchanged': True,
                          'invalid_json_friendly': True}))
    finally:
        try:
            editor.command('qa!')
        except (EOFError, OSError):
            pass
