-- nvim --headless -u NONE -l tests/media/open_spec.lua
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or (vim.fn.getcwd() .. '/portable/payload/nvim'))
vim.g.neovide = true
vim.g.neovide_native_image = true
vim.g.neovide_native_preview = true
vim.g.neovide_channel_id = 77
local sent = {}
vim.rpcnotify = function(_, method, ...) sent[#sent + 1] = { method, ... }; return true end
local open = require('config.media.open')
open.setup()
local work = vim.fn.tempname()
vim.fn.mkdir(work, 'p')
local function file(name, content)
  local path = work .. '/' .. name
  vim.fn.writefile({ content or 'binary fixture' }, path)
  return path
end
local function settle() vim.wait(50) end
local function preview(kind)
  settle()
  local state = require('config.media.preview').status()
  assert(state and state.kind == kind, kind .. ' should open natively')
  assert(#vim.api.nvim_tabpage_list_wins(0) == 1, 'preserve chosen opening window')
end
local pdf = file("space '$ name.PdF", '%PDF-1.4 fixture')
vim.cmd({ cmd = 'edit', args = { pdf } })
preview('pdf')
local descriptor = vim.fn.bufnr(pdf)
assert(vim.bo[descriptor].buftype == 'nofile' and not vim.bo[descriptor].modifiable)
assert(vim.api.nvim_buf_get_lines(descriptor, 0, -1, false)[1] == '', 'binary never read as text')
local ok = pcall(vim.api.nvim_buf_call, descriptor, function() vim.cmd('write!') end)
assert(not ok, 'source descriptor cannot overwrite PDF')
require('config.media.preview').close()

-- Pickers also use bufadd + buffer, without going through :edit.
local video = file('clip.MOV')
local video_buf = vim.fn.bufadd(video)
vim.fn.bufload(video_buf)
vim.cmd({ cmd = 'buffer', args = { tostring(video_buf) } })
preview('video')
require('config.media.preview').close()

-- Existing descriptors can be revisited from Recent Files or a buffer picker.
vim.cmd({ cmd = 'buffer', args = { tostring(descriptor) } })
preview('pdf')
require('config.media.preview').close()

local image = file('plot.PNG')
vim.cmd({ cmd = 'tabedit', args = { image } })
settle()
assert(vim.bo.filetype == 'glow_image' and vim.uv.fs_realpath(vim.b.glow_image_path) == vim.uv.fs_realpath(image),
  vim.inspect({ filetype = vim.bo.filetype, image = vim.b.glow_image_path, name = vim.api.nvim_buf_get_name(0) }))
require('config.media.image').close()

-- A queued open must not steal the window after the user chooses another file.
local text = file('source.py', 'print(42)')
vim.cmd({ cmd = 'edit', args = { pdf } })
vim.cmd({ cmd = 'edit', args = { text } })
settle()
assert(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(text))
assert(vim.api.nvim_get_current_line() == 'print(42)')

-- Leave source readers and Jupytext's Notebook conversion in control.
for _, name in ipairs({ 'index.html', 'notebook.ipynb' }) do
  local path = file(name, 'source stays editable')
  vim.cmd({ cmd = 'edit', args = { path } })
  settle()
  assert(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(path)
    and vim.bo.buftype == '' and vim.bo.modifiable)
  assert(vim.api.nvim_get_current_line() == 'source stays editable')
end

local plugin = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(plugin, work .. '/plugin.pdf')
vim.api.nvim_set_current_buf(plugin)
settle()
assert(vim.api.nvim_get_current_buf() == plugin, 'plugin scratch windows are excluded')

-- A notification float does not make it legal to close the last ordinary window.
vim.cmd('tabonly!')
vim.cmd('only!')
local editor_win = vim.api.nvim_get_current_win()
local notification_buf = vim.api.nvim_create_buf(false, true)
vim.bo[notification_buf].filetype = 'noice'
vim.api.nvim_buf_set_lines(notification_buf, 0, -1, false, { 'Image decode failed' })
local notification_win = vim.api.nvim_open_win(notification_buf, false,
  { relative = 'editor', row = 1, col = 1, width = 24, height = 1, focusable = false })
local image_preview = require('config.media.image')
assert(image_preview.open(image))
local closed, close_error = pcall(image_preview.close)
assert(closed, 'Closing the last ordinary image window with a notification must succeed: ' .. tostring(close_error))
settle()
assert(vim.api.nvim_win_is_valid(editor_win) and vim.api.nvim_win_is_valid(notification_win),
  'Keep both the only editor window and the unrelated notification')
assert(vim.api.nvim_get_current_win() == editor_win and vim.bo.buftype == '' and vim.bo.modifiable,
  'Return the surviving editor window to an editable buffer')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'Editor remains usable after closing image' })
vim.bo.modified = false
local editor_buf = vim.api.nvim_get_current_buf()

-- A second ordinary split still permits closing only the preview window.
vim.cmd('vsplit')
local preview_win = vim.api.nvim_get_current_win()
assert(preview_win ~= editor_win and image_preview.open(image))
image_preview.close()
settle()
assert(not vim.api.nvim_win_is_valid(preview_win), 'Close the image split when another ordinary window exists')
assert(vim.api.nvim_win_is_valid(editor_win) and vim.api.nvim_win_is_valid(notification_win),
  'Closing the preview split preserves the editor and its notification')
assert(vim.api.nvim_win_get_buf(editor_win) == editor_buf
  and vim.api.nvim_buf_get_lines(editor_buf, 0, 1, false)[1] == 'Editor remains usable after closing image',
  'The other ordinary split keeps its usable buffer')
vim.api.nvim_win_close(notification_win, true)
vim.api.nvim_buf_delete(notification_buf, { force = true })
vim.fn.delete(work, 'rf')
print('Dashboard/picker binary routing, protected files, stale opens, source readers, image close with notification: PASS')
vim.cmd.qa()
