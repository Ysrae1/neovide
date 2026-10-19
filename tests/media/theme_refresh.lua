-- Real, already-installed Base46/FFF/Noice sources; no installation or user session.
-- GLOW_TEST_CONFIG=/path/to/nvim GLOW_TEST_PLUGIN_ROOT=/path/to/lazy
-- GLOW_TEST_NEOVIDE=1 nvim --headless --noplugin -u NONE -i NONE -l tests/media/theme_refresh.lua
local config = assert(vim.env.GLOW_TEST_CONFIG)
local plugins = assert(vim.env.GLOW_TEST_PLUGIN_ROOT)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
for _, name in ipairs({ "base46", "plenary.nvim", "ui", "fff", "noice.nvim" }) do
  assert(vim.fn.isdirectory(plugins .. "/" .. name) == 1, "missing existing test dependency: " .. name)
  vim.opt.rtp:append(plugins .. "/" .. name)
end
vim.g.neovide = vim.env.GLOW_TEST_NEOVIDE == "1" and true or nil
local cache = vim.fn.tempname() .. "/"
vim.fn.mkdir(cache, "p")
vim.g.base46_cache = cache
local options = require("nvconfig")
options.ui.cmp.style = "atom" -- Covers the completion integration's background branch.
local compat = require("config.appearance.base46")
compat.setup()
local function rgb(value) return tonumber(value:gsub("^#", ""), 16) end
local function hl(name, namespace)
  local values = vim.api.nvim_get_hl(namespace or 0, {})
  local attrs = values[name]
  if not attrs or next(attrs) == nil then attrs = vim.api.nvim_get_hl(0, { name = name, link = false }) end
  return attrs
end
local function settle()
  vim.wait(80, function() return false end, 10)
end
local function check_sources()
  local b = require("base46")
  local syntax, colors = b.get_theme_tb("base_16"), b.get_theme_tb("base_30")
  local mode = b.get_theme_tb("type")
  local change = require("base46.colors").change_hex_lightness
  assert(vim.o.background == mode, "target mode not applied")
  assert(hl("LazyButton").fg == rgb(syntax.base05), "Lazy button retained old foreground")
  assert(hl("LazyButton").bg == rgb(colors.one_bg), "Lazy button lost its theme background")
  local inlay = rgb(change(colors.black2, mode == "dark" and 0 or 3))
  local kind = rgb(change(colors.black2, mode == "dark" and 6 or -6))
  assert(hl("LspInlayHint").bg == inlay, "LSP integration used the previous background mode")
  assert(hl("CmpItemKindText").bg == kind, "completion integration used the previous background mode")
  for _, item in ipairs({ { "lsp", "LspInlayHint", inlay }, { "cmp", "CmpItemKindText", kind } }) do
    vim.api.nvim_set_hl(0, item[2], { bg = 0x123456 })
    dofile(cache .. item[1])
    assert(hl(item[2]).bg == item[3], item[1] .. " cache retained old mode")
  end
  vim.api.nvim_set_hl(0, "LazyButton", { fg = 0x123456 })
  dofile(cache .. "defaults")
  assert(hl("LazyButton").fg == rgb(syntax.base05) and vim.o.background == mode,
    "defaults cache retained old foreground or lost its background prefix")
  compat.apply() -- Final material follows the repaired cache, including namespaced floats.
end
local popup
local function check_copies()
  local value, score, match = hl("FFFFileInfoValue"), hl("FFFFileInfoTotalScore"), hl("FFFFileInfoMatchType")
  assert(value.fg == hl("Normal").fg and not value.bg, "FFF value text is stale or imports a background")
  assert(score.fg == hl("Number").fg and score.bold, "FFF score text is stale")
  assert(match.fg == hl("Special").fg and match.bold, "FFF match type text is stale")
  assert(hl("NoiceFormatProgressDone").fg == hl("Search").fg
    and hl("NoiceFormatProgressDone").bg == hl("Search").bg, "Noice copied Search color is stale")
  local ns = math.max(vim.api.nvim_get_hl_ns({ winid = popup }), 0)
  assert(hl("LazyButton", ns).fg == hl("LazyButton").fg, "popup namespace retained old button text")
  if vim.g.neovide then
    assert(hl("Normal", ns).bg == require("config.appearance.popups").background()
      and hl("Normal", ns).blend == 0 and vim.wo[popup].winblend == 0, "popup opacity was not restored")
  else
    assert(vim.wo[popup].winblend == 35, "terminal popup policy changed")
  end
end
for index, mode in ipairs({ "light", "dark", "light" }) do
  options.base46.theme = "ayu_" .. mode
  vim.o.background = mode == "light" and "dark" or "light"
  require("base46").load_all_highlights()
  settle()
  check_sources()
  if index == 1 then
    -- Lazy-loaded providers must also refresh after their first setup.
    require("fff.highlights").setup()
    require("noice.config.highlights").setup()
    local buffer = vim.api.nvim_create_buf(false, true)
    popup = vim.api.nvim_open_win(buffer, false, {
      relative = "editor", row = 1, col = 1, width = 32, height = 2, style = "minimal",
    })
    vim.wo[popup].winhighlight, vim.wo[popup].winblend = "Normal:NormalFloat", 35
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", modeline = false })
    settle()
  end
  check_copies()
  package.loaded["config.appearance.base46"], package.loaded["config.appearance.fff"] = nil, nil
  compat = require("config.appearance.base46")
  compat.setup()
  -- A compatibility-module reload may start with old live groups/cache without
  -- NvThemeReload. Its public apply/ColorScheme/LazyLoad path repairs that too.
  vim.api.nvim_set_hl(0, "LazyButton", { fg = 0x123456 })
  require("base46").str_to_cache("defaults", "vim.api.nvim_set_hl(0,'LazyButton',{fg=0x123456})")
  compat.apply()
  check_sources()
  check_copies()
end
vim.api.nvim_win_close(popup, true)
vim.fn.delete(cache, "rf")
print("PASS: real Light/Dark/Light theme branches, repaired caches, lazy providers, Noice/FFF copies and popup reload/material isolation")
