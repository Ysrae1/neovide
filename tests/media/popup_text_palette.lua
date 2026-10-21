-- Isolated regression: one palette read per text batch, refreshed across themes;
-- preserve non-text styles, disabled accents and notification-only overrides.
local config = assert(vim.env.GLOW_TEST_CONFIG, 'GLOW_TEST_CONFIG required')
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local api = vim.api
local calls = { base_30 = 0, base_16 = 0 }
local palettes = {
  dark = { base_30 = { folder_bg = '#123456' }, base_16 = { base05 = '#ABCDEF' } },
  light = { base_30 = { folder_bg = '#654321' }, base_16 = { base05 = '#13579B' } },
}
package.loaded.base46 = { get_theme_tb = function(kind)
  assert(calls[kind] ~= nil, 'Unexpected theme table')
  calls[kind] = calls[kind] + 1
  return palettes[vim.o.background][kind]
end }
local text = require('config.appearance.popup_text')
text.overrides.SnacksPickerDir = 'folder_bg'
for _, name in ipairs({ 'TelescopePreviewNormal', 'SnacksPickerDir', 'LazyComment', 'SnacksPickerTotals', 'SnacksNotifierInfo', 'SnacksNotifierTitleInfo' }) do
  api.nvim_set_hl(0, name, { fg = 0x010203, bg = 0x08090a, bold = true, blend = 17 })
end
assert(vim.fn.hlexists('MasonMuted') == 0)
for _, mode in ipairs({ 'dark', 'light', 'dark' }) do
  vim.o.background = mode
  calls.base_30, calls.base_16 = 0, 0
  text.apply()
  assert(calls.base_30 == 1 and calls.base_16 == 1, 'A text batch repeated Base46 theme lookup')
  local expected = tonumber(palettes[mode].base_16.base05:sub(2), 16)
  for _, name in ipairs({ 'TelescopePreviewNormal', 'LazyComment', 'SnacksPickerTotals', 'SnacksNotifierInfo' }) do
    local attrs = api.nvim_get_hl(0, { name = name, link = false })
    assert(attrs.fg == expected and attrs.bg == 0x08090a and attrs.bold and attrs.blend == 17,
      'Text batch changed RGB/style semantics or retained an old theme: ' .. name)
  end
  local path = api.nvim_get_hl(0, { name = 'SnacksPickerDir', link = false })
  assert(path.fg == tonumber(palettes[mode].base_30.folder_bg:sub(2), 16), 'Named UI override lost precedence')
  assert(api.nvim_get_hl(0, { name = 'SnacksNotifierTitleInfo', link = false }).fg == 0x010203,
    'Disabled notification-title override changed its accent')
  assert(vim.fn.hlexists('MasonMuted') == 0, 'Batch created an unloaded plugin highlight')
  calls.base_30, calls.base_16 = 0, 0
  assert(next(text.window_overrides('lua', { Normal = 'TelescopePreviewNormal' })) == nil)
  assert(calls.base_30 == 0 and calls.base_16 == 0, 'Ordinary code preview fetched notification colors')
  local notification = text.window_overrides('noice', {})
  assert(notification.Comment.fg == expected and notification.NonText.fg == expected)
  assert(calls.base_30 == 1 and calls.base_16 == 1, 'Notification override batch repeated palette reads')
end
text.config.notification_detail = false
calls.base_30, calls.base_16 = 0, 0
assert(next(text.window_overrides('noice', {})) == nil)
assert(calls.base_30 == 0 and calls.base_16 == 0, 'Disabled detail color fetched a palette')
package.loaded.base46 = nil
text.apply()
assert(next(text.window_overrides('noice', {})) == nil)
print('PASS: one palette per batch, live theme RGB/style parity and notification isolation')
