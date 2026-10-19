-- nvim --headless --noplugin -u NONE -l tests/media/highlight_roles.lua
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
vim.g.neovide_reference_outline_supported = nil
local roles = require("config.appearance.render_roles")
assert(not roles.groups().LspReferenceText, "old GUI must not receive unknown roles")
local messages = {}
local notify = vim.rpcnotify
vim.rpcnotify = function(channel, method, packet)
  assert(method == "neovide.highlight_roles")
  messages[#messages + 1] = { channel = channel, packet = vim.deepcopy(packet) }
end
_G.neovide = {}
vim.g.neovide_channel_id = 41
vim.g.neovide_highlight_roles = nil
dofile("lua/highlight_roles.lua")
local expected = roles.groups()
assert(vim.deep_equal(messages[#messages].packet.groups, expected), "old config compatibility map")
assert(vim.g.neovide_highlight_roles_version == 1)
require("config.appearance.render_roles").setup()
assert(vim.deep_equal(messages[#messages].packet.groups, expected), "explicit config declaration")
local renamed = { MySyntax = { "enlarged_icon", "solid_title_cap" } }
_G.neovide.set_highlight_roles(renamed)
assert(vim.deep_equal(messages[#messages].packet.groups, renamed), "arbitrary group names")
vim.api.nvim_exec_autocmds("ColorScheme", {})
assert(vim.deep_equal(messages[#messages].packet.groups, renamed), "reload retains declaration")
vim.g.neovide_channel_id = 84
dofile("lua/highlight_roles.lua")
assert(messages[#messages].channel == 84, "new route uses its current channel")
assert(vim.deep_equal(messages[#messages].packet.groups, renamed))
_G.neovide.set_highlight_roles({})
assert(next(messages[#messages].packet.groups) == nil, "explicit empty map clears roles")
assert(vim.json.encode(messages[#messages].packet):find('"groups":{}', 1, true), "empty map wire format")
require("config.appearance.render_roles").setup()
assert(vim.deep_equal(messages[#messages].packet.groups, expected), "configuration reapply")
local references = require("config.appearance.editor_highlights").config.references
references.outline = false
roles.setup()
assert(not messages[#messages].packet.groups.LspReferenceText, "outline switch removes native role")
references.outline = true
vim.g.neovide_reference_outline_supported = nil
roles.setup()
assert(not messages[#messages].packet.groups.LspReferenceText, "early config waits for capability")
dofile("lua/highlight_roles.lua")
assert(vim.deep_equal(messages[#messages].packet.groups, expected), "native-ready event republishes early config")
vim.rpcnotify = notify
print("PASS: explicit rendering roles, legacy defaults, composition declarations, reload and route bootstrap")
