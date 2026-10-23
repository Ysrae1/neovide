-- Frozen Neo-tree rendering and independent Light/Dark colors, no GUI/user files.
-- GLOW_TEST_CONFIG=/path/to/config nvim --headless --noplugin -u NONE -i NONE -l tests/config/tree_message.lua
local config = assert(vim.env.GLOW_TEST_CONFIG)
local plugins = vim.env.GLOW_TEST_PLUGIN_ROOT or vim.fn.expand("~/.local/share/nvim/lazy")
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
for _, name in ipairs({ "neo-tree.nvim", "nui.nvim", "plenary.nvim" }) do vim.opt.rtp:append(plugins .. "/" .. name) end
local work = vim.fn.tempname()
local receipt = { config = config, cases = {} }
local ok, err = xpcall(function()
  vim.fn.mkdir(work, "p")
  vim.fn.writefile({ "hidden" }, work .. "/.hidden")
  vim.fn.writefile({ "visible" }, work .. "/visible")
  vim.o.columns, vim.o.lines = 100, 30
  vim.api.nvim_set_hl(0, "Normal", { fg = "#5c6166", bg = "#fafafa" })
  require("neo-tree").setup({
    enable_git_status = false, enable_diagnostics = false,
    filesystem = { async_directory_scan = "never", use_libuv_file_watcher = false },
    default_component_configs = { container = { enable_character_fade = false } },
  })
  require("neo-tree.command").execute({ source = "filesystem", action = "focus", dir = work })
  local state = require("neo-tree.sources.manager").get_state("filesystem")
  assert(vim.wait(1000, function() return state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) end))
  local ns = require("neo-tree.ui.highlights").ns_id
  local marked = false
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(state.bufnr, ns, 0, -1, { details = true })) do
    if mark[4].hl_group == "NeoTreeMessage" then
      local line = vim.api.nvim_buf_get_lines(state.bufnr, mark[2], mark[2] + 1, false)[1]
      marked = line:find("hidden", 1, true) ~= nil
      if marked then break end
    end
  end
  assert(marked, "actual hidden-item notice does not use NeoTreeMessage")
  receipt.cases[#receipt.cases + 1] = "actual hidden-item notice renders with NeoTreeMessage"

  local function attrs() return vim.api.nvim_get_hl(0, { id = vim.fn.hlID("NeoTreeMessage"), link = false }) end
  local settings = require("config.appearance.tree_message")
  local inherited = attrs()
  assert(inherited.italic and inherited.fg, "frozen plugin default unavailable")
  settings.apply()
  assert(vim.deep_equal(inherited, attrs()), "default changed original colors/styles")
  local themes = {}
  for _, mode in ipairs({ "light", "dark" }) do themes[mode] = require("config.appearance.themes.ayu_" .. mode .. "_customed") end
  package.loaded.base46 = { get_theme_tb = function(kind) return themes[vim.o.background][kind] end }
  settings.config.light, settings.config.dark = "#123456", "base05"
  for _, mode in ipairs({ "light", "dark", "light" }) do
    vim.o.background = mode
    local untouched = vim.api.nvim_get_hl(0, { name = "NeoTreeDirectoryName", link = false })
    -- A fresh incoming theme group includes material and styles to preserve.
    local original = { fg = 0x556677, bg = 0x223344, italic = true, blend = 27 }
    vim.api.nvim_set_hl(0, "NeoTreeMessage", original)
    original = attrs()
    settings.apply()
    local expected = mode == "light" and 0x123456 or tonumber(themes.dark.base_16.base05:sub(2), 16)
    local styled = attrs()
    assert(styled.fg == expected and styled.bg == original.bg and styled.italic and styled.blend == 27, mode .. " color or preserved style")
    settings.apply()
    assert(vim.deep_equal(styled, attrs()), mode .. " repeated application changed color/styles")
    local custom = settings.config[mode]
    settings.config[mode] = false
    settings.apply()
    assert(vim.deep_equal(original, attrs()), mode .. " false did not restore inherited attributes: " .. vim.inspect(attrs()))
    settings.config[mode] = custom
    assert(vim.deep_equal(untouched, vim.api.nvim_get_hl(0, { name = "NeoTreeDirectoryName", link = false })), mode .. " unrelated tree color changed")
    receipt.cases[#receipt.cases + 1] = mode .. ": configured fg, repeated apply, background/italic/blend preserved, false restores"
  end
  vim.api.nvim_set_hl(0, "TreeMessageTestLinked", { fg = 0x778899, italic = true })
  vim.api.nvim_set_hl(0, "NeoTreeMessage", { link = "TreeMessageTestLinked" })
  settings.apply()
  settings.reload()
  assert(vim.api.nvim_get_hl(0, { id = vim.fn.hlID("NeoTreeMessage"), link = true }).link == "TreeMessageTestLinked", "reload did not restore original link")
  assert(require("config.appearance.tree_message").config.light == false, "reload did not reread saved default")
  receipt.cases[#receipt.cases + 1] = "reload rereads saved settings and restores original link; unrelated tree groups unchanged"
  receipt.state = "passed"
end, debug.traceback)
require("neo-tree.command").execute({ action = "close" })
vim.fn.delete(work, "rf")
if not ok then receipt.state, receipt.error = "failed", err end
if vim.env.GLOW_TEST_RECEIPT then vim.fn.writefile({ vim.json.encode(receipt) }, vim.env.GLOW_TEST_RECEIPT) end
assert(ok, err)
print("PASS Neo-tree hidden-message color: real notice group, inherited defaults, independent Light/Dark hex/slot, style preservation, false/reset and reload")
