"""Real Noice/Nui layered windows and multigrid attributes; no GUI or kernel.

Run with the Notebook venv Python (pynvim required). GLOW_TEST_CONFIG selects
local or portable Lua. Uses already installed Noice/Nui/WhichKey/Snacks; installs nothing and
never attaches to an existing editor. Do not use nvim__inspect_cell: that debug
API changes highlights on the Neovim version covered by this regression.
"""
from pathlib import Path
import json
import os

import pynvim


ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get("GLOW_TEST_CONFIG", ROOT / "portable/payload/nvim"))
PLUGINS = Path.home() / ".local/share/nvim/lazy"
for plugin in ("noice.nvim", "nui.nvim", "snacks.nvim", "which-key.nvim"):
    assert (PLUGINS / plugin / "lua").is_dir(), f"installed dependency required: {plugin}"

editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n"])
try:
    editor.ui_attach(160, 50, rgb=True, ext_multigrid=True)
    editor.exec_lua("""
      local config,plugins=...
      vim.opt.rtp={config,plugins..'/nui.nvim',plugins..'/noice.nvim',plugins..'/snacks.nvim',plugins..'/which-key.nvim',vim.env.VIMRUNTIME}
      vim.g.neovide=true
      local theme_name=vim.env.GLOW_TEST_THEME or 'dark'
      vim.o.background=theme_name
      local theme=require('config.appearance.themes.ayu_'..theme_name..'_customed')
      package.loaded.base46={get_theme_tb=function(kind)return theme[kind] or {} end}
      local a=vim.api
      a.nvim_set_hl(0,'Normal',{fg=0xffffff,bg=tonumber(theme.base_30.black:sub(2),16)})
      a.nvim_set_hl(0,'NormalFloat',{link='Normal'})
      a.nvim_set_hl(0,'PopupLayerSelection',{fg=0xffea00,bg=0x345678,blend=0})
      require('noice.config').setup({log='/dev/null',cmdline={enabled=false},messages={enabled=false},
        popupmenu={enabled=false},lsp={hover={enabled=false},signature={enabled=false},
        message={enabled=false},progress={enabled=false}},presets={command_palette=true}})
      _profiles=require('config.appearance.popup_materials')
      _profiles.config.noice_cmdline={mode='custom',blend=60}
      _profiles.config.which_key={mode='custom',blend=60}
      require('which-key').setup({delay=0,triggers={},notify=false,show_help=true,show_keys=true,
        icons={mappings=false},win={no_overlap=false,width=70,height=10,row=10,col=5,border='none'},
        plugins={marks=false,registers=false,spelling={enabled=false},presets={operators=false,
          motions=false,text_objects=false,windows=false,nav=false,z=false,g=false}},
        spec={{'gz',group='Material regression'},{'gza',function()end,desc='Alpha'},
          {'gzb',function()end,desc='Beta'}}})
      _wk_view=require('which-key.view')
      assert(vim.wait(1000,function()return require('which-key.config').loaded end,10),'real WhichKey setup')
      function _show_whichkey()
        local mode=require('which-key.buf').get({mode='n',buf=vim.api.nvim_get_current_buf(),update=true})
        local node=mode and mode.tree:find('gz',{expand=true})
        assert(node and node:is_group(),'fixed real WhichKey mapping tree')
        require('which-key.state').state={mode=mode,node=node,filter={mode='n',keys='gz'},
          show=true,started=vim.uv.hrtime()/1e6}
        _material_show_calls=0
        _wk_view.show()
        _last_material_show_calls=_material_show_calls
        assert(_wk_view.view and _wk_view.footer,'real WhichKey main/footer creation')
        return {_wk_view.view.win,_wk_view.footer.win}
      end
      _transparency=require('config.appearance.transparency');_transparency.setup()
      _view=require('noice.view').get_view('cmdline_popup',{scrollbar=false})
      function _show_noice()
        _view:set({require('noice.message')('cmdline','cmdline','echo 42')},{format=false})
        _view:display()
        assert(_view._errors==0 and _view._nui.winid and _view._nui.border.winid,'real Noice view creation')
        a.nvim_buf_set_extmark(_view._nui.bufnr,a.nvim_create_namespace('popup-layer-selection'),0,5,
          {end_col=7,hl_group='PopupLayerSelection',priority=300})
        vim.wait(100)
        return {_view._nui.border.winid,_view._nui.winid}
      end
      function _snapshot(win)
        local ns=a.nvim_get_hl_ns({winid=win})
        local h=a.nvim_get_hl(ns,{})
        return {win=win,namespace=ns,normal=h.Normal,normalnc=h.NormalNC,
          material=vim.w[win].glow_popup_material,config=a.nvim_win_get_config(win),winblend=vim.wo[win].winblend}
      end
      function _floating(role,config)
        local buf=a.nvim_create_buf(false,true)
        vim.bo[buf].filetype='wk';a.nvim_buf_set_lines(buf,0,-1,false,{'layered popup text'})
        local win=a.nvim_open_win(buf,false,config)
        vim.wo[win].winhighlight='Normal:'..role
        return win
      end
    """, str(CONFIG), str(PLUGINS))

    editor.exec_lua("local channel,path=...;vim.g.neovide_channel_id=channel;dofile(path)", editor.channel_id, str(ROOT / "lua/float_shadow.lua"))

    def assert_pair(pair, profile, parent_blend=60):
        parent, child = [editor.exec_lua("return _snapshot(...)", win) for win in pair]
        assert parent["material"]["profile"] == child["material"]["profile"] == profile
        assert parent["normal"]["blend"] == parent["normalnc"]["blend"] == parent_blend, parent
        assert child["normal"]["blend"] == child["normalnc"]["blend"] == parent_blend, child
        assert parent["normal"]["bg"] == child["normal"]["bg"], "one shared material hue"
        assert parent["winblend"] == child["winblend"] == 0, "foreground must retain the existing background-only blend path"
        assert child["config"]["relative"] == "win" and child["config"]["win"] == pair[0]
        return parent, child

    def protocol_cells(points):
        """Read actual UI notifications, without the mutating inspect-cell API."""
        editor.command("redraw!")
        editor.eval("1")
        grids, attrs, cells = {}, {}, {}
        for message in editor._session._pending_messages:
            if message[0] != "notification" or message[1] != "redraw":
                continue
            for event in message[2]:
                if event[0] == "win_float_pos":
                    for item in event[1:]:
                        grids[int.from_bytes(item[1].data[1:], "big")] = item[0]
                elif event[0] == "hl_attr_define":
                    for item in event[1:]:
                        attrs[item[0]] = item[1]
                elif event[0] == "grid_clear":
                    for (grid,) in event[1:]:
                        cells = {key: value for key, value in cells.items() if key[0] != grid}
                elif event[0] == "grid_line":
                    for grid, row, column, entries, *_ in event[1:]:
                        highlight = 0
                        for entry in entries:
                            if len(entry) > 1:
                                highlight = entry[1]
                            for _ in range(entry[2] if len(entry) > 2 else 1):
                                cells[grid, row, column] = entry[0], highlight
                                column += 1
        result = {}
        for name, (win, row, column) in points.items():
            char, highlight = cells[grids[win], row, column]
            result[name] = char, attrs[highlight]
        return result

    pair = editor.exec_lua("return _show_noice()")
    assert_pair(pair, "noice_cmdline")
    # This view updates options/winhighlight on display and recreates both
    # windows on hide/show, so an initial namespace-only check is insufficient.
    editor.exec_lua("_view:display();vim.wait(100)")
    assert_pair(pair, "noice_cmdline")
    editor.exec_lua("_view:hide()")
    pair = editor.exec_lua("return _show_noice()")
    parent, child = assert_pair(pair, "noice_cmdline")
    draw = protocol_cells({"parent": (pair[0], 1, 20), "child": (pair[1], 0, 20),
                           "text": (pair[1], 0, 0), "selected": (pair[1], 0, 5)})
    assert draw["parent"][0] == draw["child"][0] == " "
    assert draw["parent"][1]["blend"] == 60 and draw["child"][1]["blend"] == 60, draw
    assert draw["text"][0] == "e" and draw["text"][1]["foreground"] == 0xffffff, draw
    assert draw["selected"][0] == "4" and draw["selected"][1]["background"] == 0x345678
    assert draw["selected"][1]["foreground"] == 0xffea00 and draw["selected"][1].get("blend", 0) == 0, draw
    assert editor.exec_lua("return vim.api.nvim_get_hl(0,{name='PopupLayerSelection'}).bg") == 0x345678
    editor.exec_lua("""
      vim.g.neovide_opacity=1;vim.g.neovide_normal_opacity=.85
      assert(vim.api.nvim_get_hl(0,{name='Normal'}).blend==nil,'Normal has no explicit blend')
      _profiles.config.noice_cmdline={mode='editor'}
      _transparency.apply()
    """)
    assert_pair(pair, "noice_cmdline", 15)
    editor_draw = protocol_cells({"padding": (pair[0], 1, 20), "border": (pair[0], 0, 0),
                                  "child": (pair[1], 0, 20)})
    assert editor_draw["padding"][0] == editor_draw["child"][0] == " "
    assert editor_draw["padding"][1]["blend"] == editor_draw["border"][1]["blend"] == 15, editor_draw
    assert editor_draw["child"][1]["blend"] == 15, editor_draw
    assert editor.exec_lua("return vim.api.nvim_get_hl(0,{name='Normal'}).blend==nil"), \
        "editor inheritance must not alter the main Normal highlight"
    editor.exec_lua("_view:hide()")

    # WhichKey suppresses WinNew/BufWinEnter/OptionSet while creating its
    # windows. Use its real setup, tree/state and view.show(), without the
    # public key-reading loop or a manual material application after display.
    editor.exec_lua("""
      _wk_show_hook=_wk_view.show
      package.loaded['config.appearance.popups']=nil
      local helper=require('config.appearance.popups');helper.apply()
      assert(_wk_view.show==_wk_show_hook,'module reload must not stack WhichKey show hooks')
      _material_show_calls=0
      local apply=helper.apply
      helper.apply=function(...)_material_show_calls=_material_show_calls+1;return apply(...)end
    """)
    whichkey = editor.exec_lua("return _show_whichkey()")
    calls = editor.exec_lua("return _last_material_show_calls")
    assert calls == 1, f"real show must apply material exactly once, observed {calls}"
    assert_pair(whichkey, "which_key")
    editor.exec_lua("vim.wait(50)")
    shadow_messages = [m[2][0] for m in editor._session._pending_messages
                       if m[0] == "notification" and m[1] == "neovide.window.shadow_exclusions"]
    assert shadow_messages and whichkey[1] in shadow_messages[-1] and whichkey[0] not in shadow_messages[-1], \
        "WhichKey footer must not cast a second shadow inside the composed popup"
    editor.exec_lua("_material_show_calls=0;_wk_view.show();_last_material_show_calls=_material_show_calls")
    calls = editor.exec_lua("return _last_material_show_calls")
    assert calls == 1, f"repeat show must retain a single hook, observed {calls}"
    assert_pair(whichkey, "which_key")
    editor.exec_lua("_wk_view.hide();_material_show_calls=0")
    whichkey = editor.exec_lua("return _show_whichkey()")
    calls = editor.exec_lua("return _last_material_show_calls")
    assert calls == 1, f"reopened windows need one synchronous material application, observed {calls}"
    assert_pair(whichkey, "which_key")
    unrelated = editor.exec_lua("""
      return _floating('WhichKeyNormal',{relative='win',win=...,row=1,col=1,width=30,height=1})
    """, whichkey[0])
    editor.exec_lua("_transparency.apply()")
    ordinary = editor.exec_lua("return _snapshot(...)", unrelated)
    assert ordinary["normal"]["blend"] == 60, "an unrelated relative=win popup must retain its own policy"
    # Each real window keeps its own profile, including nested children.
    editor.exec_lua("""
      local child=...
      _profiles.config.popup_layer_distinct={mode='custom',blend=25,bg='#456789'}
      vim.w[child].glow_popup_profile='popup_layer_distinct'
      _transparency.apply()
    """, whichkey[1])
    distinct = editor.exec_lua("return _snapshot(...)", whichkey[1])
    assert distinct["normal"]["blend"] == 25 and distinct["normal"]["bg"] == 0x456789, distinct
    assert editor.exec_lua("return _snapshot(...).normal.blend", whichkey[0]) == 60
    snacks = editor.exec_lua("""
      _wk_view.hide();require('which-key.state').state=nil
      vim.api.nvim_win_close(...,true)
      for _,name in ipairs({'snacks_picker','snacks_picker_box','snacks_picker_input',
        'snacks_picker_list','snacks_picker_preview'})do
        _profiles.config[name]={mode='custom',blend=60}
      end
      require('snacks').setup({picker={enabled=true,ui_select=false},notifier={enabled=false}})
      _picker=Snacks.picker({items={{text='alpha'},{text='beta'}},focus='list',
        format=function(item)return {{item.text,'Normal'}}end,
        preview=function(ctx)ctx.preview:set_lines({'fixed offline preview'})end,
        layout={preset='default'}})
      assert(vim.wait(1000,function()return _picker.layout and _picker.layout.box_wins
        and _picker.layout.wins and _picker.layout.wins.list:valid()end,10),'real Snacks default layout')
      vim.wait(100);_transparency.apply()
      local entries={}
      local function walk(node,parent)
        local holder=node.box and _picker.layout.box_wins[node.id] or _picker.layout.wins[node.win]
        local win=holder and holder.win
        if win and vim.api.nvim_win_is_valid(win)then
          entries[#entries+1]={win=win,parent=parent,kind=node.box and 'box' or node.win}
          parent=win
        end
        for _,child in ipairs(node)do walk(child,parent)end
      end
      walk(_picker.layout.opts.layout)
      return entries
    """, unrelated)
    assert len(snacks) >= 5, "default Snacks layout must contain root, nested box and all three leaves"
    root_window = snacks[0]["win"]
    root_material = editor.exec_lua("return _snapshot(...)", root_window)
    assert root_material["normal"]["blend"] == 60, "the outermost picker owns the material"
    nested = next(entry for entry in snacks if entry["kind"] == "box" and entry.get("parent"))
    leaves = {entry["kind"]: entry for entry in snacks if entry["kind"] != "box"}
    assert set(leaves) == {"input", "list", "preview"}
    for entry in snacks[1:]:
        layer = editor.exec_lua("return _snapshot(...)", entry["win"])
        owner = editor.exec_lua("return _snapshot(...)", entry["parent"])
        assert layer["normal"]["blend"] == 60, layer
    assert leaves["list"]["parent"] == leaves["input"]["parent"] == nested["win"]
    assert editor.exec_lua("return vim.api.nvim_win_get_config(...).win", leaves["list"]["win"]) == root_window, \
        "the regression must exercise a leaf anchored to root but semantically backed by its nested box"
    preview_win = leaves["preview"]["win"]
    editor.exec_lua("""
      _profiles.config.snacks_picker_preview={mode='custom',blend=25}
      _transparency.apply()
    """)
    preview = editor.exec_lua("return _snapshot(...)", preview_win)
    assert preview["normal"]["blend"] == 25 and not preview["material"].get("backing_window"), preview
    assert editor.exec_lua("return _snapshot(...).normal.blend", root_window) == 60
    assert editor.exec_lua("return _snapshot(...).normal.blend", leaves["list"]["win"]) == 60
    editor.exec_lua("_picker:close()")
    print(json.dumps({"noice_real_display_repeat_reopen": True,
                      "multigrid_background_blends": {"parent": draw["parent"][1]["blend"], "child": draw["child"][1]["blend"]},
                      "editor_mode_border_padding_blend": editor_draw["border"][1]["blend"],
                      "text_and_solid_selection_retained": True, "per_window_profiles_retained": True,
                      "whichkey_real_show_repeat_reopen_single_hook": True, "whichkey_single_outer_shadow": True, "unrelated_and_distinct_materials_preserved": True,
                      "snacks_real_default_nested_layout": True, "snacks_independent_preview_blend": 25}))
finally:
    try:
        editor.command("qa!")
    except (EOFError, OSError):
        pass
    editor.close()
