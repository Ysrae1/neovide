"""Isolated Notebook output-footer UI protocol regression.

Run with the existing Notebook Python (pynvim required), for example:
  ~/.local/share/nvim/glow-notebook-venv/bin/python tests/notebook/output_hint.py \
    --config ~/.config/nvim --receipt target/glow-notebook-output-hint-20261023/protocol-local.json

Uses real Neovim multigrid/linegrid output, the Notebook viewer/frame builder and
popup material adapter. The output provider only supplies fixture text: no GUI,
kernel, installed editor session, Windows command or plugin installation runs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tempfile
import traceback

import pynvim
import msgpack


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--config", type=Path, required=True)
parser.add_argument("--nvim", default="nvim")
parser.add_argument("--receipt", type=Path)
parser.add_argument("--icon-only", action="store_true", help="Check the collapse glyph and its existing capsule geometry in both themes only")
args = parser.parse_args()
config = args.config.expanduser().resolve()
receipt = {"config": str(config), "scope": "isolated Neovim UI protocol; no native GUI/GPU", "checks": []}


class Grids:
    def __init__(self):
        self.sizes, self.cells, self.attributes, self.windows = {}, {}, {}, {}

    def collect(self, editor):
        # The request is a barrier after all preceding redraw notifications.
        editor.eval("1")
        pending = editor._session._pending_messages
        while pending:
            message = pending.popleft()
            if message[0:2] != ("notification", "redraw") and list(message[0:2]) != ["notification", "redraw"]:
                continue
            for event in message[2]:
                name = event[0]
                for item in event[1:]:
                    if name == "hl_attr_define":
                        self.attributes[item[0]] = item[1]
                    elif name == "grid_resize":
                        self.sizes[item[0]] = (item[1], item[2])
                    elif name == "grid_clear":
                        self.cells[item[0]] = {}
                    elif name == "grid_destroy":
                        self.sizes.pop(item[0], None)
                        self.cells.pop(item[0], None)
                        self.windows.pop(item[0], None)
                    elif name in {"win_pos", "win_float_pos"}:
                        owner = item[1]
                        self.windows[item[0]] = int(msgpack.unpackb(owner.data) if isinstance(owner, msgpack.ExtType) else owner)
                    elif name == "grid_line":
                        grid, row, col, entries, *_ = item
                        cells, highlight = self.cells.setdefault(grid, {}), 0
                        for entry in entries:
                            if len(entry) > 1:
                                highlight = entry[1]
                            for _ in range(entry[2] if len(entry) > 2 else 1):
                                cells[row, col] = (entry[0], highlight)
                                col += 1
                    elif name == "grid_scroll":
                        grid, top, bottom, left, right, rows, cols = item
                        cells = self.cells.setdefault(grid, {})
                        old = dict(cells)
                        for row in range(top, bottom):
                            for col in range(left, right):
                                source = row + rows, col + cols
                                cells[row, col] = old.get(source, (" ", 0)) if (
                                    top <= source[0] < bottom and left <= source[1] < right
                                ) else (" ", 0)

    def footer(self, win):
        matches = []
        for grid, owner in self.windows.items():
            if owner != win or grid not in self.sizes:
                continue
            width, height = self.sizes[grid]
            cells = self.cells.get(grid, {})
            for row in range(height):
                text = "".join(cells.get((row, col), (" ", 0))[0] or " " for col in range(width))
                match = re.search(r"q\s*/\s*Esc", text)
                if match:
                    matches.append({"grid": grid, "row": row, "column": match.start(),
                                    "text": text, "grid_width": width, "grid_height": height})
        assert len(matches) == 1, f"one actual q / Esc footer must belong to output window {win}: {matches}"
        return matches[0]


SETUP = r'''
local config, theme = ...
local a = vim.api
vim.opt.rtp = {config, vim.env.VIMRUNTIME}
vim.o.termguicolors = true; vim.o.showmode = false; vim.o.cmdheight = 0
vim.o.laststatus = 0; vim.o.showtabline = 0; vim.o.background = theme
vim.g.neovide = true; vim.g.neovide_channel_id = 77
vim.g.neovide_native_notebook = true; vim.g.neovide_native_notebook_footer = true
vim.g.neovide_normal_opacity = .85; vim.g.glow_ui_language = 'en'; vim.g.mapleader = ' '
vim.rpcnotify = function() return true end
local palette = require('config.appearance.themes.ayu_' .. theme .. '_customed')
package.loaded.base46 = {get_theme_tb = function(kind) return palette[kind] or {} end}
a.nvim_set_hl(0, 'Normal', {fg=palette.base_30.white, bg=palette.base_30.black})
a.nvim_set_hl(0, 'NormalFloat', {bg=palette.base_30.darker_black})
local edit = require('config.media.notebook_edit')
edit.cell_labels = function(buf)
  local labels = {}
  for index, cell in ipairs(edit.cells(buf)) do
    labels[#labels+1] = {index=index, chunks=edit.label_chunks(cell.kind, 'python', false)}
  end
  return labels
end
edit.refresh_title_colors(); require('config.media.notebook_highlights').setup()
require('config.appearance.popup_materials').config.notebook_output = {mode='editor'}
_G.source, _G.source_buf = a.nvim_get_current_win(), a.nvim_get_current_buf()
_G.original_source = {'# %%', 'print(42)'}
a.nvim_buf_set_lines(source_buf, 0, -1, false, original_source)
vim.bo[source_buf].modified = false
_G.output_ns = a.nvim_create_namespace('molten-extmarks')
a.nvim_buf_set_extmark(source_buf, output_ns, 1, 0, {virt_lines={
  {{'Out[7]:', 'GlowNotebookOutputNumber'}, {' ✓ Done', 'GlowNotebookOutputSuccess'}},
  {{'42', 'MoltenVirtualText'}}, {{'󰁅 70 More lines ', 'MoltenVirtualText'}}}})
_G.original_marks = a.nvim_buf_get_extmarks(source_buf, output_ns, 0, -1, {details=true})
_G.ui = require('config.media.notebook_ui'); assert(ui.attach(source_buf)); ui.refresh()
_G.key_count = vim.on_key()
function _G.open_output(long)
  assert(a.nvim_get_current_win()==source)
  _G.expected_output = {'Out[7]: ✓ Done 0.1s', '42'}
  if long then
    expected_output = {}
    for row=1,80 do expected_output[row] = ('line %02d '):format(row) .. string.rep('abcdefghij', 40) end
    expected_output[1] = 'Out[7]: ✓ Done 0.1s'
  end
  assert(require('config.media.notebook_output').enter(function()
    _G.output_buf = a.nvim_create_buf(false, true)
    vim.bo[output_buf].filetype = 'molten_output'
    a.nvim_buf_set_lines(output_buf, 0, -1, false, expected_output)
    _G.output = a.nvim_open_win(output_buf, true, {relative='editor', row=1, col=1, width=32, height=6})
  end))
  require('config.appearance.popups').apply({output})
  ui.refresh(); vim.cmd.redraw()
end
function _G.snapshot()
  local frame
  for _, value in ipairs(ui.refresh()) do
    if value.kind=='output' and value.overlay and value.anchor.window==output then frame=value end
  end
  assert(frame, 'real Notebook renderer must emit the expanded output frame')
  local config = a.nvim_win_get_config(output)
  local ns = a.nvim_get_hl_ns({winid=output})
  local values = a.nvim_get_hl(math.max(ns,0), {})
  local groups = {}
  for _, chunk in ipairs(config.footer or {}) do
    local name = type(chunk[2])=='number' and a.nvim_get_hl_name_by_id(chunk[2]) or chunk[2]
    groups[#groups+1] = {text=chunk[1], name=name, attrs=values[name] or {}}
  end
  vim.cmd.redraw()
  return {win=output, config=config, frame=frame, footer=vim.w[output].glow_notebook_output_footer,
    origin=a.nvim_win_get_position(output), groups=groups, view=vim.fn.winsaveview(),
    material=vim.w[output].glow_popup_material, body_height=a.nvim_win_get_height(output),
    accent=a.nvim_get_hl(0,{name='GlowNotebookExpand',link=false}),
    value=a.nvim_get_hl(0,{name='GlowNotebookExpandValue',link=false}),
    caps={a.nvim_get_hl(0,{name='GlowNotebookExpandCap',link=false}),
      a.nvim_get_hl(0,{name='GlowNotebookExpandValueCap',link=false})}}
end
function _G.assert_retained()
  assert(vim.deep_equal(a.nvim_buf_get_lines(source_buf,0,-1,false),original_source))
  assert(not vim.bo[source_buf].modified)
  assert(vim.deep_equal(a.nvim_buf_get_extmarks(source_buf,output_ns,0,-1,{details=true}),original_marks))
  assert(vim.deep_equal(a.nvim_buf_get_lines(output_buf,0,-1,false),expected_output))
end
function _G.assert_closed()
  assert(not a.nvim_win_is_valid(output) and a.nvim_get_current_win()==source)
  assert(#a.nvim_list_wins()==1, 'closing must leave no floating output/footer window')
  assert(vim.on_key()==key_count, 'closing must remove its temporary key listener')
  assert_retained()
end
'''


def check_footer(editor, grids, label, native=True):
    snap = editor.exec_lua("return snapshot()")
    grids.collect(editor)
    visible = grids.footer(snap["win"])
    footer = snap["footer"]
    assert isinstance(footer, dict) and footer["width"] > 0, "footer geometry must be exported"
    assert visible["row"] == visible["grid_height"] - 1, "hint must occupy the fixed bottom border row"
    assert snap["config"]["footer_pos"] == "right"
    assert visible["column"] >= visible["grid_width"] / 2, "close keys must sit at the lower right"
    assert footer["col"] <= visible["column"] < footer["col"] + footer["width"]
    right = snap["frame"]["rect"]["col"] + snap["frame"]["rect"]["width"]
    assert .5 <= right - footer["col"] - footer["width"] <= 3, "capsule retains a visible inset from the right frame corner"
    bottom = snap["frame"]["rect"]["row"] + snap["frame"]["rect"]["height"]
    if native:
        assert abs(bottom - visible["row"] - .5) < .01, "native bottom line must pass through the footer row centre"
        gaps = snap["frame"].get("footer_gaps", [])
        assert len(gaps) == 1, "native footer cuts exactly one bottom-border gap"
        start = snap["frame"]["rect"]["col"] + gaps[0]["col"]
        assert abs(start - footer["col"]) <= .21
        assert footer["width"] <= gaps[0]["width"] <= footer["width"] + .41
    else:
        assert not snap["frame"].get("footer_gaps"), "old frontends receive no unsupported border gap"
        assert bottom > visible["row"] + .5, "old frontend keeps the capsule safely inside the output outline"
    assert snap["material"]["profile"] == "notebook_output"
    cells = grids.cells[visible["grid"]]
    icon_glyph, icon_highlight = cells[visible["row"], int(footer["col"]) + 1]
    assert icon_glyph == "󰕎", "collapse capsule must use mdi-unfold-less-horizontal, the inward counterpart of the expand glyph"
    icon_style = grids.attributes[icon_highlight]
    assert icon_style.get("background") == snap["accent"]["bg"] and icon_style.get("foreground") == snap["accent"]["fg"]
    assert editor.exec_lua("return vim.fn.strdisplaywidth('󰕎') == vim.fn.strdisplaywidth('󰕏')")
    q_style = grids.attributes[cells[visible["row"], visible["column"]][1]]
    assert q_style.get("foreground") == snap["value"]["fg"] and q_style.get("background") == snap["value"]["bg"], "actual q / Esc linegrid cells must retain their semantic capsule colors"
    assert q_style.get("blend", 0) == 0
    cap_styles = []
    for col, expected in ((footer["col"], snap["caps"][0]),
                          (footer["col"] + footer["width"] - 1, snap["caps"][1])):
        glyph, highlight = cells[visible["row"], int(col)]
        assert glyph in {"", ""}, "exported gap endpoints must coincide with the actual cap glyph columns"
        attrs = grids.attributes[highlight]
        assert attrs.get("foreground") == expected["fg"], "actual endcap ink keeps its theme color"
        cap_styles.append(attrs)
    actual = [group for group in snap["groups"] if group["text"].strip()]
    assert actual and any("q" in group["text"] and "Esc" in group["text"] for group in actual)
    for group in actual:
        attrs = group["attrs"]
        assert attrs.get("blend", 0) == 0, f"capsule must remain solid after popups.apply: {group}"
        if "" in group["text"] or "" in group["text"]:
            assert "bg" not in attrs, f"endcaps must retain transparent outer background: {group}"
        elif "q" in group["text"]:
            assert attrs.get("bg") == snap["value"]["bg"] and attrs.get("fg") == snap["value"]["fg"]
        else:
            assert attrs.get("bg") == snap["accent"]["bg"], f"icon segment must use the exact output-frame RGB: {group}"
    editor.exec_lua("assert_retained()")
    receipt["checks"].append({"case": label, "footer": visible, "frame": snap["frame"],
                              "capsule": footer, "groups": snap["groups"], "body_height": snap["body_height"],
                              "protocol_styles": {"keys": q_style, "caps": cap_styles, "icon": icon_style}})
    return snap, visible


try:
    receipt["sources"] = {
        str(path.relative_to(config)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [config / "lua/config/media/notebook_output.lua", config / "lua/config/media/notebook_ui.lua",
                     config / "lua/config/appearance/popups.lua"]
    }
    with tempfile.TemporaryDirectory(prefix="glow-output-hint-") as temporary:
        for theme in ("dark", "light"):
            child_env = ["XDG_" + name + "_HOME=" + str(Path(temporary) / theme / name.lower())
                         for name in ("CONFIG", "DATA", "STATE", "CACHE")]
            editor = pynvim.attach("child", argv=["/usr/bin/env", *child_env,
                "NVIM_APPNAME=glow-output-hint-test", args.nvim, "--embed", "--headless", "--noplugin",
                "-u", "NONE", "-i", "NONE", "-n"])
            grids = Grids()
            try:
                editor.ui_attach(96, 36, rgb=True, ext_multigrid=True, ext_linegrid=True, ext_hlstate=True)
                editor.exec_lua(SETUP, str(config), theme)
                editor.exec_lua("open_output(true)")
                initial, fixed = check_footer(editor, grids, theme + "/long")
                if args.icon_only:
                    editor.command("normal q")
                    editor.exec_lua("assert_closed()")
                    continue
                editor.command("normal 25l")
                editor.command("normal! 50j")
                scrolled, actual = check_footer(editor, grids, theme + "/scrolled")
                assert scrolled["view"]["leftcol"] > 0 and scrolled["view"]["topline"] > 1
                assert (actual["row"], actual["column"], actual["text"]) == (fixed["row"], fixed["column"], fixed["text"]), "horizontal and vertical scrolling must not move the hint"
                editor.ui_try_resize(64, 26)
                editor.exec_lua("vim.wait(30); require('config.appearance.popups').apply({output}); ui.refresh(); vim.cmd.redraw()")
                smaller, moved = check_footer(editor, grids, theme + "/resized")
                assert smaller["config"]["width"] < initial["config"]["width"] and moved["row"] < fixed["row"]
                assert smaller["view"]["topline"] == scrolled["view"]["topline"] and smaller["view"]["leftcol"] == scrolled["view"]["leftcol"]
                # Leave only two rows below the source seam: one padding row
                # and one genuine text row. Hiding the hint is allowed here.
                editor.exec_lua("_G.real_geometry=ui.output_frame_geometry; ui.output_frame_geometry=function(...) local g=real_geometry(...); g.clip.height=math.floor(g.rect.row)+2-g.clip.row; return g end; vim.api.nvim_exec_autocmds('VimResized',{}); vim.wait(30)")
                tiny = editor.exec_lua("return snapshot()")
                assert tiny["body_height"] >= 1, "tiny viewports retain a real scrollable output line"
                assert not tiny.get("footer") or not tiny["config"].get("footer"), "hint may be suppressed rather than consuming the final body line"
                editor.exec_lua("ui.output_frame_geometry=real_geometry")
                editor.command("normal q")
                editor.exec_lua("assert_closed()")
                receipt["checks"].append({"case": theme + "/tiny-and-q-close", "body_height": tiny["body_height"]})
                editor.ui_try_resize(96, 36)
                editor.exec_lua("vim.wait(30); ui.refresh(); open_output(false)")
                check_footer(editor, grids, theme + "/short")
                editor.input("\x1b")
                assert editor.exec_lua("return vim.wait(500,function() return not vim.api.nvim_win_is_valid(output) end,5)")
                editor.exec_lua("assert_closed()")
                receipt["checks"].append({"case": theme + "/esc-close", "remaining_windows": 1})
                editor.exec_lua("vim.g.neovide_native_notebook_footer=false; open_output(false)")
                check_footer(editor, grids, theme + "/old-host-fallback", native=False)
                editor.command("normal q")
                editor.exec_lua("assert_closed()")
            finally:
                try:
                    editor.command("qa!")
                except (EOFError, OSError):
                    pass
    receipt["status"] = "passed"
except Exception as error:
    receipt["status"] = "failed"
    receipt["error"] = str(error)
    receipt["traceback"] = traceback.format_exc()
    raise
finally:
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")

print(f"PASS Notebook output hint: {len(receipt['checks'])} protocol cases ({config})")
