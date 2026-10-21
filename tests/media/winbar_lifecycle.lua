-- Real Neovim windows/buffers and production Lua; no native decoder or kernel.
-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE -n -l tests/media/winbar_lifecycle.lua
vim.opt.rtp = { assert(vim.env.GLOW_TEST_CONFIG), vim.env.VIMRUNTIME }
local api = vim.api
vim.o.hidden, vim.o.columns, vim.o.lines = true, 120, 45
vim.g.neovide, vim.g.neovide_native_preview, vim.g.neovide_native_image, vim.g.neovide_channel_id = true, true, true, 77
local sent, notifications = {}, 0
vim.rpcnotify = function(_, method, ...) sent[#sent + 1] = { method = method, args = { ... } }; return true end
vim.notify = function() notifications = notifications + 1 end
package.preload["config.media.runtime"] = function() return { ensure_notebook_writer = function() end } end
package.preload["config.media.notebook_ui"] = function() return { setup = function() end, attach = function() end, refresh = function() end } end
local notebook = require("config.media.notebook_edit")
notebook.setup()
local p, image, bars = require("config.media.preview"), require("config.media.image"), require("config.media.winbar")
local kinds = { "image", "pdf", "web", "audio", "video", "notebook" }
local passed = {}
local function flush() vim.wait(15) end
local function managed(value)
  return value:find("%%#GlowMediaBar#") ~= nil or value:find("%%#GlowNotebookBar#") ~= nil
end
local function fresh()
  vim.cmd.tabnew()
  vim.wo.winbar = ""
  return api.nvim_get_current_win()
end
local function last(method)
  for i = #sent, 1, -1 do if sent[i].method == method then return sent[i].args[1] end end
end
local function open(kind)
  if kind == "notebook" then
    vim.cmd.enew()
    local b = api.nvim_get_current_buf()
    api.nvim_buf_set_name(b, vim.fn.tempname() .. ".ipynb")
    api.nvim_buf_set_lines(b, 0, -1, false, { "# %%", "print('preserved')" })
    vim.bo[b].filetype = "python"
    api.nvim_exec_autocmds("BufWinEnter", { buffer = b })
    return { kind = kind, buf = b, tick = api.nvim_buf_get_changedtick(b), session = notebook.status(b) }
  end
  if kind == "image" then assert(image.open("/tmp/glow-winbar.png", { command = "" }))
  else assert(p.open("/tmp/glow-winbar." .. ({ pdf = "pdf", web = "html", audio = "wav", video = "mp4" })[kind], { kind = kind, command = "" })) end
  return { kind = kind, buf = api.nvim_get_current_buf(), id = kind == "image" and last("neovide.image.load") or p.status().id }
end
local function preserved(item)
  if item.kind == "notebook" then
    assert(notebook.status(item.buf) and vim.deep_equal(notebook.status(item.buf), item.session), "Notebook session changed")
    assert(api.nvim_buf_get_changedtick(item.buf) == item.tick and vim.bo[item.buf].modified, "Notebook source/modified changed")
  end
end
local function finish(label)
  passed[#passed + 1] = label
  vim.cmd("tabclose!")
  flush()
end

-- Entering a pre-created named Notebook resets the option before attachment.
fresh(); vim.wo.winbar = 'notebook-origin-title'
local direct = api.nvim_create_buf(true, false)
api.nvim_buf_set_name(direct, vim.fn.tempname() .. '.ipynb')
api.nvim_buf_set_lines(direct, 0, -1, false, {'# %%', 'value = 42'})
vim.bo[direct].filetype = 'python'
api.nvim_win_set_buf(0, direct)
api.nvim_exec_autocmds('BufWinEnter', {buffer=direct})
flush(); assert(managed(vim.wo.winbar), 'Notebook API entry missing title')
open('pdf'); flush()
vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. '.tex')); flush()
assert(vim.wo.winbar == 'notebook-origin-title', 'Notebook API entry lost original local title')
finish('named_notebook_entry_to_media_restores_prior_local')

-- Every directed pair, including Notebook, shares the same lifetime boundary.
for _, from in ipairs(kinds) do for _, to in ipairs(kinds) do if from ~= to then
  fresh(); vim.wo.winbar = 'original-local-title'
  local a = open(from); flush(); local b = open(to); flush()
  assert(managed(vim.wo.winbar), "active " .. to .. " lost its title")
  vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. ".tex")); flush()
  assert(not managed(vim.wo.winbar), from .. " -> " .. to .. " leaked into text")
  assert(vim.wo.winbar == 'original-local-title', from .. ' -> ' .. to .. ' lost original local title')
  preserved(a); preserved(b)
  finish(from .. "_to_" .. to .. "_to_text")
end end end

for _, kind in ipairs({ "image", "pdf", "web", "audio", "video" }) do
  fresh(); vim.go.winbar = 'global-title'; vim.wo.winbar = 'local-title'
  open(kind); flush()
  vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. '.tex')); flush()
  assert(api.nvim_get_option_value('winbar', {win=0,scope='local'}) == 'local-title', kind .. ' lost prior local title')
  vim.wo.winbar = ''
  flush()
  assert(api.nvim_get_option_value('winbar', {win=0,scope='local'}) == '', 'retired owner overwrote explicit global inheritance')
  assert(vim.go.winbar == 'global-title', 'modified global title')
  finish(kind .. '_prior_local_restore_and_retire')
  vim.go.winbar = ''

  local win = fresh(); local item = open(kind); flush()
  local ordinary = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(ordinary, vim.fn.tempname() .. ".tex")
  api.nvim_buf_set_lines(ordinary, 0, -1, false, { "ordinary file stays here" })
  local tick = api.nvim_buf_get_changedtick(ordinary)
  api.nvim_win_set_buf(win, ordinary)
  vim.wo.winbar = "ordinary-own-title"
  local before_notifications = notifications
  if kind == "image" then
    image.on_status(item.id, 640, 480, nil)
    image.on_status(item.id, 0, 0, "late-error")
    image.close()
  else
    p.on_status(item.id, vim.json.encode({ state = "ready", page = 1, pages = 2, zoom = 1 }))
    p.on_status(item.id, vim.json.encode({ state = "error", error = "late-error" }))
    p.on_status(item.id, vim.json.encode({ state = "ready", close_requested = true }))
    p.close(item.id)
  end
  api.nvim_exec_autocmds("ColorScheme", { pattern = "winbar-fixture" })
  assert(api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == ordinary, "late close touched text window")
  assert(vim.wo.winbar == "ordinary-own-title", "late callback/theme overwrote current owner")
  flush()
  assert(vim.wo.winbar == "ordinary-own-title", "cleanup overwrote current owner")
  assert(api.nvim_buf_get_changedtick(ordinary) == tick and notifications == before_notifications, "late callback mutated/notified")
  finish(kind .. "_late_ready_error_close_theme")

  fresh(); open(kind); flush()
  local source = api.nvim_get_current_win()
  vim.cmd.vsplit(vim.fn.fnameescape(vim.fn.tempname() .. ".py")); flush()
  assert(not managed(vim.wo.winbar) and managed(vim.wo[source].winbar), "split title ownership")
  finish(kind .. "_split")

  local owner_win = fresh()
  vim.go.winbar = "global-one"; vim.wo.winbar = ""
  local owned = open(kind); flush()
  vim.go.winbar = "global-two"
  -- Direct release verifies raw-local inheritance before the window is reused.
  if kind == "image" then image.close() else p.close() end
  assert(api.nvim_win_is_valid(owner_win), "last ordinary window should survive close")
  assert(api.nvim_get_option_value("winbar", { win = owner_win, scope = "local" }) == "", "lost global inheritance")
  assert(vim.go.winbar == "global-two", "changed global winbar")
  finish(kind .. "_global_local_restore")
  vim.go.winbar = ""
end

-- A disposed old owner cannot restore over the new owner's title.
fresh()
local first = open("image"); flush(); local second = open("pdf"); flush()
local title = vim.wo.winbar
image.refresh()
assert(vim.wo.winbar == title, "old image restore clobbered PDF")
p.on_status(second.id, vim.json.encode({ state = "ready", page = 2, pages = 3, zoom = 1 }))
assert(vim.wo.winbar:find("2/3", 1, true), "current PDF status did not update")
finish("owner_replacement_keeps_new_title")
print(vim.json.encode({ passed = #passed, cases = passed, kernels_started = 0, rpc = "mocked", actual_nvim_windows = true }))
