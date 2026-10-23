-- Isolated real Neovim options/events and Avante split; no GUI or provider.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local real_has, platform = vim.fn.has, "macos"
vim.fn.has = function(name)
  if name == "macunix" then return platform == "macos" and 1 or 0 end
  if name == "win32" then return platform == "windows" and 1 or 0 end
  return real_has(name)
end
vim.g.neovide, vim.g.neovide_native_glass = true, true
vim.g.neovide_opacity = 1
vim.g.neovide_normal_opacity = 1 -- Published frontend startup default.
vim.g.neovide_floating_blur_amount_x, vim.g.neovide_floating_blur_amount_y = 24, 24
vim.g.neovide_floating_z_height, vim.g.neovide_floating_corner_radius = 2, .48
vim.g.neovide_scale_factor = 1.12
vim.o.guifont = "FiraCode Nerd Font Mono,PingFang SC:h16"
local font = vim.o.guifont
vim.api.nvim_set_hl(0, "Normal", { fg = 0x5c6166, bg = 0xfafafa })
vim.api.nvim_set_hl(0, "NormalFloat", { fg = 0x5c6166, bg = 0xf0f0f0 })
local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
local appearance = require("config.platform.macos_appearance")
local saved_config = vim.deepcopy(appearance.config)
assert(appearance.setup() and vim.g.neovide_normal_opacity == saved_config[vim.o.background].normal_opacity, "startup saved default")
require("config.platform.glass").setup()
vim.cmd("GlowGlass opacity 0.61")
assert(vim.g.neovide_normal_opacity == .61, "temporary Glass value")

-- Exercise the real editor-material consumer, including ordinary Avante splits.
vim.cmd("rightbelow vnew")
local sidebar = vim.api.nvim_get_current_win()
vim.bo.filetype = "Avante"
vim.wo.winhighlight = "Normal:AvanteSidebarNormal"
vim.api.nvim_set_hl(0, "AvanteSidebarNormal", { link = "NormalFloat" })
require("config.appearance.transparency")
local function sidebar_blend()
  local namespace = vim.api.nvim_get_hl_ns({ winid = sidebar })
  return vim.api.nvim_get_hl(namespace, { name = "Normal", link = false }).blend
end
appearance.config.light.normal_opacity = .96
appearance.config.dark.normal_opacity = .73
for _, theme in ipairs({ "light", "dark", "light" }) do
  local expected = theme == "light" and .96 or .73
  vim.o.background = theme
  -- Neovim may install its builtin default colors when background changes;
  -- isolate our refresh from that builtin behavior with a known theme RGB.
  vim.api.nvim_set_hl(0, "Normal", normal)
  -- Ensure every pass also covers the public theme event, even if the first
  -- background already matches the selected theme.
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  assert(vim.g.neovide_normal_opacity == expected, theme .. " independent value")
  assert(sidebar_blend() == math.floor((1 - expected) * 100 + .5), theme .. " Avante editor material")
  assert(vim.deep_equal(normal, vim.api.nvim_get_hl(0, { name = "Normal" })), theme .. " theme RGB unchanged")
  vim.cmd("GlowGlass opacity 0.61")
  assert(vim.g.neovide_normal_opacity == .61 and sidebar_blend() == 39, theme .. " temporary Glass value immediately follows")
  vim.cmd("GlowGlass reset")
  assert(vim.g.neovide_normal_opacity == expected and sidebar_blend() == math.floor((1 - expected) * 100 + .5), theme .. " reset uses current theme")
end
vim.cmd("GlowGlass opacity 0.61")
assert(vim.g.neovide_normal_opacity == .61, "runtime change remains temporary")
vim.api.nvim_exec_autocmds("User", { pattern = "NvThemeReload" })
assert(vim.g.neovide_normal_opacity == .96 and sidebar_blend() == 4, "NvThemeReload default and Avante")
vim.cmd("GlowGlass opacity 0.61")
vim.o.background = "dark" -- Real OptionSet rather than an artificial event.
assert(vim.g.neovide_normal_opacity == .73 and sidebar_blend() == 27, "background OptionSet")

assert(appearance.reload(), "saved module reload")
appearance = require("config.platform.macos_appearance")
local saved_opacity = saved_config[vim.o.background].normal_opacity
assert(vim.g.neovide_normal_opacity == saved_opacity and sidebar_blend() == math.floor((1 - saved_opacity) * 100 + .5), "reload reads saved config")
assert(#vim.api.nvim_get_autocmds({ group = "GlowMacOSAppearance" }) == 3, "reload replaces old callbacks")
for _, theme in ipairs({ "light", "dark" }) do
  vim.o.background = theme
  assert(vim.g.neovide_normal_opacity == saved_config[theme].normal_opacity, "both saved defaults remain unchanged")
end
for _ = 1, 3 do
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  vim.api.nvim_exec_autocmds("User", { pattern = "NvThemeReload" })
end
assert(#vim.api.nvim_get_autocmds({ group = "GlowMacOSAppearance" }) == 3, "repeated events retain one callback per event")
for _, value in ipairs({ -1, 1.1, "bad" }) do
  appearance.config.dark.normal_opacity = value
  assert(appearance.normal_opacity() == .85, "invalid input fallback")
end
assert(vim.g.neovide_opacity == 1 and vim.g.neovide_scale_factor == 1.12)
assert(vim.g.neovide_floating_blur_amount_x == 24 and vim.g.neovide_floating_blur_amount_y == 24)
assert(vim.g.neovide_floating_z_height == 2 and vim.g.neovide_floating_corner_radius == .48)
assert(vim.o.guifont == font, "font unchanged")

for _, target in ipairs({ "windows", "linux", "terminal" }) do
  platform, vim.g.neovide = target, target ~= "terminal"
  vim.g.neovide_normal_opacity = .42
  assert(appearance.setup() == false and appearance.apply() == false and appearance.reload() == false, target .. " guard")
  vim.api.nvim_exec_autocmds("User", { pattern = "NvThemeReload" })
  assert(vim.g.neovide_normal_opacity == .42, target .. " untouched")
end
vim.fn.has = real_has
print("PASS: Mac Light/Dark defaults, independent values, ColorScheme/NvThemeReload/background events, reload, temporary Glass opacity, Avante inheritance and platform/appearance guards")
