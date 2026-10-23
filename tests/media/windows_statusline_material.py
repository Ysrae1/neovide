"""Exercise pinned NvChad minimal statusline through real Neovim UI composites.

Host headless only: platform detection is simulated, not a Windows GPU/GUI test.
Uses installed plugin source read-only; never opens or changes a user's session.
Run with the existing notebook Python: --config ~/.config/nvim, then portable.
"""
import argparse
from pathlib import Path

import pynvim

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config', required=True, type=Path)
args = parser.parse_args()
config = str(args.config.expanduser().resolve())
lazy = str(Path('~/.local/share/nvim/lazy').expanduser())

for platform, theme, glass in [
    ('windows', 'dark', False), ('windows', 'light', False),
    ('macos', 'dark', True), ('macos', 'dark', False), ('terminal', 'dark', False),
]:
    editor = pynvim.attach('child', argv=[
        'nvim', '--embed', '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '-n',
    ])
    try:
        editor.ui_attach(120, 12, rgb=True, ext_linegrid=True, ext_hlstate=True)
        expected = editor.exec_lua(r'''
          local config,lazy,platform,theme,glass=...
          vim.opt.rtp={config,lazy..'/ui',lazy..'/base46',vim.env.VIMRUNTIME}
          local real_has=vim.fn.has
          vim.fn.has=function(feature)
            if feature=='win32' then return platform=='windows' and 1 or 0 end
            return real_has(feature)
          end
          vim.g.neovide=platform~='terminal';vim.g.neovide_liquid_glass=glass
          vim.g.neovide_normal_opacity=theme=='light' and .98 or .85
          vim.g.neovide_opacity=1
          vim.o.background=theme;vim.o.termguicolors=true;vim.o.laststatus=3
          vim.o.cmdheight=0;vim.o.showmode=false;vim.o.showtabline=0
          local selected=require('config.appearance.themes.ayu_'..theme..'_customed')
          local palette=selected.base_30
          assert(palette,'actual Ayu palette required')
          package.loaded.base46={get_theme_tb=function(name)return selected[name] or {} end}
          package.loaded.nvconfig={base46={},ui={statusline={theme='minimal',separator_style='round',
            order={'left_padding','mode','file','git','%=','lsp_msg','%=','diagnostics','lsp','cwd','cursor'},
            modules={left_padding='%#ST_EmptySpace# '}}}}
          vim.api.nvim_set_hl(0,'Normal',{fg=palette.white,bg=palette.black})
          vim.api.nvim_set_hl(0,'NeoTreeNormal',{fg=palette.white,bg=palette.one_bg})
          -- Actual pinned Base46 statusline colors and actual pinned NvChad formatter.
          local highlights=dofile(lazy..'/base46/lua/base46/integrations/statusline/minimal.lua')
          for name,attrs in pairs(highlights)do vim.api.nvim_set_hl(0,name,attrs)end
          vim.api.nvim_set_hl(0,'StatusLineNC',{bg=palette.one_bg})
          vim.api.nvim_set_hl(0,'TabLine',{link='StatusLineNC'})
          vim.api.nvim_set_hl(0,'TabLineFill',{link='TabLine'})
          local hl=function(name)return vim.api.nvim_get_hl(0,{name=name,link=false})end
          local shared={};for _,name in ipairs({'Normal','StatusLine','StatusLineNC','TabLine','TabLineFill'})do shared[name]=hl(name)end
          local bodies={};for _,name in ipairs({'St_NormalMode','St_NormalModeText','St_TerminalMode',
            'St_TerminalModeText','St_file_bg','St_file_txt','St_Pos_bg','St_Pos_txt','St_cwd_bg','St_cwd_txt'})do bodies[name]=hl(name)end
          _G.GlowTestStatusline=dofile(lazy..'/ui/lua/nvchad/stl/minimal.lua')
          vim.o.statusline='%!v:lua.GlowTestStatusline()'
          local before=hl('St_EmptySpace')
          local helper=require('config.appearance.transparency');helper.apply()
          for name,attrs in pairs(shared)do assert(vim.deep_equal(attrs,hl(name)),'shared highlight changed '..name)end
          for name,attrs in pairs(bodies)do
            local actual=hl(name);actual.blend=nil;attrs.blend=nil
            assert(vim.deep_equal(actual,attrs),'capsule RGB/style changed '..name)
          end
          if platform=='windows' then
            local panel_blend=hl('NeoTreeNormal').blend
            assert(panel_blend==40,'actual NeoTree material in both Windows themes')
            for _,name in ipairs({'St_EmptySpace','St_EmptySpace2','St_gitIcons','St_lspError',
              'St_NormalModeSep','St_TerminalModeSep','St_file_sep','St_Pos_sep','St_cwd_sep','St_sep_r'})do
              local attrs=hl(name)
              assert(attrs.bg==hl('Normal').bg and attrs.blend==panel_blend,'Windows outside material '..name)
            end
            assert(vim.g.neovide_bottom_margin_opacity==(100-panel_blend)/100,
              'Windows fractional edge should match NeoTree')
          elseif glass then
            assert(hl('St_EmptySpace').blend==80,'Mac legacy glass material changed')
            assert(vim.g.neovide_bottom_margin_opacity==.2,'Mac fractional edge changed')
          else
            assert(vim.deep_equal(before,hl('St_EmptySpace')),'non-glass Mac/terminal changed')
          end
          local once=hl('St_EmptySpace');helper.apply()
          assert(vim.deep_equal(once,hl('St_EmptySpace')),'non-idempotent refresh')
          local op=vim.g.neovide_normal_opacity
          assert(op==(theme=='light' and .98 or .85),'editor opacity changed')
          vim.cmd.redraw()
          return {normal=hl('Normal').bg,body=hl('St_NormalMode').bg,text=hl('St_NormalModeText').bg,
            file=hl('St_file_bg').bg,cwd=hl('St_cwd_bg').bg,pos=hl('St_Pos_bg').bg,
            panel_blend=hl('NeoTreeNormal').blend}
        ''', config, lazy, platform, theme, glass)
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
        footer = [(cells.get((11, col), (' ', 0))) for col in range(120)]
        text = ''.join(cell for cell, _ in footer)
        assert 'NORMAL' in text and 'Empty' in text, text
        if platform == 'windows':
            backgrounds = {expected[k] for k in ('body', 'text', 'file', 'cwd', 'pos')}
            outside, solid = 0, 0
            for _, highlight in footer:
                attrs = attributes.get(highlight, {})
                background = attrs.get('background', expected['normal'])
                if background in backgrounds:
                    solid += 1
                    assert attrs.get('blend', 0) == 0, attrs
                else:
                    outside += 1
                    assert background == expected['normal'], attrs
                    assert attrs.get('blend', 0) == expected['panel_blend'], attrs
            assert outside > 20 and solid > 20, (outside, solid)
            print(f'PASS {platform}/{theme}: actual NvChad linegrid {outside} NeoTree-material cells, {solid} solid capsule cells; shared top highlights unchanged')
        else:
            print(f'PASS {platform}/{theme}/glass={glass}: existing bar policy and capsule RGB preserved')
    finally:
        try:
            editor.command('qa!')
        except (EOFError, OSError):
            pass
