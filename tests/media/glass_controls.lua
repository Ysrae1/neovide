-- nvim --headless -u NONE -l tests/media/glass_controls.lua
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or (vim.fn.getcwd() .. '/portable/payload/nvim'))
vim.g.neovide = true
vim.g.neovide_native_glass = true
vim.g.neovide_opacity = 1
vim.g.neovide_normal_opacity = .78
vim.g.neovide_floating_blur_amount_x = 24
vim.g.neovide_floating_blur_amount_y = 24
vim.notify = function() end
require('config.platform.glass').setup()
assert(vim.g.neovide_liquid_glass == true)
vim.cmd('GlowGlass off'); assert(vim.g.neovide_liquid_glass == false)
vim.cmd('GlowGlass on'); assert(vim.g.neovide_liquid_glass == true)
vim.cmd('GlowGlass opacity 0.55')
assert(vim.g.neovide_normal_opacity == .55 and vim.g.neovide_opacity == 1, 'only background fades; text and selection stay readable')
vim.cmd('GlowGlass blur 18')
assert(vim.g.neovide_floating_blur_amount_x == 18 and vim.g.neovide_floating_blur_amount_y == 18)
vim.cmd('GlowGlass opacity -1'); assert(vim.g.neovide_normal_opacity == .55)
vim.cmd('GlowGlass blur 1000'); assert(vim.g.neovide_floating_blur_amount_x == 18)
vim.cmd('GlowGlass reset')
assert(vim.g.neovide_liquid_glass == true and vim.g.neovide_opacity == 1 and vim.g.neovide_normal_opacity == .78)
assert(vim.g.neovide_floating_blur_amount_x == 24 and vim.g.neovide_floating_blur_amount_y == 24)
print('PASS: runtime Glass switch, opacity, blur, validation and configured-default reset')
vim.cmd.qa()
