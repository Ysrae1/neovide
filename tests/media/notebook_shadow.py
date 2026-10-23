"""Isolated RPC/window regression for macOS Notebook shadow exclusions.

Run with the existing Notebook Python (pynvim required), no GUI or kernel:
  python tests/media/notebook_shadow.py --config ~/.config/nvim \
    --legacy-script target/glow-macos-notebook-shadow-20261023/installed-compatible-float-shadow.lua

The optional legacy script is a captured, unmodified installed-compatible Lua
payload. It is exercised before and after configuration, across a real UIEnter.
No running user editor, native binary, global RPC wrapper or user file changes.
"""
import argparse
import hashlib
import json
from pathlib import Path

import pynvim

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--config", type=Path, required=True)
parser.add_argument("--legacy-script", type=Path)
parser.add_argument("--receipt", type=Path)
args = parser.parse_args()
config = args.config.expanduser().resolve()
plugins = Path.home() / ".local/share/nvim/lazy"
native = ROOT / "lua/float_shadow.lua"

SETUP = r'''
local config, plugins, channel, platform, script, order = ...
local a = vim.api
vim.opt.rtp = {config, plugins .. '/snacks.nvim', vim.env.VIMRUNTIME}
vim.g.neovide = true; vim.g.neovide_channel_id = channel
vim.g.neovide_native_notebook = true; vim.g.neovide_native_notebook_footer = true
vim.g.neovide_normal_opacity = .85; vim.g.neovide_floating_shadow = true
vim.g.glow_ui_language = 'en'; vim.o.background = 'dark'
require('config.platform.locale').set_lang('en',{save=false,silent=true})
if order == 'script-first' then dofile(script) end
-- Execute the real platform entry point; only unrelated material/media setup
-- is stubbed. This verifies the Mac-only option at its production call site.
local dependencies = {'config.platform.windows_appearance','config.platform.glass',
  'config.appearance.transparency','config.appearance.render_roles','config.platform.neovide_zoom',
  'config.media.image','config.media.preview','config.media.notebook','config.media.notebook_edit',
  'config.media.book','config.media.open'}
local loaded, has = {}, vim.fn.has
for _,name in ipairs(dependencies) do
  loaded[name]=package.loaded[name]; package.loaded[name]={setup=function()end}
end
vim.fn.has = function(name)
  if name=='macunix' then return platform=='macos' and 1 or 0 end
  if name=='win32' then return platform=='windows' and 1 or 0 end
  return has(name)
end
require('config.platform.neovide')
vim.fn.has = has
for _,name in ipairs(dependencies) do package.loaded[name]=loaded[name] end
require('snacks').setup({picker={enabled=true}})
local palette = require('config.appearance.themes.ayu_dark_customed')
package.loaded.base46 = {get_theme_tb=function(kind) return palette[kind] or {} end}
a.nvim_set_hl(0,'Normal',{fg=palette.base_30.white,bg=palette.base_30.black})
a.nvim_set_hl(0,'NormalFloat',{link='Normal'})
local edit = require('config.media.notebook_edit')
edit.cell_labels = function(buf)
  local labels = {}
  for index,cell in ipairs(edit.cells(buf)) do
    labels[#labels+1] = {index=index,chunks=edit.label_chunks(cell.kind,'python',false)}
  end
  return labels
end
edit.refresh_title_colors(); require('config.media.notebook_highlights').setup()
_G.source, _G.source_buf = a.nvim_get_current_win(), a.nvim_get_current_buf()
_G.source_lines = {'# %%','print(42)'}
a.nvim_buf_set_lines(source_buf,0,-1,false,source_lines); vim.bo[source_buf].modified=false
_G.output_ns = a.nvim_create_namespace('molten-extmarks')
a.nvim_buf_set_extmark(source_buf,output_ns,1,0,{virt_lines={
  {{'Out[7]:','GlowNotebookOutputNumber'},{' ✓ Done','GlowNotebookOutputSuccess'}},
  {{'42','MoltenVirtualText'}}}})
_G.ui = require('config.media.notebook_ui'); assert(ui.attach(source_buf)); ui.refresh()
_G.source_marks = a.nvim_buf_get_extmarks(source_buf,output_ns,0,-1,{details=true})
function _G.open_output()
  _G.output_lines = {'Out[7]: ✓ Done 0.1s','42'}
  assert(require('config.media.notebook_output').enter(function()
    _G.output_buf = a.nvim_create_buf(false,true); vim.bo[output_buf].filetype='molten_output'
    a.nvim_buf_set_lines(output_buf,0,-1,false,output_lines)
    _G.output = a.nvim_open_win(output_buf,true,{relative='editor',row=1,col=1,width=32,height=6})
  end))
  require('config.appearance.popups').apply({output}); ui.refresh()
end
function _G.snapshot()
  local frame
  for _,value in ipairs(ui.refresh()) do
    if value.kind=='output' and value.overlay and value.anchor.window==output then frame=value end
  end
  assert(frame,'expanded Notebook output must retain its actual green frame')
  local cfg = a.nvim_win_get_config(output)
  local ns = a.nvim_get_hl_ns({winid=output})
  return {frame=frame,footer=cfg.footer,footer_pos=cfg.footer_pos,
    material=vim.w[output].glow_popup_material,
    highlights=a.nvim_get_hl(math.max(0,ns),{}), winhighlight=vim.wo[output].winhighlight,
    opacity=vim.g.neovide_normal_opacity,global_shadow=vim.g.neovide_floating_shadow}
end
function _G.retained()
  assert(vim.deep_equal(a.nvim_buf_get_lines(source_buf,0,-1,false),source_lines),'source text retained')
  assert(not vim.bo[source_buf].modified,'source unmodified')
  assert(vim.deep_equal(a.nvim_buf_get_extmarks(source_buf,output_ns,0,-1,{details=true}),source_marks),'inline output retained')
  local actual = a.nvim_buf_get_lines(output_buf,0,-1,false)
  assert(vim.deep_equal(actual,output_lines),'output text retained: '..vim.inspect({actual=actual,expected=output_lines}))
end
function _G.wait_shadow() vim.wait(40,function()return false end) end
if order == 'config-first' then
  -- An already-running server can have a visible output before this frontend
  -- injects its old complete-snapshot publisher and then attaches its UI.
  open_output(); wait_shadow(); dofile(script)
end
'''


def settle(editor):
    editor.exec_lua("wait_shadow()")
    editor.eval("1")
    packets = []
    pending = editor._session._pending_messages
    while pending:
        message = pending.popleft()
        if message[0] == "notification" and message[1] == "neovide.window.shadow_exclusions":
            packets.append(message[2][0])
    return packets


def run(platform, script, order):
    editor = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n"])
    try:
        editor.exec_lua(SETUP, str(config), str(plugins), editor.channel_id,
                        platform, str(script), order)
        # This real UI lifecycle boundary also covers config-first server attach.
        editor.ui_attach(120, 38, rgb=True, ext_multigrid=True, ext_hlstate=True)
        packets = settle(editor)
        assert editor.exec_lua("return #vim.api.nvim_get_autocmds({group='GlowFloatShadowOwner'})") == 0
        editor.exec_lua("""
          local owned=vim.api.nvim_get_autocmds({group='neovide_composed_float_shadow'})
          assert(#owned==9,'one complete controller owns the observation group')
          for _,event in ipairs(owned) do
            assert(debug.getinfo(event.callback,'S').source:find('/appearance/float_shadows.lua',1,true),
              'every active publisher callback must belong to the configured controller')
          end
        """)
        if order == "script-first":
            editor.exec_lua("open_output()")
            packets = settle(editor)
        output = editor.exec_lua("return output")
        if platform == "macos":
            assert packets and packets[-1] == [output], (platform, order, packets)
        else:
            assert not packets or packets[-1] == [], (platform, order, packets)
        before = editor.exec_lua("return snapshot()")
        assert before["footer_pos"] == "right"
        assert "q / Esc" in "".join(chunk[0] for chunk in before["footer"])
        assert before["opacity"] == .85 and before["global_shadow"] is True
        assert "SnacksPicker" not in before["winhighlight"]
        editor.exec_lua("require('config.appearance.float_shadows').setup(); retained()")
        assert settle(editor) == [([output] if platform == "macos" else [])], "a new ownership claim must republish the full current policy"
        assert editor.exec_lua("return snapshot()") == before, "shadow policy must not change frame/capsule/material"
        editor.exec_lua("vim.cmd('normal q'); retained()")
        packets = settle(editor)
        assert not packets or packets[-1] == [], "closing output must remove its window ID"
        editor.exec_lua("""
          _G.picker=Snacks.picker({items={{text='alpha'},{text='beta'}},layout={preset='default',preview=true}})
        """)
        packets = settle(editor)
        current = editor.exec_lua("return {input=picker.input.win.win,list=picker.list.win.win,preview=picker.preview.win.win,root=picker.layout.root.win}")
        excluded = set(packets[-1])
        children = {current["input"], current["list"], current["preview"]}
        assert children <= excluded and current["root"] not in excluded
        assert output not in excluded, "closed Notebook owner must not survive into another popup"
        assert len(excluded - children - {output}) == 1, "exactly one genuinely nested picker Box is excluded"
        ordinary = editor.exec_lua("local win=vim.api.nvim_open_win(vim.api.nvim_create_buf(false,true),false,{relative='editor',row=1,col=1,width=8,height=2,style='minimal'});vim.wo[win].winhighlight='';return win")
        packets = settle(editor)
        assert ordinary not in (packets[-1] if packets else excluded)
        editor.command("tabnew")
        packets = settle(editor)
        assert not packets or packets[-1] == [], "TabLeave must clear the old tab's owner snapshot"
        editor.exec_lua("picker:close()")
        settle(editor)
        editor.command("tabprevious")
        packets = settle(editor)
        assert not packets or packets[-1] == [], "returning must not revive closed popup IDs"
        editor.exec_lua("vim.api.nvim_set_current_win(source); open_output()")
        packets = settle(editor)
        output = editor.exec_lua("return output")
        assert not packets or packets[-1] == ([output] if platform == "macos" else [])
        editor.exec_lua("vim.cmd('normal q'); retained()")
        packets = settle(editor)
        assert not packets or packets[-1] == [], "closing output must remove its window ID"
        editor.exec_lua("""
          assert(not vim.api.nvim_win_is_valid(output)); assert(vim.g.neovide_floating_shadow)
          vim.api.nvim_win_close(...,true)
        """, ordinary)
        return {"platform_policy": platform, "script": script.name, "startup_order": order,
                "real_UIEnter": True, "notebook_only_macos": True, "picker_outer_ordinary_preserved": True,
                "frame_capsule_material_retained": True, "tab_close_cleared": True,
                "source_output_retained": True, "global_shadow": True}
    finally:
        try:
            editor.command("qa!")
        except (EOFError, OSError):
            pass


scripts = [native]
if args.legacy_script:
    scripts.append(args.legacy_script.expanduser().resolve())
result = {"config": str(config), "scope": "isolated RPC/UI protocol; no native GUI/GPU or kernel",
          "script_sha256": {str(script): hashlib.sha256(script.read_bytes()).hexdigest() for script in scripts},
          "checks": [run(platform, script, order) for script in scripts
                     for platform in ("macos", "windows", "linux")
                     for order in ("script-first", "config-first")]}
if args.receipt:
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(result, ensure_ascii=False))
