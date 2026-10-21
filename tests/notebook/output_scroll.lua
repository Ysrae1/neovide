-- Real isolated output windows, no plugin runtime, Python host or kernel.
-- GLOW_TEST_CONFIG=~/.config/nvim nvim --headless -u NONE -i NONE -l tests/notebook/output_scroll.lua
vim.opt.rtp = { assert(vim.env.GLOW_TEST_CONFIG), vim.env.VIMRUNTIME }
require("config.platform.locale").set_lang("zh", { save = false, silent = true })
local api = vim.api
local source, source_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
local source_lines = { "# %%", "print('saved output')" }
api.nvim_buf_set_lines(source_buf, 0, -1, false, source_lines)
vim.bo[source_buf].modified = false
vim.wo[source].wrap = true
local namespace = api.nvim_create_namespace("output-scroll-source")
api.nvim_buf_set_extmark(source_buf, namespace, 1, 0, {
  virt_lines = { { { "Out[7]:", "GlowNotebookOutputNumber" }, { " ", "MoltenVirtualText" },
    { "✓ Done", "GlowNotebookOutputSuccess" }, { " 0.1s", "MoltenVirtualText" } },
    { { "retained inline output", "MoltenVirtualText" } } },
})
local marks = api.nvim_buf_get_extmarks(source_buf, namespace, 0, -1, { details = true })
local output_lines = {}
for row = 1, 80 do output_lines[row] = ("line %02d "):format(row) .. string.rep("abcdefghij", 40) end
output_lines[1] = "Out[7]: ✓ Done 0.1s"
local geometry = { rect = { row = 3.5, col = 2.2, width = 45.56, height = 4 },
  clip = { row = 0, col = 0, width = 80, height = 22 } }
package.loaded["config.media.notebook_ui"] = {
  output_frame_geometry = function(win, buf, cell)
    assert(win == source and buf == source_buf and cell == 1, "geometry must belong to the selected source cell")
    return geometry
  end,
  refresh = function() end,
}
local function floating()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "molten_output"
  api.nvim_buf_set_lines(buf, 0, -1, false, output_lines)
  local win = api.nvim_open_win(buf, false, { relative = "editor", row = 1, col = 1, width = 32, height = 6 })
  vim.wo[win].wrap = true
  return win, buf
end
local helper = require("config.media.notebook_output")
local key_listeners = vim.on_key()
local global_mappings = api.nvim_get_keymap("n")
local calls, output, output_buf = 0
assert(helper.enter(function()
  calls = calls + 1
  if not output then output, output_buf = floating()
  else api.nvim_set_current_win(output) end
end), "live output must open and focus on one user action")
assert(calls == 2 and api.nvim_get_current_win() == output and not vim.wo[output].wrap,
  "open_then_enter must become a focused nowrap view")
assert(vim.on_key() == key_listeners + 1, "only this output view's passive wheel listener may be installed")
local origin = api.nvim_win_get_position(output)
local outline = vim.w[output].glow_notebook_output_frame
assert(math.abs(origin[2] + outline.col - geometry.rect.col) < 0.001
  and math.abs(outline.width - geometry.rect.width) < 0.001,
  "popup's green left/right outlines must match the original fractional edges")
assert(origin[1] + outline.row == geometry.rect.row
  and api.nvim_win_get_height(output) == 18, "popup must stay at output seam and expand down into remaining space")
assert(not vim.bo[output_buf].modifiable and vim.bo[output_buf].readonly, "output viewer must reject edits")
local styles = api.nvim_buf_get_extmarks(output_buf, api.nvim_get_namespaces()["glow.notebook.output-view"], 0, -1, { details = true })
assert(styles[1][4].hl_group == "GlowNotebookOutputNumber" and styles[3][4].hl_group == "GlowNotebookOutputSuccess",
  "popup header must retain inline execution-number and status colors")
vim.cmd("normal! Vjy")
assert(vim.fn.getreg('"') == output_lines[1] .. "\n" .. output_lines[2] .. "\n", "ordinary visual yank must copy original text")
vim.cmd("normal 25l")
assert(vim.fn.winsaveview().leftcol > 0, "l must reveal the right side of a long output line")
local leftcol = vim.fn.winsaveview().leftcol
vim.cmd("normal 10h")
assert(vim.fn.winsaveview().leftcol < leftcol, "h must scroll back toward the left")
vim.cmd("normal! 50j")
assert(vim.fn.winsaveview().topline > 1, "long output must scroll vertically")
local before_resize = vim.fn.winsaveview()
geometry.rect.width, geometry.clip.height = 35.56, 20
api.nvim_exec_autocmds("VimResized", {})
vim.wait(20)
outline = vim.w[output].glow_notebook_output_frame
assert(outline.width == geometry.rect.width and api.nvim_win_get_width(output) == 35
  and api.nvim_win_get_height(output) == 16, "resizing must keep the output aligned with the new source width and available height")
local after_resize = vim.fn.winsaveview()
assert(after_resize.topline == before_resize.topline and after_resize.leftcol == before_resize.leftcol,
  "refitting the expanded window must retain its horizontal and vertical scroll position")
geometry.clip.height = 5
api.nvim_exec_autocmds("VimResized", {})
vim.wait(20)
assert(api.nvim_win_get_height(output) == 1, "two remaining rows must retain one real scrollable text row")
geometry.clip.height = 20
api.nvim_exec_autocmds("VimResized", {})
vim.wait(20)
assert(vim.deep_equal(api.nvim_buf_get_lines(output_buf, 0, -1, false), output_lines), "scrolling must retain original output text")
assert(vim.fn.maparg("<ScrollWheelLeft>", "n") == "3zh"
  and vim.fn.maparg("<ScrollWheelRight>", "n") == "3zl", "horizontal wheel must scroll the focused output")
vim.cmd("normal q")
assert(api.nvim_get_current_win() == source and not api.nvim_win_is_valid(output), "q must close and return to the original editor")
assert(vim.on_key() == key_listeners, "q must remove the temporary wheel listener")
assert(vim.bo[output_buf].modifiable and not vim.bo[output_buf].readonly, "closing must restore provider's buffer write access")

-- Use the actual saved-output entry path. Its RPC is a fake existing renderer,
-- but changing focus is real: nvim_buf_call would incorrectly restore source.
package.loaded["config.media.runtime"] = { read_notebook = function()
  return { cells = { { cell_type = "code", source = "print('saved output')", execution_count = 7,
    outputs = { { output_type = "stream", text = "retained inline output" } } } } }
end }
_G.output_scroll_rpc = function(args)
  if args[1] == "enter" then
    output, output_buf = floating()
    api.nvim_set_current_win(output)
    return true
  end
  return 1
end
vim.cmd([[
function! GlowNotebookSavedOutputs(...) abort
  return luaeval('_G.output_scroll_rpc(_A)', a:000)
endfunction
]])
local saved = require("config.media.notebook_saved")
saved.attach(source_buf, "isolated.ipynb")
api.nvim_win_set_cursor(source, { 2, 0 })
assert(helper.enter(function() return saved.enter(source_buf) end), "saved output must focus without starting a kernel")
assert(vim.on_key() == key_listeners + 1, "reopening must install one wheel listener without accumulating earlier views")
assert(api.nvim_get_current_win() == output and not vim.wo[output].wrap, "saved output must use the same scroll behavior")
api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "xt", false)
assert(api.nvim_get_current_win() == source and not api.nvim_win_is_valid(output), "Esc must close and return to source")
assert(vim.on_key() == key_listeners, "Esc must remove the temporary wheel listener")
assert(helper.enter(function() output, output_buf = floating(); api.nvim_set_current_win(output) end))
local target_buf = api.nvim_create_buf(false, true)
local target = api.nvim_open_win(target_buf, false, { relative = "editor", row = 1, col = 55, width = 12, height = 3 })
api.nvim_set_current_win(target)
vim.wait(20)
assert(api.nvim_get_current_win() == target and not api.nvim_win_is_valid(output),
  "leaving output must close it without stealing a click/window switch's target focus")
assert(vim.on_key() == key_listeners, "click/window-switch dismissal must remove the wheel listener")
api.nvim_win_close(target, true)
api.nvim_set_current_win(source)
assert(vim.wo[source].wrap and vim.deep_equal(api.nvim_buf_get_lines(source_buf, 0, -1, false), source_lines)
  and not vim.bo[source_buf].modified, "output viewing must preserve source contents, options and saved state")
assert(vim.deep_equal(api.nvim_buf_get_extmarks(source_buf, namespace, 0, -1, { details = true }), marks),
  "output viewing must not rewrite or clear original inline output marks")
calls = 0
assert(not helper.enter(function() calls = calls + 1; return false end) and calls == 1
  and api.nvim_get_current_win() == source, "missing output must not steal focus or retry")
assert(helper.enter(function()
  output, output_buf = floating()
  api.nvim_buf_set_lines(output_buf, 0, -1, false, { "Out[8]: ✗ Failed 0.4s", "Traceback:", "ValueError: original error" })
  api.nvim_set_current_win(output)
end))
styles = api.nvim_buf_get_extmarks(output_buf, api.nvim_get_namespaces()["glow.notebook.output-view"], 0, -1, { details = true })
local semantic = {}
for _, mark in ipairs(styles) do semantic[mark[4].hl_group] = true end
assert(semantic.GlowNotebookOutputNumber and semantic.GlowNotebookOutputFailure and semantic.GlowNotebookOutputError,
  "full error output and execution header must use the same semantic groups as the inline error")
vim.cmd("normal q")
geometry.clip.height = 4
local fits, error_message = helper.enter(function() output, output_buf = floating(); api.nvim_set_current_win(output) end)
assert(not fits and error_message:find("空间不足", 1, true) and api.nvim_get_current_win() == source
  and not api.nvim_win_is_valid(output), "no usable space below the original seam must fail gracefully without moving the viewer elsewhere")
assert(vim.on_key() == key_listeners and vim.deep_equal(api.nvim_get_keymap("n"), global_mappings),
  "finished output views must retain no wheel listener or modified global mouse mappings")
print("Notebook output scrolling: live/saved focus, horizontal/vertical scroll, q/Esc and source/inline preservation passed")
