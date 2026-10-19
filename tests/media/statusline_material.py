"""Check real Neovim composite attributes, including inherited statusline blend.

Run with the existing Notebook venv Python (pynvim required):
  statusline_material.py --config ~/.config/nvim
No user editor, plugins, window, or theme cache is changed.
"""
import argparse
from pathlib import Path

import pynvim


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config', type=Path, required=True)
args = parser.parse_args()
editor = pynvim.attach('child', argv=[
    'nvim', '--embed', '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '-n',
])
try:
    editor.ui_attach(60, 8, rgb=True, ext_linegrid=True, ext_hlstate=True)
    editor.exec_lua("""
      vim.opt.rtp={...,vim.env.VIMRUNTIME}
      vim.g.neovide=true;vim.g.neovide_liquid_glass=true
      vim.o.termguicolors=true;vim.o.laststatus=3;vim.o.cmdheight=0;vim.o.showmode=false
      vim.api.nvim_set_hl(0,'Normal',{fg=0xc9c7be,bg=0x0b0e14})
      vim.api.nvim_set_hl(0,'StatusLine',{})
      vim.api.nvim_set_hl(0,'StatusLineNC',{bg=0x12151b})
      vim.api.nvim_set_hl(0,'TabLine',{link='StatusLineNC'})
      vim.api.nvim_set_hl(0,'TabLineFill',{link='TabLine'})
      vim.api.nvim_set_hl(0,'St_NormalMode',{fg=0x0b0e14,bg=0x00bfff})
      vim.api.nvim_set_hl(0,'St_NormalModeText',{fg=0x00bfff,bg=0x1c1f25})
      vim.api.nvim_set_hl(0,'St_NormalModeSep',{fg=0x00bfff,bg=0x0b0e14})
      vim.api.nvim_set_hl(0,'St_sep_r',{fg=0x1c1f25})
      vim.api.nvim_set_hl(0,'St_EmptySpace',{fg=0xc9c7be})
      local top=vim.api.nvim_get_hl(0,{name='TabLineFill',link=false})
      vim.o.statusline='%#St_NormalModeSep#L%#St_NormalMode#III%#St_NormalModeText# NORMAL %#St_sep_r#R%#St_EmptySpace# tail %='
      require('config.appearance.transparency').apply()
      assert(vim.deep_equal(top,vim.api.nvim_get_hl(0,{name='TabLineFill',link=false})),
        'footer material leaked through the shared StatusLineNC/TabLine link')
      vim.cmd.redraw()
    """, str(args.config.expanduser().resolve()))
    editor.eval('1')
    attributes, cells = {}, {}
    for message in editor._session._pending_messages:
        if message[0] != 'notification' or message[1] != 'redraw':
            continue
        for event in message[2]:
            if event[0] == 'hl_attr_define':
                for item in event[1:]:
                    attributes[item[0]] = item[1]
            elif event[0] == 'grid_line':
                for grid, row, column, entries, *_ in event[1:]:
                    if grid != 1:
                        continue
                    highlight = 0
                    for entry in entries:
                        if len(entry) > 1:
                            highlight = entry[1]
                        for _ in range(entry[2] if len(entry) > 2 else 1):
                            cells[row, column] = (entry[0], highlight)
                            column += 1

    def at(column):
        return attributes[cells[7, column][1]]

    blend = at(20).get('blend', 0)
    assert blend > 0, 'surrounding statusline should use glass material'
    assert at(2).get('blend', 0) == at(7).get('blend', 0) == 0, 'capsule inherited glass blend'
    assert at(2)['background'] == 0x00bfff and at(7)['background'] == 0x1c1f25
    assert at(0).get('blend', 0) == at(12).get('blend', 0) == blend
    print(f'PASS: actual composite statusline blend={blend}, solid capsule bodies, cap material, unchanged top TabLine')
finally:
    try:
        editor.command('qa!')
    except (EOFError, OSError):
        pass
