#!/usr/bin/env python3
"""Real VimTeX .tex maps and typed WhichKey prefix in an owned embedded child.
No compile/view/clean action is invoked. GLOW_TEST_CONFIG selects local/portable.
"""
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import threading
import time

import pynvim

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get('GLOW_TEST_CONFIG', Path.home() / '.config/nvim'))
PLUGINS = Path.home() / '.local/share/nvim/lazy'
with tempfile.TemporaryDirectory(prefix='glow-vimtex-locale-') as temporary:
    work = Path(temporary)
    tex = work / 'entry.tex'
    second = work / 'second.tex'
    document = '\\documentclass{article}\n\\begin{document}\nOriginal user source\n\\end{document}\n'
    tex.write_text(document)
    second.write_text(document)
    child = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '-n'])
    pid = child.eval('getpid()')
    watchdog = threading.Timer(25, lambda: os.kill(pid, signal.SIGTERM))
    watchdog.start()
    try:
        child.ui_attach(140, 55, rgb=True)
        child.exec_lua('''
          local config,plugins,work=...
          vim.opt.rtp={config,plugins..'/vimtex',plugins..'/which-key.nvim',vim.env.VIMRUNTIME}
          vim.g.mapleader=' ';vim.g.maplocalleader='\\\\';vim.g.neovide=false
          local stdpath=vim.fn.stdpath
          vim.fn.stdpath=function(name)return name=='state' and work or name=='config' and work..'/config' or stdpath(name)end
          vim.g.vimtex_cache_root=work..'/cache';vim.g.vimtex_syntax_enabled=0
          require('plugins.languages.vimtex').init()
          vim.cmd('runtime plugin/vimtex.vim')
          _language='en'
          local catalog=require('config.locale.catalog').new(function()return _language end)
          package.loaded['config.platform.locale']={current=function()return _language end,t=catalog.t}
          require('which-key').setup({delay=0,notify=false,icons={mappings=false},
            win={width=110,height={min=8,max=35},row=2,col=2,no_overlap=false},
            plugins={marks=false,registers=false,presets={operators=false,motions=false,text_objects=false,windows=false,nav=false,z=false,g=false}}})
          assert(vim.wait(1000,function()return require('which-key.config').loaded end,10))
          vim.o.timeoutlen=5000;vim.o.hidden=true
          vim.cmd('filetype plugin indent on')
          function _maps(buf)
            local result={}
            for _,mode in ipairs({'n','x'})do
              for _,m in ipairs(vim.api.nvim_buf_get_keymap(buf,mode))do
                if m.lhs:sub(1,2)=='\\\\l' and m.rhs and m.rhs:find('<Plug>(vimtex-',1,true)then
                  result[mode..':'..m.lhs]=m
                end
              end
            end
            return result
          end
        ''', str(CONFIG), str(PLUGINS), temporary)
        child.command('edit ' + child.funcs.fnameescape(str(tex)))
        buf = child.current.buffer.number
        baseline = child.exec_lua('return _maps(...)', buf)
        assert len(baseline) >= 23, baseline
        assert child.exec_lua('return vim.b.vimtex~=nil and vim.bo.filetype=="tex"')
        assert all(not row.get('desc') for row in baseline.values()), 'fixture must use true plugin mappings without desc'
        # Hot application to already initialized VimTeX; no source/module reload.
        assert child.exec_lua('return require("config.locale.vimtex").setup()') == len(baseline)
        assert child.exec_lua('return _maps(...)', buf) == baseline, 'metadata changed real map fields'
        assert child.exec_lua('return require("config.locale.vimtex").setup()') == len(baseline)
        metadata_count = child.exec_lua('return #require("which-key.config").mappings')
        assert child.exec_lua('return require("config.locale.vimtex").refresh(...)', buf) == len(baseline)
        assert child.exec_lua('return #require("which-key.config").mappings') == metadata_count, 'duplicate metadata registration'

        group_rows = child.exec_lua(r'''
          local result={}
          local mode=require('which-key.buf').get({mode='n',update=true})
          local node=assert(mode.tree:find([[\l]]))
          for _,lang in ipairs({'en','zh','en'})do
            _language=lang;result[#result+1]=require('which-key.view').item(node).desc
          end
          _language='en'
          return result
        ''')
        assert [label.lstrip('+') for label in group_rows] == ['LaTeX', 'LaTeX功能', 'LaTeX'], group_rows
        if os.environ.get('GLOW_TEST_GROUP_ONLY') == '1':
            print('PASS real VimTeX/WhichKey group en→zh→en: ' + repr(group_rows))
            sys.exit(0)

        def wait(predicate, name):
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                value = predicate()
                if value:
                    return value
                time.sleep(.01)
            raise AssertionError(name + ': ' + child.command_output('messages'))

        # Actual key input exercises the automatic backslash trigger, rather
        # than constructing a fake WhichKey state or just testing the catalog.
        wait(lambda: child.exec_lua('return vim.fn.maparg([[\\]],"n",false,true).desc=="which-key-trigger"'), 'automatic localleader trigger')
        child.input('\\l')
        wait(lambda: child.exec_lua('local s=require("which-key.state").state;return s and s.node.keys==[[\\l]] and require("which-key.view").valid()'), 'typed \\l opens real help')
        def rendered(lang):
            return child.exec_lua('''
              _language=...
              vim.api.nvim_exec_autocmds('User',{pattern='GlowLanguageChanged',modeline=false})
              local view=require('which-key.view')
              local state=require('which-key.state').state
              local rows={}
              for _,node in ipairs(state.node:children())do rows[node.keys]=view.item(node).desc end
              local body=table.concat(vim.api.nvim_buf_get_lines(view.view.buf,0,-1,false),'\\n')
              return {rows=rows,body=body,keys=state.node.keys}
            ''', lang)
        english = rendered('en')
        chinese = rendered('zh')
        restored = rendered('en')
        assert english['rows'] == restored['rows']
        assert len(english['rows']) == len([k for k in baseline if k.startswith('n:')]), english
        for key, row in chinese['rows'].items():
            assert row != english['rows'][key] and row in chinese['body'], (key, row, chinese['body'])
        assert chinese['rows']['\\ll'] == '切换 LaTeX 持续编译'
        assert chinese['rows']['\\lS'] == '单次编译 LaTeX'
        assert chinese['rows']['\\lL'] == '编译指定的 LaTeX 行（接动作）'
        assert chinese['rows']['\\lC'] == '清理 LaTeX 辅助及输出文件'
        assert child.exec_lua('return _maps(...)', buf) == baseline
        child.input('<Esc>')
        wait(lambda: not child.exec_lua('return require("which-key.view").valid()'), 'close help only')
        # The parent localleader menu contains the explicit VimTeX product group.
        mode = child.exec_lua('''
          local m=require('which-key.buf').get({mode='n',update=true})
          return require('which-key.view').item(assert(m.tree:find([[\\l]]))).desc
        ''')
        assert mode.lstrip('+') == 'LaTeX', mode
        # New .tex buffer: the official InitPost event attaches automatically.
        child.command('edit ' + child.funcs.fnameescape(str(second)))
        newer = child.current.buffer.number
        assert newer != buf
        registered = child.exec_lua('''
          local mode=require('which-key.buf').get({mode='n',update=true})
          local node=assert(mode.tree:find([[\\ll]]))
          return require('which-key.view').item(node).desc
        ''')
        assert registered == english['rows']['\\ll']
        # Non-TeX buffers get no phantom menu or compilation keys.
        child.command('enew')
        # Avoid Neovim's unrelated Lua ftplugin starting an unavailable parser
        # in this deliberately minimal plugin fixture. Test the real ft value.
        child.command('noautocmd setlocal filetype=lua')
        assert child.exec_lua('return require("config.locale.vimtex").refresh()') == 0
        assert child.exec_lua('local m=require("which-key.buf").get({mode="n",update=true});return m.tree:find([[\\l]])==nil')
        assert tex.read_text() == document and second.read_text() == document
        assert not any(p.suffix in {'.pdf', '.log', '.aux', '.fdb_latexmk', '.synctex'} for p in work.iterdir()), 'compiler/viewer action ran'
        print('PASS:', CONFIG, '| typed \\l actual WhichKey en→zh→en;', len(baseline), 'real n/x maps unchanged; existing/new TeX, group, metadata idempotence, non-TeX isolation; no compile/view/clean')
        print('REAL_VIMTEX_MENU=' + json.dumps(chinese['rows'], ensure_ascii=False))
    finally:
        watchdog.cancel()
        try:
            child.command('qa!')
        except Exception:
            pass
        child.close()
