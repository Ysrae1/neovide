"""Real Neovim UI routing with installed NvChad and Snacks, without a GUI.

Run with a Python that has pynvim. GLOW_TEST_CONFIG selects local/portable;
GLOW_TEST_PLUGIN_ROOT selects the installed lazy plugin directory. No plugin
installation, user buffer access, shell or OS input is performed.
"""
import json
import os
from pathlib import Path
import tempfile

import pynvim

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get("GLOW_TEST_CONFIG", ROOT / "portable/payload/nvim"))
PLUGINS = Path(os.environ.get("GLOW_TEST_PLUGIN_ROOT", Path.home() / ".local/share/nvim/lazy"))
CASES = [
    {"name": "dashboard_startup", "columns": 80, "buffers": 0, "dashboard": True},
    {"name": "dashboard_top_content", "columns": 80, "buffers": 0, "dashboard": True, "top_content": True},
    {"name": "dashboard_custom_mouse", "columns": 80, "buffers": 0, "dashboard": True, "custom_mouse": True},
    {"name": "empty_tabline", "columns": 80, "buffers": 0},
    {"name": "buffer_labels", "columns": 120, "buffers": 2},
    {"name": "overflow_and_wide_buttons", "columns": 80, "buffers": 8, "wide": True},
]
checks = []
for case in CASES:
    with tempfile.TemporaryDirectory(prefix="glow-window-drag-") as temp:
        before = {}
        for kind in ("CONFIG", "DATA", "STATE", "CACHE"):
            key = f"XDG_{kind}_HOME"
            before[key] = os.environ.get(key)
            directory = Path(temp) / kind.lower()
            directory.mkdir()
            os.environ[key] = str(directory)
        editor = pynvim.attach("child", argv=[
            os.environ.get("GLOW_TEST_NVIM", "nvim"), "--embed", "--headless",
            "--noplugin", "-u", "NONE", "-i", "NONE", "-n",
        ])
        try:
            editor.ui_attach(case["columns"], 24, rgb=True, ext_linegrid=True)
            editor.exec_lua(r"""
local config,plugins,case=...
vim.opt.rtp:prepend(config)
vim.opt.rtp:prepend(plugins..'/ui')
vim.opt.rtp:prepend(plugins..'/snacks.nvim')
vim.g.neovide=true
vim.g.neovide_window_drag_supported=true
vim.g.neovide_channel_id=84
vim.o.showtabline=2;vim.o.mouse='a';vim.o.mousetime=0
local opts={bufwidth=21,order={'buffers','tabs','githubprofile','btns'},modules={}}
package.loaded.nvconfig={ui={tabufline=opts}}
package.loaded['nvim-web-devicons']={get_icon=function() return nil end}
local utils=require('nvchad.tabufline.utils')
opts.modules.githubprofile=function()
  return utils.btn(case.wide and ' GitHub profile ' or ' GitHub ','TabCloseBtn','OpenGitHubProfile')
end
opts.modules.btns=function()
  return utils.btn(' T ','ThemeToggleBtn','Toggle_theme')..utils.btn(' X ','CloseAllBufsBtn','SaveAndQuit')
end
vim.t.bufs={}
local drag=require('config.appearance.window_drag')
vim.o.tabline="%!v:lua.require('nvchad.tabufline.modules')()"
drag.setup()
if case.dashboard then
  if case.custom_mouse then vim.keymap.set('n','<LeftMouse>',function() _G.route='custom_mouse' end,{buffer=0,desc='Existing dashboard mouse owner'}) end
  require('snacks').setup({dashboard={enabled=true,row=case.top_content and 0 or nil,sections={{text='Dashboard body'}}}})
else
  local buffers={}
  for i=1,case.buffers do
    local b=vim.api.nvim_create_buf(true,false)
    vim.api.nvim_buf_set_name(b,'GlowGap-'..i..'.lua')
    table.insert(buffers,b)
  end
  vim.t.bufs=buffers
  if #buffers>0 then vim.api.nvim_set_current_buf(buffers[#buffers]) end
end
""", str(CONFIG), str(PLUGINS), case)
            editor.command("sleep 20m")
            result = editor.exec_lua(r"""
local case=...
local raw=require('nvchad.tabufline.modules')()
local start,finish=assert(raw:find('%%#TbFill#%%='))
local left=vim.api.nvim_eval_statusline(raw:sub(1,start-1),{use_tabline=true,maxwidth=case.columns}).width
local right=vim.api.nvim_eval_statusline(raw:sub(finish+1),{use_tabline=true,maxwidth=case.columns}).width
local drag=require('config.appearance.window_drag')
_G.GlowWindowDrag=function(...) _G.route='drag';return drag.click(...) end
vim.rpcnotify=function(_,method,packet) _G.last_packet=packet;_G.last_method=method end
for _,name in ipairs({'GoToBuf','KillBuf','GotoTab','NewTab','ToggleTabs','OpenGitHubProfile','Toggle_theme','SaveAndQuit'}) do
  vim.cmd('function! Tb'..name..'(a,b,c,d)\n lua _G.route="'..name..'"\n endfunction')
end
vim.cmd('redraw!')
return {showtabline=vim.o.showtabline,filetype=vim.bo.filetype,gap_start=left,gap_end=case.columns-right}
""", case)
            assert result["showtabline"] == (0 if case.get("dashboard") else 2), (case, result, "dashboard must keep its tabline hidden")
            if case.get("dashboard"):
                assert result["filetype"] == "snacks_dashboard", result
                assert result["gap_start"] == 0, result
            controls = set()
            for column in range(case["columns"]):
                editor.exec_lua("_G.route='';_G.last_packet=nil;_G.last_method=nil")
                editor.api.input_mouse("left", "press", "", 0, 0, column)
                editor.api.input_mouse("left", "release", "", 0, 0, column)
                editor.command("sleep 1m")
                route = editor.exec_lua("return {route=_G.route,packet=_G.last_packet,method=_G.last_method}")
                expected = (not case.get("custom_mouse")) if case.get("dashboard") else result["gap_start"] <= column < result["gap_end"]
                if case.get("top_content") and (10 <= column < 19 or 20 <= column < 24):
                    expected = False
                assert (route["route"] == "drag") == expected, (case, result, column, route)
                if expected:
                    assert route["packet"] == {"version": 1, "row": 0, "column": column}, route
                    assert route["method"] == "neovide.window.start_drag", route
                elif route["route"]:
                    controls.add(route["route"])
            if not case.get("dashboard"):
                assert {"OpenGitHubProfile", "Toggle_theme", "SaveAndQuit"} <= controls, (case, controls)
            if case.get("custom_mouse"):
                assert controls == {"custom_mouse"}, controls
            if case["buffers"]:
                assert {"GoToBuf", "KillBuf"} <= controls, (case, controls)
            if case.get("dashboard") and not case.get("custom_mouse"):
                for modifiers in ["S", "C", "A"]:
                    editor.exec_lua("_G.route=''")
                    editor.api.input_mouse("left", "press", modifiers, 0, 0, 1)
                    editor.api.input_mouse("left", "release", modifiers, 0, 0, 1)
                    editor.command("sleep 1m")
                    assert editor.exec_lua("return _G.route") != "drag", "modified click must keep its normal action"
            editor.exec_lua("_G.route=''")
            editor.api.input_mouse("left", "press", "", 0, 1, 1)
            editor.api.input_mouse("left", "release", "", 0, 1, 1)
            editor.command("sleep 1m")
            assert editor.exec_lua("return _G.route") != "drag", "dashboard/editor body must not request native move"
            checks.append({"case": case["name"], "columns_checked": case["columns"], **result, "controls": sorted(controls)})
        finally:
            try:
                editor.command("qa!")
            except Exception:
                pass
            editor.close()
            for key, value in before.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
receipt = {"state": "passed", "config": str(CONFIG), "scope": "Neovim UI routing; no OS window drag", "checks": checks}
if os.environ.get("GLOW_TEST_RECEIPT"):
    Path(os.environ["GLOW_TEST_RECEIPT"]).write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
print(json.dumps(receipt))
