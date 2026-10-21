-- Platform modeled, no GUI or user config loaded.
-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE
--   -l tests/navigation/windows_appearance.lua
local config = assert(vim.env.GLOW_TEST_CONFIG, "GLOW_TEST_CONFIG is required")
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local has = vim.fn.has
local windows = false
vim.fn.has = function(name)
  return name == "win32" and (windows and 1 or 0) or has(name)
end
local names = { "floating_shadow", "floating_z_height", "light_angle_degrees", "floating_corner_radius" }
local function fresh()
  package.loaded["config.platform.windows_appearance"] = nil
  for _, name in ipairs(names) do
    vim.g["neovide_" .. name] = nil
  end
  vim.g.glow_windows_appearance = nil
  return require("config.platform.windows_appearance")
end
local module = fresh()
vim.g.neovide = true
vim.g.neovide_opacity = 0.77
vim.g.neovide_normal_opacity = 0.66
vim.g.neovide_floating_blur_amount_x = 24
assert(module.setup() == false, "Mac/Linux must remain untouched")
assert(vim.g.neovide_floating_z_height == nil)
windows = true
vim.g.neovide = false
assert(module.setup() == false, "terminal Neovim must remain untouched")
vim.g.neovide = true
vim.g.neovide_floating_shadow = false
vim.g.neovide_floating_corner_radius = 0.2
vim.g.glow_windows_appearance = { floating_z_height = 4, floating_shadow = true }
assert(module.setup())
assert(vim.g.neovide_floating_shadow == false, "explicit false must survive")
assert(vim.g.neovide_floating_corner_radius == 0.2, "explicit geometry must survive")
assert(vim.g.neovide_floating_z_height == 4 and vim.g.neovide_light_angle_degrees == 45)
vim.g.glow_windows_appearance = { floating_z_height = 7 }
module.setup()
assert(vim.g.neovide_floating_z_height == 7, "hot setup must refresh owned values")
vim.g.neovide_floating_z_height = 3
module.setup()
assert(vim.g.neovide_floating_z_height == 3, "runtime user change must survive")
module = fresh()
vim.g.glow_windows_appearance = { floating_z_height = -1, light_angle_degrees = 90, floating_corner_radius = "bad" }
module.setup()
assert(vim.g.neovide_floating_shadow == true)
assert(vim.g.neovide_floating_z_height == 6)
assert(vim.g.neovide_light_angle_degrees == 45 and vim.g.neovide_floating_corner_radius == 0.48)
assert(vim.g.neovide_opacity == 0.77 and vim.g.neovide_normal_opacity == 0.66)
assert(vim.g.neovide_floating_blur_amount_x == 24, "material blur must not be changed")
-- Real frontend startup ordering: read_initial_values publishes these defaults
-- before UI attach lets user init.lua install the platform configuration.
vim.o.background = "light"
module = fresh()
vim.g.neovide_floating_shadow = true
vim.g.neovide_floating_z_height = 10
vim.g.neovide_light_angle_degrees = 45
vim.g.neovide_floating_corner_radius = 0
vim.g.neovide_normal_opacity = 1
module.setup({ initialize = true })
assert(vim.g.neovide_floating_z_height == 6 and vim.g.neovide_normal_opacity == 0.98,
  "published frontend defaults must not be mistaken for explicit user choices")
assert(vim.g.neovide_floating_corner_radius == 0.48)
vim.g.neovide_floating_z_height = 3
vim.g.neovide_normal_opacity = 0.72
module.setup({ initialize = true })
module.setup()
assert(vim.g.neovide_floating_z_height == 3 and vim.g.neovide_normal_opacity == 0.72,
  "repeated initialization/theme refresh must preserve later user changes")
module = fresh()
vim.g.neovide_floating_z_height = 10
vim.g.neovide_normal_opacity = 1
vim.g.glow_windows_appearance = {
  floating_shadow = false, floating_z_height = 4, light = { normal_opacity = 0.95 },
}
module.setup({ initialize = true })
assert(vim.g.neovide_floating_shadow == false and vim.g.neovide_floating_z_height == 4
  and vim.g.neovide_normal_opacity == 0.95, "startup profile overrides must survive frontend defaults")
vim.fn.has = has
print("PASS Windows appearance: platform guard, frontend 1/10 defaults, startup overrides, runtime ownership, material preservation")
