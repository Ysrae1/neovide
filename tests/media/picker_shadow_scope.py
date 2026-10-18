"""Real Snacks roles survive linked-highlight metadata and clear without polling."""
from pathlib import Path
import json
import msgpack
import pynvim

root = Path(__file__).resolve().parents[2]
nvim = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
try:
    nvim.ui_attach(120, 38, rgb=True, ext_multigrid=True, ext_hlstate=True)
    nvim.exec_lua("""
        vim.g.neovide_channel_id=77
        _G.shadows={}
        vim.rpcnotify=function(_,name,owners)
            assert(name=='neovide.window.shadow_exclusions')
            shadows[#shadows+1]=vim.deepcopy(owners)
        end
        vim.opt.rtp:prepend(vim.fn.expand('~/.local/share/nvim/lazy/snacks.nvim'))
        require('snacks').setup({picker={enabled=true}})
        vim.api.nvim_set_hl(0,'NormalFloat',{bg=0x20242b})
    """)
    nvim.exec_lua((root / 'lua/float_shadow.lua').read_text())
    nvim.exec_lua("_G.picker=Snacks.picker({items={{text='alpha'},{text='beta'}},layout={preset='default',preview=true}});vim.wait(50,function()return false end)")
    current = nvim.exec_lua("return {input=picker.input.win.win,list=picker.list.win.win,preview=picker.preview.win.win,root=picker.layout.root.win,excluded=shadows[#shadows]}")
    children = {current['input'], current['list'], current['preview']}
    assert children.issubset(set(current['excluded'])) and current['root'] not in current['excluded']
    assert len(current['excluded']) == 4, 'three panels plus one genuinely nested Box'
    nested = (set(current['excluded']) - children).pop()
    config = nvim.api.win_get_config(nested)
    assert config['relative'] == 'win' and config['win'].handle == current['root']
    nvim.command('redraw!')
    nvim.eval('1')
    metadata, used, owners, viewports = {}, {}, {}, {}
    while nvim._session._pending_messages:
        message = nvim._session._pending_messages.popleft()
        if message[0] != 'notification' or message[1] != 'redraw':
            continue
        for event in message[2]:
            for values in event[1:]:
                if event[0] == 'hl_attr_define':
                    metadata[values[0]] = values[3]
                elif event[0] == 'win_float_pos':
                    owners[values[0]] = msgpack.unpackb(values[1].data)
                elif event[0] == 'win_viewport':
                    viewports[values[0]] = msgpack.unpackb(values[1].data)
                elif event[0] == 'grid_line':
                    ids = used.setdefault(values[0], set())
                    ids.update(cell[1] for cell in values[3] if len(cell) > 1)
    names = [info.get('hi_name') for grid, owner in owners.items() if owner in children
             for hl in used.get(grid, []) for info in metadata.get(hl, [])]
    assert 'NormalFloat' in names and not any(name in names for name in
        ['SnacksPickerInput', 'SnacksPickerList', 'SnacksPickerPreview']), 'real aliases collapse to generic metadata'
    assert set(current['excluded']).issubset(set(viewports.values())), 'every excluded owner has the native viewport association'
    ordinary = nvim.exec_lua("return vim.api.nvim_open_win(vim.api.nvim_create_buf(false,true),false,{relative='editor',row=1,col=1,width=8,height=2,style='minimal'})")
    nvim.exec_lua('vim.wait(20,function()return false end)')
    assert ordinary not in nvim.exec_lua('return shadows[#shadows]')
    nvim.command('tabnew')
    nvim.exec_lua('vim.wait(20,function()return false end)')
    assert nvim.exec_lua('return shadows[#shadows]') == [], 'TabLeave clears the prior owner snapshot'
    nvim.exec_lua('pcall(function()picker:close()end);vim.wait(20,function()return false end)')
    assert nvim.exec_lua('return shadows[#shadows]') == []
    print(json.dumps({'linked_metadata_verified': True, 'excluded_children': 3,
                      'excluded_nested_box': True, 'outer_and_ordinary_preserved': True,
                      'tab_and_close_snapshot_cleared': True, 'poll_timer': False}))
finally:
    try:
        nvim.command('qa!')
    except (EOFError, OSError):
        pass
