-- GLOW_TEST_CONFIG=... nvim --headless --noplugin -u NONE -l tests/config/window_drag.lua
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local drag = require("config.appearance.window_drag")
local labels = "%@Buffer@ 文件名 %X%#TbFill#%=%@Tab@ 2 %X%@GitHub@ GitHub %X%@Close@ X %X"
vim.g.neovide_window_drag_supported = false
assert(drag.wrap(labels) == labels, "old or non-Windows GUI keeps its tabline")
vim.g.neovide_window_drag_supported = true
local expected = "%@Buffer@ 文件名 %X%#TbFill#%@v:lua.GlowWindowDrag@%=%T%@Tab@ 2 %X%@GitHub@ GitHub %X%@Close@ X %X"
assert(drag.wrap(labels) == expected, "only the explicit alignment fill becomes draggable")
assert(drag.wrap(drag.wrap(labels)) == expected, "wrapping is idempotent")
assert(drag.wrap("%@Buffer@   %X") == "%@Buffer@   %X", "blank button padding remains clickable")
assert(drag.wrap("%#OtherFill#%=") == "%#OtherFill#%=", "unknown tabline layouts are not inferred")

local calls = {}
vim.rpcnotify = function(channel, method, packet)
  calls[#calls + 1] = { channel, method, packet }
end
vim.fn.getmousepos = function() return { screenrow = 1, screencol = 42 } end
vim.g.neovide_channel_id = 84
drag.click(0, 1, "l", "    ")
assert(vim.deep_equal(calls, { { 84, "neovide.window.start_drag", { version = 1, row = 0, column = 41 } } }))
for _, args in ipairs({ { 0, 1, "r", "" }, { 0, 1, "m", "" }, { 0, 2, "l", "" },
  { 0, 1, "l", "s" }, { 0, 1, "l", "c" }, { 0, 1, "l", "a" }, { 0, 1, "l", "m" } }) do
  drag.click(unpack(args))
end
assert(#calls == 1, "other buttons, double clicks and modified clicks do not request a native move")
vim.fn.getmousepos = function() return { screenrow = 2, screencol = 42 } end
drag.click(0, 1, "l", "")
vim.g.neovide_channel_id = nil
drag.click(0, 1, "l", "")
assert(#calls == 1, "only a root tabline click on a live frontend channel can request a move")

vim.g.neovide = true
vim.o.tabline = "%!v:lua.require('nvchad.tabufline.modules')()"
drag.setup()
vim.api.nvim_exec_autocmds("User", { pattern = "NeovideWindowDragReady" })
assert(vim.o.tabline == "%!v:lua.require('config.appearance.window_drag').render()")
vim.o.showtabline = 0
drag.attach()
assert(vim.o.showtabline == 0, "drag attachment must never reveal a hidden tabline")
vim.o.tabline = "%!CustomTabline()"
drag.attach()
assert(vim.o.tabline == "%!CustomTabline()", "a later custom tabline remains owned by its provider")
vim.o.showtabline = 0
drag.attach()
assert(vim.o.showtabline == 0, "custom tabline visibility remains owned by its provider")
vim.g.neovide_window_drag_supported = false
vim.o.tabline = "%!v:lua.require('nvchad.tabufline.modules')()"
drag.attach()
assert(vim.o.showtabline == 0 and vim.o.tabline:find("nvchad", 1, true), "unsupported frontends keep their original visibility")
print("PASS: frameless tabline drag markup, control preservation, capability and click guards")
