#!/usr/bin/env python3
"""Real orphan swap + Edit Anyway: Jupytext resumes after its post-write E325."""
import json
import os
import signal
import tempfile
import threading
import time
from pathlib import Path

import nbformat
import pynvim

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="glow swap's read ") as temporary:
    work = Path(temporary)
    path, directory, server = work / 'swap continued.ipynb', work / 'swap', work / 'reader.sock'
    directory.mkdir()
    nbformat.write(nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell('value = 42\nvalue')]), path)
    disk = path.read_bytes()
    owner = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE'])
    owner.options['directory'] = str(directory) + '//'
    owner.command('edit ' + owner.funcs.fnameescape(str(path)))
    owner.api.buf_set_lines(0, 0, -1, False, ['# %%', 'value = 42', 'value'])
    owner.command('preserve')
    orphan = Path(owner.eval("swapname('%')"))
    assert orphan.exists()
    os.kill(owner.funcs.getpid(), signal.SIGKILL)
    owner.close()

    editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '--listen', str(server)])
    pid = editor.funcs.getpid()
    def answer_edit_anyway():
        peer = pynvim.attach('socket', path=str(server))
        try:
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                text = []
                for message in list(editor._session._pending_messages):
                    if message[0] != 'notification' or message[1] != 'redraw':
                        continue
                    for event in message[2]:
                        if event[0] == 'grid_line':
                            text.extend(''.join(cell[0] for cell in line[3]) for line in event[1:])
                        elif event[0] == 'msg_show':
                            text.extend(''.join(chunk[1] for chunk in item[1]) for item in event[1:])
                if any('E325:' in line for line in text):
                    # This API path displays E325 without firing SwapExists.
                    # Answer the actual UI warning through a fast RPC channel.
                    peer.input('e\r')
                    return
                time.sleep(.01)
            peer.input('e')
        finally:
            peer.close()

    def swap_read(code):
        editor._session._pending_messages.clear()
        answer = threading.Thread(target=answer_edit_anyway, daemon=True)
        answer.start()
        result = editor.exec_lua(code, str(path))
        answer.join(timeout=2)
        assert not answer.is_alive(), 'swap answer thread did not finish'
        return result

    try:
        signal.signal(signal.SIGALRM, lambda *_args: (_ for _ in ()).throw(TimeoutError('bounded swap read')))
        signal.alarm(35)
        editor.ui_attach(100, 30, rgb=True)
        editor.exec_lua('''
          local config,directory=...
          vim.opt.rtp:prepend(config)
          vim.opt.rtp:append(vim.fn.expand('~/.local/share/nvim/lazy/jupytext.nvim'))
          vim.o.directory=directory..'//';vim.o.hidden=true
          _runtime=require('config.media.runtime');_runtime.configure_jupytext()
          -- Baseline is the exact unwrapped upstream reader.
          require('jupytext').setup({style='percent',output_extension='py',force_ft='python'})
          _posts=0;_messages={}
          vim.notify=function(message)_messages[#_messages+1]=message end
          vim.api.nvim_create_autocmd('BufReadPost',{pattern='*.ipynb',callback=function()_posts=_posts+1 end})
          _set_lines=vim.api.nvim_buf_set_lines
        ''', str(Path(os.environ.get('GLOW_TEST_CONFIG', ROOT / 'portable/payload/nvim'))), str(directory))
        baseline = swap_read("local ok,err=pcall(vim.cmd.edit,{args={...}});return {ok=ok,error=tostring(err),ft=vim.bo.filetype,posts=_posts,lines=vim.api.nvim_buf_get_lines(0,0,-1,false)}")
        assert not baseline['ok'] and 'E325:' in baseline['error'] and baseline['ft'] == '', baseline
        assert 'value = 42' in baseline['lines'] and baseline['posts'] == 0, baseline
        editor.command('bwipeout!')
        editor.exec_lua("assert(_runtime.install_reader_guard()==1);assert(_runtime.install_reader_guard()==0);_notebook=require('config.media.notebook_edit');_notebook.setup()")
        loaded = swap_read("return {ok=_notebook.open(...),ft=vim.bo.filetype,posts=_posts,resumed=vim.b.glow_notebook_swap_read_resumed,complete=vim.b.glow_notebook_read_complete}")
        assert loaded == {'ok': True, 'ft': 'python', 'posts': 1, 'resumed': True, 'complete': True}, (loaded, editor.exec_lua('return _messages'))
        assert editor.exec_lua('return _notebook.status()~=nil and vim.api.nvim_buf_set_lines==_set_lines')
        assert editor.exec_lua("local n=0;for _,a in ipairs(vim.api.nvim_get_autocmds({event='BufWriteCmd',buffer=0}))do if a.group_name=='jupytext-nvim' then n=n+1 end end;return n") == 1
        assert editor.current.buffer[0] == '# ---' and 'value = 42' in editor.current.buffer[:]
        # The dashboard and direct :edit share this original BufReadCmd.
        editor.command('bwipeout!')
        direct = swap_read("local ok,err=pcall(vim.cmd.edit,{args={...}});return {ok=ok,error=tostring(err),ft=vim.bo.filetype,posts=_posts,resumed=vim.b.glow_notebook_swap_read_resumed,attached=vim.b.glow_notebook_edit}")
        assert direct['ok'] and direct['ft'] == 'python' and direct['posts'] == 2 and direct['resumed'] and direct['attached'], direct
        editor.current.buffer.append('# keep unsaved text')
        before, tick = editor.current.buffer[:], editor.api.buf_get_changedtick(0)
        editor.exec_lua('assert(_runtime.complete_notebook_load(vim.api.nvim_get_current_buf()))')
        assert editor.current.buffer[:] == before and editor.api.buf_get_changedtick(0) == tick and editor.current.buffer.options['modified']
        # Ordinary reopening completes automatically after the orphan is gone.
        editor.command('bwipeout!')
        orphan.unlink()
        assert editor.exec_lua('return _notebook.open(...)', str(path))
        assert editor.current.buffer.options['filetype'] == 'python' and editor.exec_lua('return _posts') == 3
        assert editor.exec_lua('return vim.b.glow_notebook_read_complete and not vim.b.glow_notebook_swap_read_resumed')
        assert editor.exec_lua('return _notebook.status()~=nil and vim.api.nvim_buf_set_lines==_set_lines')
        # Unrelated errors still abort, even after writing converted text.
        failure = editor.exec_lua('''
          local actual=vim.api.nvim_buf_set_lines
          local injected=function(...)actual(...);error('E999: controlled unrelated read failure',0)end
          vim.api.nvim_buf_set_lines=injected
          local ok,err=pcall(vim.cmd.edit,{args={...},bang=true})
          assert(vim.api.nvim_buf_set_lines==injected,'scoped API restored after failure')
          vim.api.nvim_buf_set_lines=actual
          return {ok=ok,error=tostring(err),complete=vim.b.glow_notebook_read_complete or false}
        ''', str(path))
        assert not failure['ok'] and 'E999:' in failure['error'] and not failure['complete'], failure
        assert path.read_bytes() == disk, 'Notebook source file was changed while loading'
        print(json.dumps({'real_orphan_swap': True, 'actual_edit_anyway_E325_reproduced': True,
                          'molten_open_and_direct_edit_completed': True, 'normal_reopen_completed': True,
                          'original_reader_writer_and_undo_retained': True, 'unsaved_text_modified_flag_preserved': True,
                          'unrelated_error_not_swallowed': True, 'disk_unchanged': True}))
    finally:
        signal.alarm(0)
        try:
            editor.command('qa!')
        except (EOFError, OSError):
            pass
