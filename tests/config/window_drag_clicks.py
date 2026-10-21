"""Real Neovim tabline click routing; this does not perform an OS window drag.

Run with the existing Notebook venv Python (pynvim). GLOW_TEST_CONFIG selects
local/portable. Uses one isolated child, no plugins, existing editor or GUI.
"""
import os
from pathlib import Path

import pynvim


ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get("GLOW_TEST_CONFIG", ROOT / "portable/payload/nvim"))
editor = pynvim.attach("child", argv=[
    "nvim", "--embed", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n",
])
try:
    editor.ui_attach(80, 24, rgb=True, ext_linegrid=True)
    editor.exec_lua("""
        vim.opt.rtp:prepend(...)
        vim.g.neovide_window_drag_supported=true
        vim.g.neovide_channel_id=84
        vim.g.neovide=true
        _G.calls={}
        vim.rpcnotify=function(channel,method,packet)
            table.insert(_G.calls,{method=method,packet=packet})
        end
        _G.GlowWindowDrag=require('config.appearance.window_drag').click
        _G.BufferCb=function() table.insert(_G.calls,{method='buffer'}) end
        _G.GitHubCb=function() table.insert(_G.calls,{method='github'}) end
        _G.CloseCb=function() table.insert(_G.calls,{method='close'}) end
        vim.o.showtabline=2; vim.o.mouse='a'
        vim.o.tabline=require('config.appearance.window_drag').wrap(
            '%@v:lua.BufferCb@ Buffer %X%#TbFill#%=%@v:lua.GitHubCb@ GitHub %X%@v:lua.CloseCb@ X %X')
        vim.cmd('redraw!')
    """, str(CONFIG))
    for column in [30, 2, 72, 78]:
        editor.api.input_mouse("left", "press", "", 0, 0, column)
        editor.api.input_mouse("left", "release", "", 0, 0, column)
        editor.command("sleep 20m")
    assert editor.exec_lua("return _G.calls") == [
        {"method": "neovide.window.start_drag", "packet": {"version": 1, "row": 0, "column": 30}},
        {"method": "buffer"}, {"method": "github"}, {"method": "close"},
    ], "alignment fill and each original button must keep separate click definitions"
    print("PASS: real Neovim UI mouse routing preserves buffer, GitHub and close buttons")
finally:
    try:
        editor.command("qa!")
    except Exception:
        pass
    editor.close()
