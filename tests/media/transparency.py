"""Actual normal-grid highlight propagation; no Neovide/GUI session touched.
Run with the Notebook venv Python (pynvim required).
"""
from pathlib import Path
import sys
import pynvim

ROOT = Path(__file__).resolve().parents[2]
if '--split-strip-only' in sys.argv or '--avante-strip-only' in sys.argv:
    avante = '--avante-strip-only' in sys.argv
    probe = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
    try:
        probe.ui_attach(120, 22, rgb=True, ext_linegrid=True, ext_hlstate=True)
        probe.exec_lua('vim.opt.rtp:prepend(...)', str(ROOT / 'portable/payload/nvim'))
        points = probe.exec_lua("""
          local avante=...
          vim.g.neovide=true;vim.g.neovide_liquid_glass=true;vim.g.neovide_normal_opacity=.78
          vim.o.laststatus=3;vim.o.termguicolors=true;vim.o.showmode=false
          vim.api.nvim_set_hl(0,'Normal',{fg=0xc9c7be,bg=0x0b0e14})
          vim.api.nvim_set_hl(0,'NeoTreeNormal',{bg=0x05080e,blend=40})
          vim.api.nvim_set_hl(0,'NeoTreeWinSeparator',{fg=0x05080e,bg=0x05080e,blend=40})
          vim.api.nvim_set_hl(0,'WinSeparator',{fg=0x05080e,bg=0x05080e,blend=40})
          vim.api.nvim_set_hl(0,'AvanteSidebarNormal',{fg=0xc9c7be,bg=0x0b0e14,blend=40})
          vim.api.nvim_set_hl(0,'AvanteSidebarWinSeparator',{fg=0x05080e,bg=0x05080e,blend=40})
          vim.api.nvim_buf_set_lines(0,0,-1,false,{'source text'})
          vim.bo.filetype='tex';local source=vim.api.nvim_get_current_win()
          if avante then vim.wo.winhighlight='CursorLine:Normal,WinSeparator:AvanteSidebarWinSeparator' end
          vim.cmd('rightbelow vnew');vim.api.nvim_buf_set_lines(0,0,-1,false,{'PDF placeholder'})
          vim.bo.filetype='glow_pdf';local pdf=vim.api.nvim_get_current_win()
          local panel_hl='CursorLine:Normal,WinSeparator:AvanteSidebarWinSeparator,Normal:AvanteSidebarNormal'
          if avante then vim.bo.filetype='Avante';vim.wo.winhighlight=panel_hl end
          local before={vim.api.nvim_win_get_position(pdf),vim.api.nvim_win_get_width(source),vim.api.nvim_win_get_width(pdf)}
          local tree=vim.api.nvim_get_hl(0,{name='NeoTreeNormal',link=false})
          local helper=require('config.appearance.transparency');helper.setup();helper.apply();vim.cmd.redraw()
          assert(vim.deep_equal(before,{vim.api.nvim_win_get_position(pdf),vim.api.nvim_win_get_width(source),vim.api.nvim_win_get_width(pdf)}))
          assert(vim.deep_equal(tree,vim.api.nvim_get_hl(0,{name='NeoTreeNormal',link=false})),'tree material changed')
          if avante then
            assert(vim.wo[source].winhighlight=='CursorLine:Normal,WinSeparator:AvanteSidebarWinSeparator','adjacent glass sidebar owns the blank boundary')
            assert(vim.wo[pdf].winhighlight==panel_hl,'Avante panel mappings unchanged')
            vim.api.nvim_set_option_value('winhighlight','CursorLine:Normal,WinSeparator:AvanteSidebarWinSeparator',{win=source})
            assert(vim.wait(500,function()return vim.wo[source].winhighlight=='CursorLine:Normal,WinSeparator:AvanteSidebarWinSeparator'end,10),'plugin remap reapplication')
          end
          return {separator={0,vim.api.nvim_win_get_width(source)},source={0,20},pdf={0,before[1][2]+25}}
        """, avante)
        probe.eval('1')
        attrs, cells = {}, {}
        for message in probe._session._pending_messages:
            if message[0] != 'notification' or message[1] != 'redraw':
                continue
            for event in message[2]:
                if event[0] == 'hl_attr_define':
                    for item in event[1:]: attrs[item[0]] = item[1]
                elif event[0] == 'grid_line':
                    for grid, row, column, entries, *_ in event[1:]:
                        if grid != 1: continue
                        highlight = 0
                        for entry in entries:
                            if len(entry) > 1: highlight = entry[1]
                            for _ in range(entry[2] if len(entry) > 2 else 1):
                                cells[(row, column)] = (entry[0], highlight); column += 1
        materials = {}
        for name, point in points.items():
            assert 0 <= point[0] < 22 and 0 <= point[1] < 120
            # A cleared grid starts with default-highlight blanks; Neovim
            # need not resend unchanged empty space in either editor window.
            text, highlight = cells.get(tuple(point), (' ', 0))
            assert text == ' ', (name, point, text)
            hl = attrs.get(highlight, {})
            materials[name] = (hl.get('background', 0x0b0e14), hl.get('blend', 0))
        assert materials['source'] == (0x0b0e14, 0), materials
        assert materials['separator'] == (0x0b0e14, 40 if avante else 0), materials
        assert materials['pdf'] == (0x0b0e14, 40 if avante else 0), materials
        print('PASS: actual Neovim separator follows adjacent glass sidebar or left editor beside opaque PDF; adjacent ' + ('Avante material/mappings' if avante else 'PDF base') + ', blank drag column/layout and Tree material preserved (GUI not tested)')
    finally:
        try: probe.command('qa!')
        except Exception: pass
    raise SystemExit(0)

nvim = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
try:
    nvim.ui_attach(50, 15, rgb=True, ext_linegrid=True, ext_hlstate=True)
    nvim.exec_lua('vim.opt.rtp:prepend(...)', str(ROOT / 'portable/payload/nvim'))
    nvim.exec_lua("""
      vim.g.neovide=true;vim.g.neovide_liquid_glass=true;vim.o.termguicolors=true
      vim.api.nvim_set_hl(0,'Normal',{fg=0x5c6166,bg=0xfafafa})
      vim.api.nvim_set_hl(0,'Visual',{bg=0xeeeeee,bold=true})
      vim.api.nvim_set_hl(0,'GlowNotebookLanguage',{fg=0xffffff,bg=0xffd68a})
      vim.api.nvim_set_hl(0,'StatusLine',{fg=0xabcdef,bg=0x123456})
      vim.api.nvim_set_hl(0,'PmenuSel',{fg=0xffffff,bg=0x0066aa,bold=true})
      vim.api.nvim_set_hl(0,'TelescopePromptTitle',{fg=0xffffff,bg=0x228855})
      vim.api.nvim_set_hl(0,'AvanteTitle',{fg=0x171717,bg=0x98c379})
      vim.api.nvim_set_hl(0,'AvanteReversedTitle',{fg=0x98c379,bg=0x242933})
      _global_hl=function(name)return vim.api.nvim_get_hl_by_id(vim.fn.hlID(name),true)end
      _visual=_global_hl('Visual')
      _capsule=_global_hl('GlowNotebookLanguage')
      _normal=_global_hl('Normal')
      _solid={};for _,name in ipairs({'StatusLine','PmenuSel','TelescopePromptTitle','AvanteTitle'}) do _solid[name]=_global_hl(name) end
      _theme={NeoTreeNormal={bg=0xf3f3f3},NeoTreeNormalNC={bg=0xf3f3f3},
        NeoTreeCursorLine={bg=0xfafafa},CursorLine={bg=0xefefef},
        WinSeparator={fg=0x556677},NeoTreeWinSeparator={fg=0x181a1f,bg=0x181a1f},
        AvanteSidebarWinSeparator={fg=0x242933,bg=0x242933},
        AvanteSidebarWinHorizontalSeparator={fg=0x667788,bg=0x242933},
        AvantePromptInput={}}
      _transparency=require('config.appearance.transparency');_transparency.setup();_transparency.apply()
      assert(vim.fn.hlexists('NeoTreeNormal')==0,'do not pre-create absent plugin groups')
      for name,attrs in pairs(_theme) do vim.api.nvim_set_hl(0,name,attrs) end
      _surfaces={NormalFloat={bg=0xe8ebef,fg=0x334455},FloatBorder={bg=0xe8ebef,fg=0x00aabb},
        Pmenu={bg=0xe0e4ea,fg=0x223344},CmpPmenu={bg=0xddeeff,fg=0x335577},CmpDoc={bg=0xeeeeef},
        TelescopeNormal={bg=0xe1e2e3,fg=0x334466},SnacksInputNormal={bg=0xd5d6d7,fg=0x112233},
        SnacksPickerList={bg=0xd6d7d8,fg=0x223355},SnacksNotifierInfo={bg=0xd9dadb,fg=0x123abc}}
      for name,attrs in pairs(_surfaces) do vim.api.nvim_set_hl(0,name,attrs) end
      for name,target in pairs({WhichKeyNormal='NormalFloat',BlinkCmpMenu='CmpPmenu',
        NoicePopup='NormalFloat',NoiceCmdlinePopup='Normal',MasonNormal='NormalFloat',LazyNormal='NormalFloat',
        AvanteSidebarNormal='NormalFloat',AvantePromptInputBorder='NormalFloat',AvantePopupHint='NormalFloat'}) do
        vim.api.nvim_set_hl(0,name,{link=target}) end
      vim.api.nvim_exec_autocmds('User',{pattern='LazyLoad'})
      assert(vim.wait(500,function()return vim.api.nvim_get_hl(0,{name='NeoTreeNormal'}).blend==40 end,10))
      for name,attrs in pairs(_surfaces) do
        local actual=_global_hl(name)
        assert(actual.blend==40,name..' blend')
        assert(actual.background==attrs.bg and actual.foreground==attrs.fg,name..' original colors')
      end
      for name,target in pairs({WhichKeyNormal='NormalFloat',BlinkCmpMenu='CmpPmenu',NoicePopup='NormalFloat'}) do
        assert(vim.api.nvim_get_hl(0,{name=name}).link==target,'unnecessary unlink '..name)
      end
      for name,attrs in pairs(_theme) do
        local actual=_global_hl(name)
        assert(actual.blend==(name=='WinSeparator' and 0 or 40),name..' panel/separator blend')
        local inherited=name=='AvantePromptInput'
        local tree_separator=name=='NeoTreeWinSeparator'
        local avante_separator=name=='AvanteSidebarWinSeparator' or name=='AvanteSidebarWinHorizontalSeparator'
        assert(actual.background==(name=='WinSeparator' and _normal.background or tree_separator and _theme.NeoTreeNormal.bg or avante_separator and _surfaces.NormalFloat.bg or inherited and _normal.background or attrs.bg) and
          actual.foreground==(name=='WinSeparator' and _normal.background or tree_separator and _theme.NeoTreeNormal.bg or avante_separator and _surfaces.NormalFloat.bg or inherited and _normal.foreground or attrs.fg),name..' original/inherited/matched colors')
      end
      for _,name in ipairs({'AvanteSidebarNormal','AvantePromptInputBorder','AvantePopupHint'}) do
        assert(_global_hl(name).blend==40,name..' same glass material')
      end
      vim.wo.winhighlight='Normal:NeoTreeNormal,NormalNC:NeoTreeNormalNC,CursorLine:NeoTreeCursorLine'
      vim.wo.cursorline=true
      vim.bo.filetype='neo-tree'
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'current tree','normal tree'})
      _transparency.apply()
      vim.cmd.redraw()
    """)
    nvim.eval('1')
    attributes, rows = {}, {}
    for message in nvim._session._pending_messages:
        if message[0] != 'notification' or message[1] != 'redraw':
            continue
        for event in message[2]:
            if event[0] == 'hl_attr_define':
                for highlight in event[1:]:
                    attributes[highlight[0]] = highlight[1]
            elif event[0] == 'grid_line':
                for line in event[1:]:
                    if line[0] == 1 and line[1] in (0, 1) and line[2] == 0:
                        rows[line[1]] = line[3][0][1]
    assert attributes[rows[0]]['background'] == 0xfafafa
    assert attributes[rows[1]]['background'] == 0xf3f3f3
    assert attributes[rows[0]]['blend'] == attributes[rows[1]]['blend'] == 40, (rows, attributes)
    nvim.exec_lua("""
      -- Simulate Base46's nested scheduled integration replay, which overwrites
      -- these groups after ColorScheme handlers have started.
      for name,attrs in pairs(_theme) do vim.api.nvim_set_hl(0,name,attrs) end
      vim.api.nvim_create_autocmd('ColorScheme',{callback=function()
        vim.schedule(function()vim.schedule(function()
          for name,attrs in pairs(_theme) do vim.api.nvim_set_hl(0,name,attrs) end
        end)end)
      end})
      vim.api.nvim_exec_autocmds('ColorScheme',{pattern='test'})
      assert(vim.wait(500,function()
        for name in pairs(_theme) do if _global_hl(name).blend~=(name=='WinSeparator' and 0 or 40) then return false end end
        return true
      end,10),'transparency survives theme integration replay')
      assert(vim.deep_equal(_visual,_global_hl('Visual')))
      assert(vim.deep_equal(_capsule,_global_hl('GlowNotebookLanguage')))
      assert(vim.deep_equal(_normal,_global_hl('Normal')))
      assert(_global_hl('CursorLine').background==0xefefef,'keep theme RGB')
      assert(_global_hl('NeoTreeWinSeparator').background==_global_hl('NeoTreeNormal').background and
        _global_hl('NeoTreeWinSeparator').foreground==_global_hl('NeoTreeNormal').background,'tree separator matches its material')
      for name,attrs in pairs(_solid) do assert(vim.deep_equal(attrs,_global_hl(name)),'solid '..name) end
      assert(_global_hl('AvanteReversedTitle').foreground==0x98c379 and
        _global_hl('AvanteReversedTitle').background==_global_hl('AvanteSidebarNormal').background and
        _global_hl('AvanteReversedTitle').blend==40,'cap outer corner uses panel background')
      -- A container linked to Normal needs its own alpha but must keep following
      -- theme changes without forcing Normal, text or unrelated groups to blend.
      vim.api.nvim_set_hl(0,'Normal',{fg=0x112244,bg=0xf0f1f2})
      _transparency.apply()
      assert(_global_hl('NoiceCmdlinePopup').background==0xf0f1f2)
      assert(_global_hl('NoiceCmdlinePopup').foreground==0x112244)
      assert(_global_hl('NoiceCmdlinePopup').blend==40)
      assert(_global_hl('AvantePromptInput').background==0xf0f1f2 and
        _global_hl('AvantePromptInput').foreground==0x112244 and _global_hl('AvantePromptInput').blend==40)
      assert(_global_hl('Normal').blend==nil)
      local popup=vim.api.nvim_create_buf(false,true)
      vim.api.nvim_buf_set_lines(popup,0,-1,false,{'container'})
      _popup=vim.api.nvim_open_win(popup,false,{relative='editor',row=4,col=10,width=18,height=3,border='rounded'})
      vim.api.nvim_set_option_value('winhighlight','Normal:SnacksInputNormal,NormalFloat:SnacksInputNormal,FloatBorder:FloatBorder',{win=_popup})
      vim.cmd.redraw()
    """)
    # The real float UI sends the container blend alongside its distinct colors.
    nvim.eval('1')
    actual_float = False
    for message in nvim._session._pending_messages:
        if message[0] == 'notification' and message[1] == 'redraw':
            for event in message[2]:
                if event[0] == 'hl_attr_define':
                    for hl in event[1:]:
                        if hl[1].get('background') == 0xd5d6d7 and hl[1].get('blend') == 40:
                            actual_float = True
    assert actual_float, 'float container blend did not reach actual UI attributes'
    # Render the real separator/window mappings used by Neo-tree and Avante.
    nvim.api.win_close(nvim.exec_lua('return _popup'), True)
    nvim.ui_try_resize(92, 24)
    nvim.exec_lua("""
      vim.wo.winhighlight='Normal:NeoTreeNormal,NormalNC:NeoTreeNormalNC,WinSeparator:NeoTreeWinSeparator'
      vim.wo.fillchars='vert:│';vim.wo.cursorline=false
      local tree=vim.api.nvim_get_current_win();_tree=tree
      vim.cmd('rightbelow vnew');vim.api.nvim_buf_set_lines(0,0,-1,false,{'editor'})
      vim.wo.winhighlight='';vim.wo.fillchars='vert:│'
      local editor=vim.api.nvim_get_current_win()
      vim.cmd('rightbelow vnew');vim.api.nvim_buf_set_lines(0,0,-1,false,{'Avante panel'})
      vim.bo.filetype='Avante'
      vim.wo.winhighlight='Normal:AvanteSidebarNormal,WinSeparator:AvanteSidebarWinSeparator'
      vim.wo.fillchars='vert:│'
      vim.wo.winbar='%#AvanteSidebarWinHorizontalSeparator# Panel %=%#AvanteTitle# Solid '
      local avante=vim.api.nvim_get_current_win()
      vim.cmd('rightbelow vnew');vim.api.nvim_buf_set_lines(0,0,-1,false,{'editor'})
      vim.wo.winhighlight='';vim.wo.fillchars='vert:│'
      local prompt=vim.api.nvim_create_buf(false,true)
      vim.api.nvim_buf_set_lines(prompt,0,-1,false,{'Avante prompt'})
      local win=vim.api.nvim_open_win(prompt,false,{relative='editor',row=10,col=4,width=24,height=3,border='rounded'})
      vim.api.nvim_set_option_value('winhighlight','Normal:AvantePromptInput,NormalFloat:AvantePromptInput,FloatBorder:AvantePromptInputBorder',{win=win})
      _transparency.apply();vim.cmd.redraw()
      assert(vim.api.nvim_win_call(tree,function()return vim.opt_local.fillchars:get().vert==' 'end),'Neovide tree separator is blank')
      assert(vim.api.nvim_win_call(editor,function()return vim.opt_local.fillchars:get().vert==' 'end),'all Neovide split separators are blank')
      _component_cells={}
      for _,item in ipairs({{'NeoTreeWinSeparator',tree},{'AvanteSidebarWinSeparator',editor},{'AvanteSidebarWinSeparator',avante}}) do
        local origin=vim.api.nvim_win_get_position(item[2])
        local body=vim.fn.screenpos(item[2],1,1)
        _component_cells[#_component_cells+1]={name=item[1],row=body.row,col=origin[2]+vim.api.nvim_win_get_width(item[2])+1}
      end
      local body=vim.fn.screenpos(avante,1,1)
      _component_cells[#_component_cells+1]={name='AvanteSidebarNormal',row=body.row,col=body.col}
      _component_cells[#_component_cells+1]={name='AvanteSidebarWinHorizontalSeparator',row=body.row-1,col=body.col+1}
      local prompt_body=vim.fn.screenpos(win,1,1)
      _component_cells[#_component_cells+1]={name='AvantePromptInput',row=prompt_body.row,col=prompt_body.col}
      _component_cells[#_component_cells+1]={name='AvantePromptInputBorder',row=prompt_body.row-1,col=prompt_body.col+1}
    """)
    nvim.eval('1')
    cells, attributes = {}, {}
    for message in nvim._session._pending_messages:
        if message[0] == 'notification' and message[1] == 'redraw':
            for event in message[2]:
                if event[0] == 'hl_attr_define':
                    for hl in event[1:]:
                        attributes[hl[0]] = hl[1]
                elif event[0] == 'grid_line':
                    for line in event[1:]:
                        if line[0] != 1:
                            continue
                        column, highlight = line[2], 0
                        for cell in line[3]:
                            if len(cell) >= 2:
                                highlight = cell[1]
                            for _ in range(cell[2] if len(cell) >= 3 else 1):
                                cells[(line[1], column)] = (cell[0], highlight)
                                column += 1
    for position in nvim.exec_lua('return _component_cells'):
        cell = cells[(position['row'] - 1, position['col'] - 1)]
        if position['name'].startswith('AvantePromptInput'):
            # Single-grid Neovim composes floating cells against the underlying
            # split. Verify its original material is sent before composition.
            expected = nvim.exec_lua('return _global_hl(...)', position['name'])
            assert any(hl.get('blend') == 40 and hl.get('foreground') == expected.get('foreground') and
                       hl.get('background') == expected.get('background') for hl in attributes.values()), position
            assert cell[0].strip(), (position, cell)
        else:
            assert attributes[cell[1]].get('blend', 0) == (0 if position['name'] == 'WinSeparator' else 40), (position, cell, attributes[cell[1]])
            if position['name'] in ['NeoTreeWinSeparator', 'WinSeparator', 'AvanteSidebarWinSeparator']:
                expected_background = {'WinSeparator': 0xf0f1f2, 'AvanteSidebarWinSeparator': 0xe8ebef, 'NeoTreeWinSeparator': 0xf3f3f3}[position['name']]
                assert cell[0] == ' ' and attributes[cell[1]]['foreground'] == attributes[cell[1]]['background'] == expected_background
    nvim.exec_lua("""
      local treebuf=vim.api.nvim_win_get_buf(_tree)
      vim.bo[treebuf].filetype='python';_transparency.apply()
      assert(vim.api.nvim_win_call(_tree,function()return vim.opt_local.fillchars:get().vert==' 'end),'ordinary Python keeps its blank separator')
      assert(_global_hl('WinSeparator').foreground==_global_hl('Normal').background,'ordinary separator follows editor base')
      vim.o.laststatus=3 -- The app uses one global statusline; divider rows are fillchars.
      vim.cmd('rightbelow new')
      vim.wo.winbar='';vim.wo.winhighlight=''
      vim.wo.fillchars='vert:│,horiz:─,verthoriz:┼,vertleft:┤,vertright:├,horizup:┴,horizdown:┬,eob:~,fold:-,lastline:@'
      local lower=vim.api.nvim_get_current_win()
      local before={}
      for _,win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative=='' then
          before[win]={vim.api.nvim_win_get_position(win),vim.api.nvim_win_get_width(win),vim.api.nvim_win_get_height(win)}
        end
      end
      _transparency.apply();vim.cmd.redraw()
      for win,geometry in pairs(before) do
        assert(vim.deep_equal(geometry,{vim.api.nvim_win_get_position(win),vim.api.nvim_win_get_width(win),vim.api.nvim_win_get_height(win)}),'separator padding changed layout/hit positions')
        local values=vim.api.nvim_win_call(win,function()return vim.opt_local.fillchars:get()end)
        for _,key in ipairs({'vert','horiz','verthoriz','vertleft','vertright','horizup','horizdown'}) do assert(values[key]==' ',key) end
      end
      local values=vim.opt_local.fillchars:get()
      assert(values.eob=='~' and values.fold=='-' and values.lastline=='@','other local fillchars changed')
      local origin=vim.api.nvim_win_get_position(lower)
      for col=origin[2]+1,origin[2]+vim.api.nvim_win_get_width(lower) do
        assert(vim.fn.screenstring(origin[1],col)==' ',vim.inspect({reason='horizontal split/cross must be blank',row=origin[1],col=col,char=vim.fn.screenstring(origin[1],col),laststatus=vim.o.laststatus,statusline=vim.wo.statusline}))
      end
      for _,key in ipairs({'vert','horiz','verthoriz','vertleft','vertright','horizup','horizdown'}) do
        assert(vim.opt_global.fillchars:get()[key]==' ','new windows must inherit blank separators')
      end
    """)
finally:
    try:
        nvim.command('qa!')
    except Exception:
        pass

terminal = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
try:
    terminal.exec_lua('vim.opt.rtp:prepend(...)', str(ROOT / 'portable/payload/nvim'))
    terminal.exec_lua("""
      vim.api.nvim_set_hl(0,'NormalFloat',{fg=0x334455,bg=0x445566})
      vim.api.nvim_set_hl(0,'CursorLine',{bg=0x223344})
      vim.api.nvim_set_hl(0,'WhichKeyNormal',{link='NormalFloat'})
      vim.api.nvim_set_hl(0,'WinSeparator',{fg=0x112233,bg=0x223344})
      vim.api.nvim_set_hl(0,'NeoTreeWinSeparator',{fg=0x334455,bg=0x445566})
      vim.api.nvim_set_hl(0,'AvanteSidebarNormal',{link='NormalFloat'})
      vim.api.nvim_set_hl(0,'AvanteSidebarWinSeparator',{fg=0x556677,bg=0x667788})
      vim.api.nvim_set_hl(0,'AvantePromptInput',{})
      vim.o.guifont='terminal sentinel:h17'
      vim.g.neovide_normal_opacity=0.91
      vim.opt_global.fillchars={vert='!',horiz='=',verthoriz='+',eob='~'}
      vim.opt_local.fillchars={vert='|',eob='#'}
      local global_fillchars=vim.api.nvim_get_option_value('fillchars',{scope='global'})
      local local_fillchars=vim.wo.fillchars
      local groups=vim.api.nvim_get_hl(0,{})
      local font,opacity=vim.o.guifont,vim.g.neovide_normal_opacity
      local helper=require('config.appearance.transparency');helper.setup();helper.apply()
      require('config.platform.neovide')
      vim.api.nvim_exec_autocmds('ColorScheme',{pattern='terminal-test'})
      vim.wait(50)
      assert(vim.deep_equal(groups,vim.api.nvim_get_hl(0,{})),'terminal highlight mutation')
      assert(vim.o.guifont==font and vim.g.neovide_normal_opacity==opacity,'terminal font/opacity mutation')
      assert(vim.g.neovide_opacity==nil and vim.g.neovide_liquid_glass==nil,'terminal Neovide variables')
      assert(vim.fn.exists('#GlowBackgroundTransparency')==0,'terminal setup installed hooks')
      assert(vim.api.nvim_get_option_value('fillchars',{scope='global'})==global_fillchars and vim.wo.fillchars==local_fillchars,'terminal fillchars mutation')
    """)
finally:
    try:
        terminal.command('qa!')
    except Exception:
        pass
# Exercise the actual pinned Snacks section and its private terminal float.
# A separate editor keeps its subprocess/window lifecycle isolated from above.
dashboard = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
try:
    dashboard.ui_attach(70, 18, rgb=True, ext_linegrid=True, ext_hlstate=True, ext_multigrid=True)
    dashboard.exec_lua('vim.opt.rtp:prepend(...);vim.opt.rtp:prepend(vim.fn.expand("~/.local/share/nvim/lazy/snacks.nvim"))', str(ROOT / 'portable/payload/nvim'))
    result = dashboard.exec_lua(r"""
      vim.g.neovide=true
      vim.api.nvim_set_hl(0,'Normal',{fg=0xcccccc,bg=0x171717})
      local snacks=require('snacks')
      local section=snacks.dashboard.sections.terminal
      local helper=require('config.appearance.transparency')
      local name='SnacksDashboardTerminal'
      local original=vim.api.nvim_get_hl(0,{name=name})
      helper.setup();helper.apply()
      assert(vim.deep_equal(original,vim.api.nvim_get_hl(0,{name=name})),'no Glass: dashboard untouched')
      vim.g.neovide=false;vim.g.neovide_liquid_glass=true;helper.apply()
      assert(vim.deep_equal(original,vim.api.nvim_get_hl(0,{name=name})),'terminal frontend: dashboard untouched')
      vim.g.neovide=true;helper.apply()
      assert(vim.api.nvim_get_hl(0,{name=name,link=false}).blend==40,'Glass dashboard uses tree material')
      assert(vim.api.nvim_get_hl(0,{name='Normal',link=false}).blend==nil,'ordinary terminal base remains unchanged')
      _dashboard_close={}
      local owner={opts={width=24},win=vim.api.nvim_get_current_win(),trace=function()end,
        on=function(_,fn)_dashboard_close[#_dashboard_close+1]=fn end}
      local item=section({height=4,ttl=0,cmd={'/bin/sh','-c',
        "printf '\\033[38;2;0;255;0mGREEN\\033[0m\nrow2\nrow3\n'; sleep 4"}})(owner)
      item.render(nil,{1,1})
      local win
      assert(vim.wait(1500,function()
        for _,candidate in ipairs(vim.api.nvim_list_wins()) do
          if vim.wo[candidate].winhighlight:find(name,1,true) then
            local buf=vim.api.nvim_win_get_buf(candidate)
            if table.concat(vim.api.nvim_buf_get_lines(buf,0,-1,false),'\n'):find('GREEN',1,true) then win=candidate;return true end
          end
        end
      end,10),'real dashboard terminal output')
      assert(vim.wo[win].winhighlight=='TermCursorNC:'..name..',NormalFloat:'..name,'upstream actual terminal mapping')
      vim.cmd.redraw()
      return {win=win,foreground=0x00ff00,background=0x171717}
    """)
    dashboard.eval('1')
    attributes, cells, grids = {}, [], {}
    for message in dashboard._session._pending_messages:
        if message[0] != 'notification' or message[1] != 'redraw':
            continue
        for event in message[2]:
            if event[0] == 'hl_attr_define':
                for hl in event[1:]:
                    attributes[hl[0]] = hl[1]
            elif event[0] == 'win_float_pos':
                for position in event[1:]:
                    grids[getattr(position[1], 'handle', position[1])] = position[0]
            elif event[0] == 'grid_line':
                for line in event[1:]:
                    active = 0
                    for cell in line[3]:
                        if len(cell) >= 2:
                            active = cell[1]
                        cells.append((line[0], cell[0], active))
    assert len(grids) == 1, grids  # The real section owns the only floating grid.
    panel = next(iter(grids.values()))
    green = [attributes[hl] for grid, text, hl in cells if grid == panel and text in 'GREEN' and attributes[hl].get('foreground') == result['foreground']]
    blank = [attributes[hl] for grid, text, hl in cells if grid == panel and text == ' ']
    assert green and all(hl.get('blend') == 40 and hl.get('background') == result['background'] for hl in green), (green, [(text, attributes[hl]) for grid, text, hl in cells if grid == panel])
    assert blank and any(hl.get('blend') == 40 for hl in blank), blank
    dashboard.exec_lua("""
      vim.g.neovide_liquid_glass=false
      require('config.appearance.transparency').apply()
      assert(vim.api.nvim_get_hl(0,{name='SnacksDashboardTerminal'}).link=='SnacksDashboardNormal','Glass off restores original theme link')
    """)
finally:
    try:
        dashboard.exec_lua('for _,close in ipairs(_dashboard_close or {}) do pcall(close) end')
        dashboard.command('qa!')
    except Exception:
        pass
print('PASS: blend40; split/panel/theme guards; actual Snacks dashboard terminal ANSI and blank backgrounds share Glass material; ordinary terminal unchanged')
