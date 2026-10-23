"""Isolated Matrix intro startup/window/RPC regression; no native GUI.

Run with an existing pynvim Python:
  python tests/navigation/matrix_shadow.py --config ~/.config/nvim \
    --legacy-script target/glow-macos-notebook-shadow-20261023/installed-compatible-float-shadow.lua

Starts only its own embedded Neovim and the existing two-second cmatrix intro.
No running user editor, theme values, native application or kernel is changed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

import pynvim
from msgpack import ExtType, unpackb

ROOT = Path(__file__).resolve().parents[2]
SETUP = r'''
local a = vim.api
local config, script = vim.env.GLOW_TEST_CONFIG, vim.env.GLOW_SHADOW_SCRIPT
local platform = vim.env.GLOW_SHADOW_PLATFORM
vim.opt.rtp = {config, vim.env.VIMRUNTIME}
vim.g.neovide = true; vim.g.neovide_channel_id = 1
vim.env.NVIM_SKIP_MATRIX_INTRO = nil
dofile(script)
-- Exercise the production platform policy while omitting unrelated providers.
local dependencies = {'config.platform.windows_appearance','config.platform.glass',
  'config.appearance.transparency','config.appearance.render_roles','config.platform.neovide_zoom',
  'config.media.image','config.media.preview','config.media.notebook','config.media.notebook_edit',
  'config.media.book','config.media.open','config.platform.macos_appearance'}
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
vim.g.neovide_floating_shadow = true
vim.g.neovide_normal_opacity = .85
_G.source = a.nvim_get_current_win()
_G.ordinary = a.nvim_open_win(a.nvim_create_buf(false,true),false,
  {relative='editor',row=2,col=2,width=10,height=3,style='minimal'})
require('config.appearance.intro')
for _,win in ipairs(a.nvim_list_wins()) do
  if vim.w[win].glow_popup_profile=='matrix_intro' then _G.cover=win end
end
assert(cover,'actual intro must open its cover during startup')
_G.cover_buf = a.nvim_win_get_buf(cover)
_G.cover_config = a.nvim_win_get_config(cover)
_G.cover_namespace = a.nvim_get_hl_ns({winid=cover})
_G.cover_material = a.nvim_get_hl(cover_namespace,{name='Normal',link=false})
assert(a.nvim_get_current_win()==source,'intro must not steal startup focus')
a.nvim_create_autocmd('VimEnter',{once=true,callback=function()
  assert(a.nvim_get_current_win()==source,'terminal must not steal startup focus')
  assert(vim.bo[cover_buf].buftype=='terminal','actual Matrix terminal must start')
  vim.g.glow_matrix_started = true
end})
'''


def drain(editor):
    editor.exec_lua("vim.wait(35,function()return false end)")
    editor.eval("1")
    messages = []
    pending = editor._session._pending_messages
    while pending:
        messages.append(pending.popleft())
    return messages


def snapshots(messages):
    return [m[2][0] for m in messages
            if m[0] == "notification" and m[1] == "neovide.window.shadow_exclusions"]


def window_id(value):
    return unpackb(value.data) if isinstance(value, ExtType) else getattr(value,"handle",value)


def run(config, script, platform):
    env = dict(os.environ, GLOW_TEST_CONFIG=str(config), GLOW_SHADOW_SCRIPT=str(script),
               GLOW_SHADOW_PLATFORM=platform)
    with tempfile.TemporaryDirectory(prefix="glow-matrix-shadow-") as work:
        startup = Path(work) / "init.lua"
        startup.write_text(SETUP)
        previous_env = {key: os.environ.get(key) for key in env if key.startswith("GLOW_")}
        os.environ.update({key:value for key,value in env.items() if key.startswith("GLOW_")})
        try:
            editor = pynvim.attach("child", argv=["nvim", "--embed", "--noplugin", "-u", str(startup), "-i", "NONE", "-n"])
        finally:
            for key,value in previous_env.items():
                if value is None:
                    os.environ.pop(key,None)
                else:
                    os.environ[key]=value
        try:
            assert editor.channel_id == 1
            editor.ui_attach(100, 32, rgb=True, ext_multigrid=True)
            state = editor.exec_lua("return {cover=cover,ordinary=ordinary,started=vim.g.glow_matrix_started,config=cover_config,material=cover_material}")
            assert state["started"], "real VimEnter must run the Matrix terminal"
            cover, ordinary = state["cover"], state["ordinary"]
            assert state["config"]["border"] == "none" and not state["config"]["focusable"]
            assert state["material"]["blend"] == 15, "intro material must remain editor alpha"
            messages = drain(editor)
            packets = snapshots(messages)
            expected = [cover] if platform == "macos" else []
            assert packets and packets[-1] == expected, (platform, packets)
            assert ordinary not in packets[-1], "ordinary floating window must keep its shadow"
            if platform == "macos":
                current = []
                first_cover_frame = False
                for kind,name,args in messages:
                    if kind != "notification":
                        continue
                    if name == "neovide.window.shadow_exclusions":
                        current = args[0]
                    if name == "redraw" and any(event[0] == "win_float_pos" and any(window_id(pos[1]) == cover for pos in event[1:]) for event in args):
                        assert cover in current, "intro ID must be excluded before its first UI frame"
                        first_cover_frame = True
                        break
                assert first_cover_frame, "must observe the actual first cover float frame"
            editor.exec_lua("require('config.appearance.float_shadows').setup()")
            assert snapshots(drain(editor)) == [expected], "frontend takeover must preserve full policy"
            editor.exec_lua("""
              assert(vim.deep_equal(vim.api.nvim_win_get_config(cover),cover_config))
              assert(vim.deep_equal(vim.api.nvim_get_hl(cover_namespace,{name='Normal',link=false}),cover_material))
              assert(vim.g.neovide_floating_shadow)
              assert(vim.wait(2600,function() return not vim.api.nvim_win_is_valid(cover) end,20), 'intro timeout')
              assert(not vim.api.nvim_buf_is_valid(cover_buf),'intro buffer must be deleted')
              assert(vim.api.nvim_win_is_valid(ordinary),'ordinary float must survive intro cleanup')
              assert(vim.api.nvim_get_current_win()==source,'intro cleanup must retain focus')
            """)
            packets = snapshots(drain(editor))
            assert not packets or packets[-1] == [], "closed cover ID must leave the snapshot"
            editor.exec_lua("require('config.appearance.float_shadows').setup()")
            assert snapshots(drain(editor)) == [[]], "no stale cover ID after controller reclaim"
            return {"platform_policy":platform,"frontend_script":script.name,"real_startup":True,
                    "first_frame_excluded":platform=="macos","ordinary_shadow_preserved":True,
                    "cover_job_buffer_cleaned":True,"takeover_retained":True,"global_shadow":True}
        finally:
            try:
                editor.command("qa!")
            except (EOFError,OSError):
                pass


parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--config",type=Path,required=True)
parser.add_argument("--legacy-script",type=Path)
parser.add_argument("--receipt",type=Path)
args=parser.parse_args()
config=args.config.expanduser().resolve()
scripts=[ROOT/"lua/float_shadow.lua"]
if args.legacy_script:
    scripts.append(args.legacy_script.expanduser().resolve())
result={"config":str(config),"scope":"real embedded Neovim startup/UI/RPC; no native GUI/GPU",
        "script_sha256":{str(s):hashlib.sha256(s.read_bytes()).hexdigest() for s in scripts},
        "checks":[run(config,s,p) for s in scripts for p in ("macos","windows","linux")]}
if args.receipt:
    args.receipt.parent.mkdir(parents=True,exist_ok=True)
    args.receipt.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
print(json.dumps(result,ensure_ascii=False))
