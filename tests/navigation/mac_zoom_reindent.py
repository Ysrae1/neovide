#!/usr/bin/env python3
"""Actual key dispatch in an owned embedded Mac Neovim (no native GUI/OS capture).
Terminal mode uses nvim_open_term, without a shell or child job.
"""
import os
from pathlib import Path
import tempfile
import time

import pynvim

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get('GLOW_TEST_CONFIG', Path.home() / '.config/nvim'))
with tempfile.TemporaryDirectory(prefix='glow-mac-zoom-') as temporary:
    child = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '-n'])
    try:
        child.ui_attach(100, 35, rgb=True)
        child.exec_lua('''
          local config,work=...
          vim.opt.rtp={config,vim.env.VIMRUNTIME}
          local old=vim.fn.stdpath
          vim.fn.stdpath=function(name)return name=='state' and work or name=='config' and work..'/config' or old(name)end
          assert(vim.fn.has('macunix')==1,'actual Mac mapping dispatch fixture')
          vim.g.neovide=true;vim.g.mapleader=' ';vim.g.neovide_scale_factor=.8
          _language='en';_translations=0
          package.loaded['config.platform.locale']={current=function()return _language end,
            t=function()error('explicit reindent strings must not depend on shared catalog')end,
            translate=function(en,zh)_translations=_translations+1;return _language=='zh' and zh or en end}
          local source='@'..config..'/lua/config/platform/neovide_zoom.lua'
          _old=assert(loadstring(string.rep('\\n',65)..'return function()\\n return "old"\\nend',source))()
          assert(debug.getinfo(_old,'S').linedefined==66 and debug.getinfo(_old,'S').lastlinedefined==68)
          vim.keymap.set({'n','i','v','c','t'},'<D-9>',_old,{desc='Decrease Neovide scale'})
          vim.keymap.set('t','<D-9>',_old,{desc='缩小 Neovide 界面'})
          _custom=function()_user_nine=(_user_nine or 0)+1 end
          vim.keymap.set('i','<D-9>',_custom,{desc='Decrease Neovide scale'})
          vim.keymap.set('s','<D-9>',_custom,{desc='User Select shortcut'})
          vim.keymap.set('c','<D-9>',_old,{desc='User command shortcut'})
          vim.keymap.set('n','<D-9>',_custom,{buffer=0,desc='User local shortcut'})
          _zoom=require('config.platform.neovide_zoom');_zoom.setup({load=false})
          assert(vim.g.neovide_scale_factor==.8,'hot setup loaded persisted scale')
          local function global(mode)
            for _,m in ipairs(vim.api.nvim_get_keymap(mode))do if m.lhs=='<D-9>'then return m end end
          end
          assert(not global('n') and not global('x') and not global('t'),'old owned mappings survived')
          assert(global('i').callback==_custom and global('s').callback==_custom and global('c').callback==_old,'user override removed')
          assert(vim.fn.maparg('<D-9>','n',false,true).callback==_custom,'local user override removed')
          assert(vim.fn.maparg('<D-9>','n',false,true).buffer==1)
          _zoom.setup({load=false})
          assert(vim.fn.maparg('<D-9>','i',false,true).callback==_custom,'repeat setup removed user shortcut')
          _sourcebuf=vim.api.nvim_get_current_buf()
          vim.api.nvim_buf_set_lines(_sourcebuf,0,-1,false,{'keep original text'})
          _terminal=vim.api.nvim_create_buf(false,true);_terminal_input={}
          vim.api.nvim_open_term(_terminal,{on_input=function(_,_,_,data)_terminal_input[#_terminal_input+1]=data end})
          vim.o.hidden=true;vim.o.timeoutlen=300
        ''', str(CONFIG), temporary)

        def wait(predicate, label):
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                if predicate():
                    return
                time.sleep(.005)
            raise AssertionError(label + ': ' + child.command_output('messages'))

        for mode in ('n', 'i', 'v', 'c', 't'):
            child.input('<Esc>')
            child.exec_lua('vim.api.nvim_set_current_buf(_sourcebuf)')
            if mode == 'i': child.input('i')
            elif mode == 'v': child.input('v')
            elif mode == 'c': child.input(':echo 123')
            elif mode == 't':
                child.exec_lua('vim.api.nvim_set_current_buf(_terminal)')
                child.command('startinsert')
            wait(lambda: child.api.get_mode()['mode'] == mode, 'enter ' + mode)
            command = child.funcs.getcmdline() if mode == 'c' else None
            for key, expected in (('<D-=>', 1.1), ('<D-+>', 1.1), ('<D-->', .9), ('<D-0>', 1.0)):
                child.exec_lua('vim.g.neovide_scale_factor=1.0')
                child.input(key)
                wait(lambda: abs(child.exec_lua('return vim.g.neovide_scale_factor') - expected) < 1e-8, mode + '/' + key)
                assert child.api.get_mode()['mode'] == mode, (mode, key, child.api.get_mode())
                if mode == 'c': assert child.funcs.getcmdline() == command
            if mode == 't': child.input('<C-\\><C-n>')
            else: child.input('<Esc>')
            wait(lambda: child.api.get_mode()['mode'] in ('n', 'nt'), 'leave ' + mode)
        assert child.exec_lua('return #_terminal_input') == 0, 'zoom key was sent to terminal input'
        assert child.exec_lua('return vim.api.nvim_buf_get_lines(_sourcebuf,0,-1,false)') == ['keep original text']

        child.exec_lua('''
          vim.api.nvim_set_current_buf(_sourcebuf)
          _native_n=vim.fn.maparg('=','n',false,true);_native_x=vim.fn.maparg('=','x',false,true)
          _reindent=require('config.navigation.reindent_keymaps');_reindent.setup()
          assert(vim.deep_equal(_native_n,vim.fn.maparg('=','n',false,true)) and vim.deep_equal(_native_x,vim.fn.maparg('=','x',false,true)))
          vim.bo.equalprg='';vim.bo.indentexpr='';vim.bo.cindent=true;vim.bo.expandtab=true;vim.bo.shiftwidth=2
          _code={'if (ready) {','value = 1;','next();','}'}
          vim.api.nvim_buf_set_lines(0,0,-1,false,_code)
          vim.api.nvim_win_set_cursor(0,{1,0})
        ''')
        child.input(' c=')
        wait(lambda: 'o' in child.api.get_mode()['mode'], 'native = awaits a motion')
        assert child.eval('v:operator') == '='
        child.input('j')
        wait(lambda: child.api.get_mode()['mode'] == 'n', 'normal reindent completes')
        assert child.current.buffer[:] == ['if (ready) {', '  value = 1;', 'next();', '}'], 'normal motion scope changed'
        child.exec_lua('vim.api.nvim_buf_set_lines(0,0,-1,false,_code);vim.api.nvim_win_set_cursor(0,{2,0})')
        child.input('Vj')
        wait(lambda: child.api.get_mode()['mode'] == 'V', 'visual line range')
        child.input(' c=')
        wait(lambda: child.api.get_mode()['mode'] == 'n', 'visual reindent completes')
        assert child.current.buffer[:] == ['if (ready) {', '  value = 1;', '  next();', '}'], 'visual selection scope changed'
        descriptions = child.exec_lua('''
          local result={}
          for _,lang in ipairs({'en','zh','en'})do
            _language=lang;vim.api.nvim_exec_autocmds('User',{pattern='GlowLanguageChanged',modeline=false})
            result[#result+1]={vim.fn.maparg(' c=','n',false,true).desc,vim.fn.maparg(' c=','x',false,true).desc}
          end
          assert(_translations>=8,'locale.translate(en,zh) was not used')
          assert(vim.deep_equal(_native_n,vim.fn.maparg('=','n',false,true)) and vim.deep_equal(_native_x,vim.fn.maparg('=','x',false,true)))
          return result
        ''')
        assert descriptions == [['Reindent Code', 'Reindent Selection'], ['重新缩进（选择范围）', '重新缩进选中代码'], ['Reindent Code', 'Reindent Selection']]
        # A later user override is also retained by language-only refresh.
        assert child.exec_lua('''
          vim.keymap.set('n',' c=','gq',{desc='User action'})
          _language='zh';vim.api.nvim_exec_autocmds('User',{pattern='GlowLanguageChanged',modeline=false})
          return vim.fn.maparg(' c=','n',false,true).rhs=='gq'
        ''')
        print('PASS:', CONFIG, '| actual D=/D+/D-/D0 dispatch n/i/v/c/t; exact old D9 retired, custom/global/local/Select overrides kept; native normal/Visual = scopes, explicit en→zh→en labels; no GUI/OS event or shell')
    finally:
        try: child.command('qa!')
        except Exception: pass
        child.close()
