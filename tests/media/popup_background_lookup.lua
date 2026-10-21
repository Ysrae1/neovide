-- Isolated regression: popup color lookup never copies all syntax highlights;
-- notifier batches retain RGB, and own OptionSet repairs cannot requeue a batch.
local config = assert(vim.env.GLOW_TEST_CONFIG, 'GLOW_TEST_CONFIG required')
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
vim.g.neovide = true
local api = vim.api
local palette = { darker_black = '#111111' }
package.loaded.base46 = { get_theme_tb = function() return palette end }
api.nvim_set_hl(0, 'Normal', { fg = 0xeeeeee, bg = 0x222222 })
api.nvim_set_hl(0, 'PopupLookupSource', { fg = 0xabcdef, bg = 0x333333 })
api.nvim_set_hl(0, 'NormalFloat', { link = 'PopupLookupSource' })
for index = 1, 1000 do api.nvim_set_hl(0, 'PopupLookupSyntax' .. index, { fg = index }) end
local original, full_reads = api.nvim_get_hl, 0
api.nvim_get_hl = function(namespace, opts)
  if namespace == 0 and not opts.name and not opts.id then full_reads = full_reads + 1 end
  return original(namespace, opts)
end
local popup = require('config.appearance.popups')
for _ = 1, 16 do assert(popup.background() == 0x111111) end
palette = { darker_black = '#222222', one_bg = '#444444' }
assert(popup.background() == 0x444444, 'Palette choice must still skip the editor RGB')
palette = {}
assert(popup.background() == 0x333333, 'Resolved linked NormalFloat fallback must remain unchanged')
api.nvim_set_hl(0, 'PopupLookupSource', { fg = 0xfedcba, bg = 0x555555 })
assert(popup.background() == 0x555555, 'Theme changes must not reuse stale color')
assert(full_reads == 0, 'Background lookup copied the complete syntax highlight table')
api.nvim_get_hl = original
local background, lookups = popup.background, 0
popup.background = function() lookups = lookups + 1; return background() end
for _, level in ipairs({ 'Trace', 'Debug', 'Info', 'Warn', 'Error' }) do
  api.nvim_set_hl(0, 'SnacksNotifier' .. level, { fg = 0x121212, bg = 0x121212 })
end
api.nvim_set_hl(0, 'SnacksNotifierMinimal', { link = 'NormalFloat' })
api.nvim_set_hl(0, 'SnacksNotifierHistory', { link = 'Normal' })
local transparency = require('config.appearance.transparency')
transparency.apply_notifier_material()
assert(lookups == 1, 'A notifier batch must resolve its background once')
for _, level in ipairs({ 'Trace', 'Debug', 'Info', 'Warn', 'Error' }) do
  local attrs = api.nvim_get_hl(0, { name = 'SnacksNotifier' .. level, link = false })
  assert(attrs.fg == 0xeeeeee and attrs.bg == 0x555555 and attrs.blend == 0, 'Notifier material RGB changed')
end
popup.background = background
local calls, window_calls = 0, 0
transparency.apply = function()
  calls = calls + 1
  api.nvim_exec_autocmds('OptionSet', { pattern = 'winhighlight' })
end
transparency.apply_windows = function()
  window_calls = window_calls + 1
  api.nvim_exec_autocmds('OptionSet', { pattern = 'winhighlight' })
end
transparency.setup()
vim.wait(100, function() return false end, 10)
assert(calls == 1 and window_calls == 0, 'The initial full refresh scheduled itself again')
api.nvim_exec_autocmds('WinNew', {})
api.nvim_exec_autocmds('BufWinEnter', {})
assert(vim.wait(100, function() return window_calls == 1 end, 10), 'Window events must refresh local material')
vim.wait(70, function() return false end, 10)
assert(calls == 1 and window_calls == 1, 'Opening windows rebuilt global highlights or retriggered itself')
api.nvim_exec_autocmds('OptionSet', { pattern = 'winhighlight' })
assert(vim.wait(100, function() return window_calls == 2 end, 10), 'A later real window change must still refresh')
api.nvim_exec_autocmds('ColorScheme', { pattern = 'PopupLookupTheme' })
assert(vim.wait(100, function() return calls == 2 end, 10), 'Theme changes must still refresh global material')
vim.wait(70, function() return false end, 10)
assert(calls == 2 and window_calls == 2, 'The later batch scheduled itself again')
print('PASS: bounded popup lookup, notifier RGB and global/window refresh lifecycle')
