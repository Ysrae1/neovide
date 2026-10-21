-- Actual buffers/windows/autocommands; serializer and native RPC are disabled.
-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE -n -l tests/notebook/winbar_lifecycle.lua
vim.opt.rtp = { assert(vim.env.GLOW_TEST_CONFIG), vim.env.VIMRUNTIME }
vim.o.hidden, vim.o.columns, vim.o.lines = true, 120, 45
local api = vim.api
package.preload["config.media.runtime"] = function()
  return { ensure_notebook_writer = function() end }
end
package.preload["config.media.notebook_ui"] = function()
  return { setup = function() end, refresh = function() end, attach = function() end }
end
local editor = require("config.media.notebook_edit")
editor.setup()
local bars = require("config.media.notebook_winbar")
local dirty = require("config.media.notebook_dirty")
local results = {}
local prefix = "%#GlowNotebookBar#"
local function is_notebook_bar(win)
  return vim.wo[win or 0].winbar:sub(1, #prefix) == prefix
end
local function flush()
  assert(vim.wait(1000, function() return not is_notebook_bar() end, 5), "stale Notebook winbar")
end
local function notebook(before)
  vim.cmd.tabnew()
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  vim.wo.winbar = before or ""
  api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".ipynb")
  api.nvim_buf_set_lines(buf, 0, -1, false, { "# %%", "print('kept')", "# %%", "value = 42" })
  vim.bo[buf].filetype = "python"
  api.nvim_exec_autocmds("BufWinEnter", { buffer = buf })
  assert(is_notebook_bar(), "Notebook title is missing")
  dirty.changed(buf)
  local ns = api.nvim_create_namespace("winbar-lifecycle-output")
  api.nvim_buf_set_extmark(buf, ns, 1, 0, { virt_lines = { { { "Out[1]: kept", "Normal" } } } })
  return { buf = buf, win = win, title = vim.wo.winbar, session = editor.status(buf),
    tick = api.nvim_buf_get_changedtick(buf), lines = api.nvim_buf_get_lines(buf, 0, -1, false),
    ns = ns, marks = api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) }
end
local function preserved(item)
  assert(vim.deep_equal(editor.status(item.buf), item.session), "Notebook session changed")
  assert(vim.bo[item.buf].modified and dirty.status(item.buf).dirty, "unsaved output protection lost")
  assert(api.nvim_buf_get_changedtick(item.buf) == item.tick, "source tick changed")
  assert(vim.deep_equal(api.nvim_buf_get_lines(item.buf, 0, -1, false), item.lines), "source changed")
  assert(vim.deep_equal(api.nvim_buf_get_extmarks(item.buf, item.ns, 0, -1, { details = true }), item.marks), "outputs changed")
end

-- New files and :enew may inherit the last window-local value.
for _, action in ipairs({ "edit_tex", "edit_py", "enew" }) do
  local item = notebook("prior-title")
  if action == "enew" then vim.cmd.enew()
  else vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. (action == "edit_tex" and ".tex" or ".py"))) end
  flush(); preserved(item)
  vim.cmd.buffer(item.buf)
  assert(is_notebook_bar(), "returning to Notebook must restore its title")
  preserved(item)
  results[#results + 1] = action .. "_and_return"
end

local item = notebook("before-split")
vim.cmd.vsplit(vim.fn.fnameescape(vim.fn.tempname() .. ".tex"))
flush(); preserved(item)
assert(is_notebook_bar(item.win), "other Notebook split lost its title")
local plain = api.nvim_get_current_buf()
api.nvim_set_current_win(item.win)
api.nvim_win_set_buf(item.win, plain)
flush(); preserved(item)
results[#results + 1] = "split_and_background_window_reuse"

-- A legacy literal or a delayed media-options restore must not resurrect it.
item = notebook("prior-title")
vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. ".tex"))
flush()
vim.wo.winbar = item.title
bars.refresh()
assert(vim.wo.winbar == "prior-title", "restore the prior local title")
local media_title = "%#GlowMediaInfo#PDF 1/4"
vim.wo.winbar = media_title
bars.refresh()
assert(vim.wo.winbar == media_title, "do not clear another component's title")
vim.wo.winbar = item.title
api.nvim_exec_autocmds("OptionSet", { pattern = "winbar" })
assert(vim.wo.winbar == "prior-title", "clean a delayed saved-options restore")
preserved(item)
results[#results + 1] = "prior_custom_title_and_delayed_media_restore"

-- Existing stale windows can be repaired without reloading Notebook sessions.
vim.cmd.tabnew()
api.nvim_buf_set_name(0, vim.fn.tempname() .. ".tex")
vim.wo.winbar = editor.render_title({}, 73)
bars.refresh()
assert(not is_notebook_bar(), "clean inherited/legacy Notebook title")
vim.wo.winbar = "another-owner"
bars.refresh()
assert(vim.wo.winbar == "another-owner")
results[#results + 1] = "legacy_cleanup_and_other_owner"

-- Close only after acknowledging this fixture's output state as saved.
item = notebook()
assert(dirty.saved(item.buf, dirty.token(item.buf)))
vim.cmd.bdelete(item.buf)
flush()
assert(editor.status(item.buf) == nil, "deleted Notebook descriptor must be released")
results[#results + 1] = "close_notebook"

-- Restoring an empty local option must preserve inheritance of the global bar.
vim.go.winbar = "global-title"
item = notebook("")
vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. ".tex"))
flush(); preserved(item)
assert(api.nvim_get_option_value("winbar", { win = 0, scope = "local" }) == "")
assert(vim.go.winbar == "global-title", "global title changed")
results[#results + 1] = "global_local_inheritance"
print(vim.json.encode({ passed = #results, cases = results, kernels_started = 0, source_and_outputs = "preserved" }))
