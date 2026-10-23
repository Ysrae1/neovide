-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE -l tests/navigation/native_preview_capabilities.lua
vim.opt.rtp = { assert(vim.env.GLOW_TEST_CONFIG), vim.env.VIMRUNTIME }
vim.g.neovide = true
vim.g.neovide_channel_id = 1
vim.g.neovide_native_preview = true
local preview = require('config.media.preview')
local open = require('config.media.open')
assert(preview.available('web') and open.kind('test.mp3') == 'audio', 'legacy Mac capability lost')
vim.g.neovide_native_preview_kinds = { 'pdf' }
assert(preview.available('pdf') and not preview.available('web'))
assert(open.kind('test.pdf') == 'pdf' and not open.kind('test.mp3'), 'unsupported kind intercepted')
local calls = 0
package.loaded['neo-tree.utils'] = { get_appropriate_window = function() calls = calls + 1; return 0, false end }
local old_open = preview.open
local event = { path = 'test.pdf', state = {}, open_cmd = 'edit' }
preview.open = function() return false end
assert(preview.from_tree(event) == nil, 'failed opener was swallowed')
preview.open = function() return true end
assert(preview.from_tree(event).handled == true)
preview.open = function() error('test failure') end
local notify = vim.notify; vim.notify = function() end
assert(preview.from_tree(event) == nil, 'exception was swallowed')
vim.notify = notify
preview.open = old_open
local before = calls
assert(preview.from_tree({path='test.mp3'}) == nil and calls == before)
vim.g.neovide_native_preview = false
assert(not preview.available('pdf'))
local synctex = require('config.media.synctex')
vim.g.neovide_native_preview = true
assert(synctex.native_enabled() == (vim.fn.has('win32') ~= 1), 'old Windows frontend must not imply coordinate support')
vim.g.neovide_native_pdf_synctex = true
assert(synctex.native_enabled())
vim.g.glow_tex_viewer = 'sumatra'
assert(not synctex.native_enabled(), 'explicit external viewer must override native coordinates')
vim.g.glow_tex_viewer = nil
vim.g.neovide_native_pdf_synctex = false
assert(not synctex.native_enabled(), 'unsupported coordinate SyncTeX advertised')
print('PASS native preview kind capability and failed tree opening fallback')
