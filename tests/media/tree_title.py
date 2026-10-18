#!/usr/bin/env python3
"""Real tabline screen: fixed left title anchor through narrow sidebar widths."""
import json
from pathlib import Path

import pynvim


ROOT = Path(__file__).resolve().parents[2]
editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
try:
    editor.ui_attach(96, 20, rgb=True)
    editor.exec_lua('vim.opt.rtp:prepend(...)', str(ROOT / 'portable/payload/nvim'))
    editor.exec_lua('''
        vim.g.neovide=true;vim.o.showtabline=2;vim.o.laststatus=0
        local render=require('config.appearance.tree_title').render
        for _,system in ipairs({'Darwin','Linux','Windows_NT','Other'}) do
          for width=0,24 do
            local result=vim.api.nvim_eval_statusline(render(width,system),{use_tabline=true,maxwidth=96})
            assert(result.width==(width>0 and width+1 or 0),'display width '..width)
            if width>0 then assert(result.str:sub(1,1)==' ' and result.str:sub(-1)==' ') end
          end
        end
        vim.g.neovide=false
        assert(vim.api.nvim_eval_statusline(render(12,'Darwin'),{use_tabline=true}).str:sub(-3)=='│','terminal separator unchanged')
        vim.g.neovide=true
        _title=require('chadrc').ui.tabufline.modules.ntreeOffset
        _G.GlowTreeTitle=function() return _title()..'%#TabLine#NEIGHBOR' end
        vim.o.tabline='%!v:lua.GlowTreeTitle()'
    ''')
    editor.current.buffer[:] = ['neighbor source']
    source, source_window = editor.current.buffer.number, editor.current.window.handle
    editor.current.buffer.options['modified'] = False
    changedtick = editor.api.buf_get_changedtick(source)
    editor.command('leftabove vnew')
    tree = editor.current.window.handle
    editor.current.buffer[:] = ['tree content']
    editor.current.buffer.options['filetype'] = 'neo-tree'
    widths = []
    for width in (28, 18, 16, 15, 12, 8, 5, 2, 1, 28):
        editor.api.win_set_width(tree, width)
        editor.command('redraw!')
        actual = editor.api.win_get_width(tree)
        snapshot = editor.exec_lua('''
            local width=...;local text=''
            for col=1,width+10 do text=text..vim.fn.screenstring(1,col) end
            return {text=text,first=vim.fn.screenstring(1,1),separator=vim.fn.screenstring(1,width+1),
              next=vim.fn.screenstring(1,width+2),rendered=vim.api.nvim_eval_statusline(_title(),{use_tabline=true,maxwidth=96})}
        ''', actual)
        assert snapshot['first'] == ' ', snapshot
        assert snapshot['separator'] == ' ' and snapshot['next'] == 'N', snapshot
        assert snapshot['rendered']['width'] == actual + 1, snapshot
        assert editor.api.win_get_position(source_window)[1] == actual + 1
        assert '\ufffd' not in snapshot['text']
        if actual >= 16:
            assert 'File Explorer' in snapshot['rendered']['str'], snapshot
        widths.append(actual)
    assert editor.api.buf_get_lines(source, 0, -1, False) == ['neighbor source']
    assert editor.api.buf_get_changedtick(source) == changedtick and not editor.api.buf_get_option(source, 'modified')
    print(json.dumps({'sidebar_widths': widths, 'fixed_one_cell_indent': True, 'blank_separator_aligned': True,
                      'neighbor_not_overlapped': True, 'utf8_intact': True, 'source_unchanged': True}))
finally:
    try:
        editor.command('qa!')
    except (EOFError, OSError):
        pass
