-- Headless material policy and hot-reload contract; no native GUI is opened.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local real_has = vim.fn.has
local platform = "windows"
vim.fn.has = function(feature)
  if feature == "win32" then return platform == "windows" and 1 or 0 end
  return real_has(feature)
end
vim.g.neovide, vim.g.neovide_liquid_glass = true, false
vim.o.background = "light"
vim.o.guifont = "FiraCode Nerd Font:h11"
local original_font = vim.o.guifont
local normal = { fg = 0x5c6166, bg = 0xfafafa }
vim.api.nvim_set_hl(0, "Normal", normal)
vim.api.nvim_set_hl(0, "NeoTreeNormal", { fg = 0x5c6166, bg = 0xf3f3f3 })
vim.api.nvim_set_hl(0, "NeoTreeNormalNC", { bg = 0xf3f3f3 })
vim.api.nvim_set_hl(0, "NeoTreeCursorLine", { bg = 0xe5e5e5 })
vim.api.nvim_set_hl(0, "CursorLine", { bg = 0xebebeb })
vim.api.nvim_set_hl(0, "St_EmptySpace", { bg = 0xfafafa })
package.loaded.base46 = { get_theme_tb = function(name)
  if name == "polish_hl" then return { ["neo-tree"] = { NeoTreeCursorLine = { blend = 7 } } } end
  return require("config.appearance.themes.ayu_" .. vim.o.background .. "_customed")[name] or {}
end }
local windows = require("config.platform.windows_appearance")
local helper = require("config.appearance.transparency")
assert(helper.config.material_blend == 80 and helper.config.windows.material_blend == 40)
windows.setup({ initialize = true })
for _, theme in ipairs({ "light", "dark", "light" }) do
  vim.o.background = theme
  local theme_normal = vim.api.nvim_get_hl(0, { name = "Normal" })
  helper.apply()
  assert(vim.api.nvim_get_hl(0, { name = "NeoTreeNormal" }).blend == 40, theme .. " panel")
  assert(vim.api.nvim_get_hl(0, { name = "St_EmptySpace" }).blend == 40, theme .. " footer")
  assert(vim.api.nvim_get_hl(0, { name = "NeoTreeCursorLine" }).blend == 7, "selection override")
  assert(vim.api.nvim_get_hl(0, { name = "CursorLine" }).blend == 20, "editor row override")
  assert(vim.g.neovide_bottom_margin_opacity == 0.6, "partial row")
  assert(vim.g.neovide_normal_opacity == (theme == "light" and 0.98 or 0.85))
  assert(windows.popup_blend(60) == (theme == "light" and 15 or 60))
  assert(vim.deep_equal(theme_normal, vim.api.nvim_get_hl(0, { name = "Normal" })), "Normal RGB")
end
helper.config.windows.material_blend = 53
helper.apply()
assert(vim.api.nvim_get_hl(0, { name = "NeoTreeNormal" }).blend == 53, "editable Windows value")
vim.api.nvim_exec_autocmds("ColorScheme", {})
assert(vim.wait(500, function()
  return vim.api.nvim_get_hl(0, { name = "St_EmptySpace" }).blend == 53
end, 10), "theme refresh keeps editable value")
package.loaded["config.appearance.transparency"] = nil
helper = require("config.appearance.transparency")
helper.setup()
assert(vim.wait(500, function()
  return vim.api.nvim_get_hl(0, { name = "NeoTreeNormal" }).blend == 40
end, 10), "documented hot reload consumes saved values")
for _, name in ipairs({ "macos", "linux" }) do
  platform = name
  helper.config.windows = nil -- Non-Windows must never read Windows settings.
  vim.g.neovide_liquid_glass = true
  vim.g.neovide_normal_opacity = 0.78
  assert(windows.setup() == false and windows.material_blend(80) == 80 and windows.popup_blend(60) == 60)
  helper.apply()
  assert(vim.api.nvim_get_hl(0, { name = "NeoTreeNormal" }).blend == 80, name .. " panel unchanged")
  assert(vim.g.neovide_normal_opacity == 0.78 and vim.g.neovide_bottom_margin_opacity == 0.2, name .. " opacity unchanged")
end
assert(vim.o.guifont == original_font, "font unchanged")
print("PASS: Windows material 40 in both themes, editable value/theme refresh/hot reload, independent selection, RGB/font and Mac/Linux policy preserved")
