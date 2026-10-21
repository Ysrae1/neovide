"""Real pinned Snacks: material in every panel's first multigrid flush.

Isolated child only; no GUI, plugin installation or existing user editor.
Run with the Notebook venv Python; GLOW_TEST_CONFIG chooses local/portable.
"""
from pathlib import Path
from collections import Counter
import json
import os

import msgpack
import pynvim

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get("GLOW_TEST_CONFIG", ROOT / "portable/payload/nvim"))
PLUGINS = Path.home() / ".local/share/nvim/lazy"


def run(theme, kind):
    editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n"])
    try:
        editor.ui_attach(140, 45, rgb=True, ext_multigrid=True)
        editor.exec_lua("""
          local config,plugins,theme,shadow,channel=...
          vim.opt.rtp={config,plugins..'/snacks.nvim',vim.env.VIMRUNTIME}
          vim.g.neovide=true;vim.g.neovide_normal_opacity=.85
          vim.g.neovide_channel_id=channel
          local colors=require('config.appearance.themes.ayu_'..theme..'_customed')
          package.loaded.base46={get_theme_tb=function(kind)return colors[kind] or {} end}
          vim.o.background=theme
          vim.api.nvim_set_hl(0,'Normal',{fg=tonumber(colors.base_30.white:sub(2),16),bg=tonumber(colors.base_30.black:sub(2),16)})
          vim.api.nvim_set_hl(0,'NormalFloat',{link='Normal'})
          _material=require('config.appearance.popups')
          _transparency=require('config.appearance.transparency');_transparency.setup()
          dofile(shadow)
          vim.wait(80)
          _normal=vim.api.nvim_get_hl(0,{name='Normal',link=false})
        """, str(CONFIG), str(PLUGINS), theme, str(ROOT / "lua/float_shadow.lua"), editor.channel_id)

        attrs, grids, cells = {}, {}, {}

        def frames(check=False):
            while editor._session._pending_messages:
                message = editor._session._pending_messages.popleft()
                if message[0] != "notification" or message[1] != "redraw":
                    continue
                for event in message[2]:
                    for values in event[1:]:
                        name = event[0]
                        if name == "hl_attr_define":
                            attrs[values[0]] = values[1]
                        elif name == "win_float_pos":
                            grids[values[0]] = msgpack.unpackb(values[1].data)
                        elif name == "grid_clear":
                            cells[values[0]] = {}
                        elif name == "grid_line":
                            grid, row, column, entries, *_ = values
                            current = cells.setdefault(grid, {})
                            highlight = 0
                            for entry in entries:
                                if len(entry) > 1:
                                    highlight = entry[1]
                                for _ in range(entry[2] if len(entry) > 2 else 1):
                                    current[row, column] = entry[0], highlight
                                    column += 1
                        elif name == "win_hide" or name == "win_close":
                            grids.pop(values[0], None)
                    if event[0] == "flush" and check:
                        for grid, win in grids.items():
                            if win not in wanted or win in first:
                                continue
                            # Skip the active first list row's semantic CursorLine.
                            padding = Counter(hl for (row, _), (char, hl) in cells.get(grid, {}).items()
                                              if char == " " and (row > 0 or wanted[win] != 'snacks_picker_list'))
                            if not padding:
                                continue
                            actual = attrs.get(padding.most_common(1)[0][0], {})
                            first[win] = actual
                            assert actual.get("background") == normal["bg"] and actual.get("blend", 0) == 15, \
                                f"{theme}/{kind} {wanted[win]} first flush has transient material: {actual}"

        frames()
        normal = editor.exec_lua("return _normal")
        editor.exec_lua("""
          -- Cold provider: no 30ms wait between LazyLoad and the first show.
          require('snacks').setup({picker={enabled=true,ui_select=true}})
          local open_win,redraw=vim.api.nvim_open_win,vim.api.nvim__redraw
          local unhooked=require('snacks.win').show
          vim.api.nvim_exec_autocmds('User',{pattern='LazyLoad',data='snacks.nvim'})
          local show=require('snacks.win').show
          assert(show~=unhooked,'LazyLoad must install the first-show hook synchronously')
          package.loaded['config.appearance.popups']=nil
          require('config.appearance.popups').apply()
          assert(require('snacks.win').show==show,'reload must not stack provider hooks')
          assert(vim.api.nvim_open_win==open_win and vim.api.nvim__redraw==redraw,'no global API wrappers')
        """)
        if kind == "select":
            editor.exec_lua("_picker=vim.ui.select({'GitHub profile'}, {prompt='GitHub'}, function()end)")
        else:
            editor.exec_lua("_picker=Snacks.picker({items={{text='alpha'},{text='beta'}},layout={preset='default',preview=true}})")
        wanted = editor.exec_lua("""
          local ret={}
          for _,win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_config(win).relative~='' then
              local profile=require('config.appearance.popup_materials').classify(win,{Normal=vim.wo[win].winhighlight:match('Normal:([^,]+)')})
              if profile:match('^snacks_picker') then ret[tostring(win)]=profile end
            end
          end
          return ret
        """)
        wanted = {int(win): profile for win, profile in wanted.items()}
        assert len(wanted) >= 3, f"real composed picker required: {wanted}"
        first = {}
        editor.exec_lua("vim.wait(80)")
        frames(check=True)
        assert first.keys() == wanted.keys(), f"missing first panel flush: {wanted.keys() - first.keys()}"
        editor.exec_lua("""
          local callback=function()error('owned callback sentinel')end
          local win=Snacks.win({show=false,backdrop=false,on_win=callback,
            wo={winhighlight='Normal:SnacksPickerList'}})
          local ok,err=pcall(function()win:show()end)
          assert(not ok and err:find('owned callback sentinel',1,true),'provider error must propagate')
          assert(win.opts.on_win==callback,'failed show must restore the original callback')
          win:destroy()
        """)
        return {"theme": theme, "kind": kind, "first_flush_panels": len(first)}
    finally:
        try:
            editor.command("qa!")
        except (EOFError, OSError):
            pass


print(json.dumps([run(theme, kind) for theme in ("dark", "light") for kind in ("select", "preview")]))
