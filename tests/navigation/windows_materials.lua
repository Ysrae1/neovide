-- Real Ayu tables, terminal buffer and floating namespaces; platform modeled.
-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE
--   -l tests/navigation/windows_materials.lua
local config = assert(vim.env.GLOW_TEST_CONFIG, "GLOW_TEST_CONFIG is required")
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local original_has, windows = vim.fn.has, true
vim.fn.has = function(name)
  if name == "win32" then return windows and 1 or 0 end
  return original_has(name)
end
vim.g.neovide = true
local appearance = require("config.platform.windows_appearance")
local transparency = require("config.appearance.transparency")
local profiles = require("config.appearance.popup_materials")
local buf = vim.api.nvim_create_buf(false, true)
local channel = vim.api.nvim_open_term(buf, {})
vim.api.nvim_chan_send(channel, "Yazi-style terminal text\r\n")
local win = vim.api.nvim_open_win(buf, false, {
  relative = "editor", row = 1, col = 2, width = 28, height = 3, border = "rounded", style = "minimal",
})
local function rgb(value) return tonumber(value:sub(2), 16) end
local function window_material()
  local namespace = vim.api.nvim_get_hl_ns({ winid = win })
  return vim.api.nvim_get_hl(namespace, {}).Normal
end
local function theme(mode)
  local data = require("config.appearance.themes.ayu_" .. mode .. "_customed")
  vim.o.background = mode
  package.loaded.base46 = { get_theme_tb = function(kind)
    return kind == "base_30" and data.base_30 or kind == "base_16" and data.base_16 or {}
  end }
  vim.api.nvim_set_hl(0, "Normal", { fg = rgb(data.base_30.white), bg = rgb(data.base_30.black) })
  vim.api.nvim_set_hl(0, "NormalFloat", { link = "Normal" })
  vim.api.nvim_set_hl(0, "FloatBorder", { link = "Normal" })
  vim.api.nvim_set_hl(0, "Pmenu", { link = "Normal" })
  vim.api.nvim_set_hl(0, "SnacksNormal", { link = "Normal" })
  vim.api.nvim_set_hl(0, "SnacksDashboardTerminal", { link = "Normal" })
  vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "GlowMaterialTest", modeline = false })
  return data
end
appearance.setup()
transparency.setup()
for _, mode in ipairs({ "light", "dark", "light" }) do
  local data = theme(mode)
  assert(vim.wait(150, function()
    return vim.w[win].glow_popup_material ~= nil
      and window_material().blend == (mode == "light" and 2 or 15)
  end, 5), "theme event did not refresh open terminal")
  assert(vim.w[win].glow_popup_material.profile == "terminal", "Yazi must use the actual terminal path")
  local material = window_material()
  assert(material.bg == rgb(data.base_30.black) and material.fg == rgb(data.base_30.white), "Ayu RGB changed")
  assert(vim.g.neovide_normal_opacity == (mode == "light" and 0.98 or 0.85))
  local highlights = vim.api.nvim_get_hl(0, {})
  assert(highlights.SnacksNormal.blend == (mode == "light" and 15 or 80), "panel retained the wrong material")
  assert(highlights.Pmenu.blend == (mode == "light" and 2 or 15), "completion differs from terminal policy")
  assert(highlights.SnacksDashboardTerminal.blend == (mode == "light" and 2 or 15), "Matrix differs from editor material")
end
-- Override one platform policy for every editor-mode popup, while preserving
-- explicit custom per-class material settings and a user-adjusted editor.
vim.g.neovide_normal_opacity = 0.4
vim.g.glow_windows_appearance = { light = { material_blend = 12, popup_blend = 10 } }
transparency.apply()
assert(vim.g.neovide_normal_opacity == 0.4, "user opacity was overwritten")
assert(window_material().blend == 10)
assert(vim.api.nvim_get_hl(0, {}).SnacksNormal.blend == 12)
profiles.config.terminal = { mode = "custom", blend = 67 }
transparency.apply()
assert(window_material().blend == 67, "explicit terminal policy was capped")
profiles.config.terminal = { mode = "editor" }
windows = false
vim.g.neovide_normal_opacity = 0.85
local data = theme("light")
transparency.apply()
assert(window_material().blend == 15 and vim.api.nvim_get_hl(0, {}).SnacksNormal.blend == 80, "Mac behavior changed")
assert(window_material().bg == rgb(data.base_30.black))
vim.api.nvim_win_close(win, true)
vim.fn.has = original_has
print("PASS Windows material: real Ayu light/dark events, terminal/Matrix/completion/panel consistency, RGB and user-policy preservation")
