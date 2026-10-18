#!/usr/bin/env python3
"""Real Snacks screen: blank/icon/blank diagnostics and original priorities."""
import json
from pathlib import Path
import re

import pynvim


ROOT = Path(__file__).resolve().parents[1]
editor = pynvim.attach('child', argv=['nvim', '--embed', '-u', 'NONE', '-n', '-i', 'NONE'])
try:
    editor.ui_attach(80, 24, rgb=True)
    editor.exec_lua('vim.opt.rtp:prepend(...)', str(Path.home() / '.local/share/nvim/lazy/snacks.nvim'))
    editor.exec_lua('''
        local root = ...
        vim.opt.rtp:prepend(root..'/portable/payload/nvim')
        for _,name in ipairs({'pyright','clangd','texlab'}) do package.preload['config.lsp.'..name]=function() return {} end end
        local severity=vim.diagnostic.severity
        local opts={diagnostics={underline=false,virtual_text=false,severity_sort=true,
          signs={text={[severity.ERROR]=' ',[severity.WARN]=' ',[severity.INFO]=' ',[severity.HINT]=' '}}}}
        dofile(root..'/portable/payload/nvim/lua/plugins/languages/nvim_lspconfig.lua')[1].opts(nil,opts)
        assert(opts.diagnostics.severity_sort and opts.diagnostics.underline==false)
        for _,text in pairs(opts.diagnostics.signs.text) do assert(text:sub(1,1)==' ' and vim.fn.strdisplaywidth(text)==2) end
        vim.diagnostic.config(opts.diagnostics)
        local spec=dofile(root..'/portable/payload/nvim/lua/plugins/appearance/snacks.lua')[1]
        local column=spec.opts.statuscolumn
        assert(vim.deep_equal(column,{enabled=true}), 'original Snacks sides and priorities stay at their defaults')
        spec.config(nil,{statuscolumn=column})
        vim.wo.number=true;vim.wo.relativenumber=true;vim.wo.numberwidth=4
        vim.wo.signcolumn='yes';vim.wo.foldcolumn='0';vim.wo.wrap=false;vim.wo.foldmethod='manual'
        vim.o.showtabline=0;vim.o.laststatus=0
        vim.api.nvim_set_hl(0,'Normal',{fg=0xffffff,bg=0x171717})
        vim.api.nvim_set_hl(0,'DiagnosticSignWarn',{fg=0xffcc00})
        vim.api.nvim_set_hl(0,'GitSignsChange',{fg=0x55bbff})
        _G.diagnostics_ns=vim.api.nvim_create_namespace('diagnostic-inset-test')
        _G.git_ns=vim.api.nvim_create_namespace('diagnostic-inset-git-test')
    ''', str(ROOT))

    def row_snapshot(line):
        editor.exec_lua('vim.wait(80,function() return false end,10)')
        editor.command('redraw!')
        return editor.exec_lua('''
            local line=...;local pos=vim.fn.screenpos(0,line,1);local text=''
            for col=1,60 do text=text..vim.fn.screenstring(pos.row,col) end
            return {text=text,row=pos.row,body=pos.col,textoff=vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff,
              first=vim.fn.screenstring(pos.row,1),second=vim.fn.screenstring(pos.row,2),
              third=vim.fn.screenstring(pos.row,3),
              diagnostic_color=vim.fn.screenattr(pos.row,2)~=vim.fn.screenattr(pos.row,pos.col)}
        ''', line)

    screens=[]
    for name in ('ordinary.py', 'editable.ipynb'):
        editor.command('enew!')
        editor.current.buffer.name=str(Path('/tmp')/('glow-diagnostic-inset-'+name))
        editor.current.buffer[:]=['body_line_'+str(index) for index in range(1,13)]
        editor.current.window.cursor=(4,0)
        editor.exec_lua('''
            vim.diagnostic.set(diagnostics_ns,0,{{lnum=1,col=0,message='warning',severity=vim.diagnostic.severity.WARN}})
            vim.api.nvim_buf_set_extmark(0,git_ns,1,0,{sign_text='G ',sign_hl_group='GitSignsChange'})
        ''')
        snapshot=row_snapshot(2)
        assert snapshot['first']==' ' and snapshot['second']=='' and snapshot['third']==' ', snapshot
        assert snapshot['textoff']==8 and snapshot['body']==9, snapshot
        assert snapshot['text'].index('') < snapshot['text'].index('2') < snapshot['text'].index('G') < snapshot['text'].index('body_line_2'), snapshot
        assert snapshot['diagnostic_color'], snapshot
        screens.append({'buffer':name,'line':snapshot['text'].rstrip(),'textoff':snapshot['textoff']})
        editor.command('2mark a')
        marked=row_snapshot(2)
        assert marked['first']=='a' and marked['second']==' ' and '' not in marked['text'], 'original left mark priority remains ahead of diagnostics'
        editor.command('delmarks a')

    editor.exec_lua('''
        vim.wo.foldcolumn='1';vim.wo.fillchars='foldclose:>'
        vim.api.nvim_buf_set_extmark(0,git_ns,4,0,{sign_text='G ',sign_hl_group='GitSignsChange'})
        vim.cmd('5,8fold')
    ''')
    folded=row_snapshot(5)
    assert editor.funcs.foldclosed(5)==5
    gutter=folded['text'][:folded['body']-1]
    number=re.search(r'\d+',gutter)
    assert number and number.start() < gutter.index('>') and 'G' not in gutter, folded
    editor.exec_lua("vim.o.mouse='a'")
    editor.api.input_mouse('left','press','',0,folded['row']-1,0)
    editor.api.input_mouse('left','release','',0,folded['row']-1,0)
    assert editor.exec_lua('return vim.wait(1000,function() return vim.fn.foldclosed(5)==-1 end,10)'), 'original mouse fold callback remains active'
    print(json.dumps({'screens':screens,'warning_highlight':True,'left_mark_priority':True,'right_git_and_fold_priority':True,
                      'mouse_fold_callback':True,'extra_padding_columns':1},ensure_ascii=False))
finally:
    try: editor.command('qa!')
    except (EOFError,OSError): pass
