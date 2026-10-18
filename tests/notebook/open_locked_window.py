#!/usr/bin/env python3
"""Notebook routing around real winfixbuf, panels, explicit splits and tabs."""
import json
import tempfile
from pathlib import Path

import nbformat
import pynvim

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="glow locked window's ") as temporary:
    work = Path(temporary)
    path, other = work / 'opened notebook.ipynb', work / 'fallback notebook.ipynb'
    for target in (path, other):
        nbformat.write(nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell('42')]), target)
    initial_disk = {target: target.read_bytes() for target in (path, other)}
    editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
    try:
        editor.ui_attach(110, 30, rgb=True)
        editor.exec_lua('''
          vim.opt.rtp:prepend(...)
          vim.opt.rtp:append(vim.fn.expand('~/.local/share/nvim/lazy/jupytext.nvim'))
          vim.o.hidden=true;_messages={};vim.notify=function(msg)_messages[#_messages+1]=msg end
          require('config.media.runtime').configure_jupytext()
          _notebook=require('config.media.notebook_edit');_notebook.setup()
          _source_win=vim.api.nvim_get_current_win();_source_buf=vim.api.nvim_get_current_buf()
          vim.bo.filetype='python';vim.api.nvim_buf_set_lines(0,0,-1,false,{'UNSAVED SOURCE'})
          vim.cmd('rightbelow vnew')
          _locked_win=vim.api.nvim_get_current_win();_locked_buf=vim.api.nvim_get_current_buf()
          vim.bo.buftype='nofile';vim.bo.filetype='Avante';vim.api.nvim_buf_set_lines(0,0,-1,false,{'AVANTE PANEL'})
          vim.bo.modified=false;vim.wo.winfixbuf=true
          package.loaded['neo-tree.utils']={get_appropriate_window=function()return _locked_win,false end}
        ''', str(ROOT / 'portable/payload/nvim'))
        baseline = editor.exec_lua("local ok,err=pcall(vim.cmd.edit,{args={...}});return {ok,tostring(err)}", str(path))
        assert not baseline[0] and 'E1513' in baseline[1], baseline
        editor.exec_lua("assert(_notebook.from_tree({path=...,open_cmd='edit',state={current_position='left'}}).handled)", str(path))
        assert editor.exec_lua('return vim.api.nvim_get_current_win()==_source_win')
        assert Path(editor.current.buffer.name).resolve() == path.resolve() and '42' in editor.current.buffer[:], (editor.current.buffer.name, editor.current.buffer[:], editor.exec_lua('return _messages'))
        assert editor.exec_lua('return #vim.api.nvim_tabpage_list_wins(0)') == 2, 'available source must avoid an extra split'
        assert editor.exec_lua("return vim.api.nvim_buf_get_lines(_source_buf,0,-1,false)") == ['UNSAVED SOURCE']
        assert editor.exec_lua("return vim.wo[_locked_win].winfixbuf and vim.api.nvim_win_get_buf(_locked_win)==_locked_buf")
        assert editor.exec_lua('return _notebook.status()~=nil'), 'normal session attached'

        # A disposable dashboard is replaced, without leaving its floating
        # terminal animation over a newly created split.
        editor.exec_lua("vim.cmd('tabnew');vim.bo.buftype='nofile';vim.bo.filetype='snacks_dashboard';vim.bo.modified=false;_dashboard_win=vim.api.nvim_get_current_win()")
        assert editor.exec_lua('return _notebook.open(...)', str(other))
        assert editor.exec_lua('return #vim.api.nvim_tabpage_list_wins(0)==1 and vim.api.nvim_get_current_win()==_dashboard_win')
        editor.command('tabclose')
        editor.exec_lua('vim.api.nvim_set_current_win(_source_win)')

        # Verify the hot-apply recipe keeps the old sessions and closures alive.
        editor.exec_lua('''
          local old=_notebook
          local fresh=assert(loadfile(...))()
          local function retain(fn,previous)
            local values={}
            for i=1,100 do local name,value=debug.getupvalue(previous,i);if not name then break end;values[name]=value end
            for i=1,100 do local name=debug.getupvalue(fn,i);if not name then break end
              if values[name]~=nil then debug.setupvalue(fn,i,values[name]) end
            end
            return fn
          end
          local status=old.status()
          old.route_open=fresh.route_open
          old.open=retain(fresh.open,old.open)
          old.from_tree=retain(fresh.from_tree,old.from_tree)
          assert(package.loaded['config.media.notebook_edit']==old and vim.deep_equal(status,old.status()),'session preserved hot apply')
        ''', str(ROOT / 'portable/payload/nvim/lua/config/media/notebook_edit.lua'))

        editor.exec_lua('vim.wo[_source_win].winfixbuf=true;vim.api.nvim_set_current_win(_locked_win)')
        assert editor.exec_lua('return _notebook.open(...,{win=_locked_win})', str(other))
        assert Path(editor.current.buffer.name).resolve() == other.resolve()
        assert editor.exec_lua('return #vim.api.nvim_tabpage_list_wins(0)') == 3, 'all locked creates one editor split'
        assert not editor.current.window.options['winfixbuf']
        assert editor.exec_lua('return vim.wo[_locked_win].winfixbuf and vim.wo[_source_win].winfixbuf')
        count = len(editor.current.tabpage.windows)
        editor.exec_lua("_notebook.from_tree({path=...,open_cmd='vsplit',state={current_position='left'}})", str(path))
        assert len(editor.current.tabpage.windows) == count + 1 and Path(editor.current.buffer.name).resolve() == path.resolve(), 'explicit vsplit preserved'
        tabs = len(editor.tabpages)
        editor.exec_lua("_notebook.from_tree({path=...,open_cmd='tabnew',state={current_position='left'}})", str(other))
        assert len(editor.tabpages) == tabs + 1 and Path(editor.current.buffer.name).resolve() == other.resolve(), 'explicit tab request preserved'
        assert editor.exec_lua("return vim.api.nvim_buf_get_lines(_locked_buf,0,-1,false)") == ['AVANTE PANEL']
        assert all(target.read_bytes() == disk for target, disk in initial_disk.items())
        print(json.dumps({'actual_E1513_reproduced': True, 'locked_panel_preserved': True,
                          'normal_source_preferred': True, 'all_locked_new_split': True,
                          'explicit_split_and_tab': True, 'hot_apply_sessions_preserved': True,
                          'user_data_unchanged': True}))
    finally:
        try:
            editor.command('qa!')
        except (EOFError, OSError):
            pass
