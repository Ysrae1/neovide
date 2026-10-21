-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE
--   -l tests/navigation/neovide_zoom.lua
-- Uses an isolated state directory; models platform detection, not GUI key events.
local config = assert(vim.env.GLOW_TEST_CONFIG, "GLOW_TEST_CONFIG is required")
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local state = vim.fn.tempname()
local original_stdpath = vim.fn.stdpath
local original_has = vim.fn.has
vim.fn.stdpath = function(name)
  if name == "state" then
    return state
  elseif name == "config" then
    return state .. "/config"
  end
  return original_stdpath(name)
end

local ok, err = xpcall(function()
  vim.g.neovide = true
  local zoom = require("config.platform.neovide_zoom")
  assert(not package.loaded["config.media.notebook"], "zoom must not initialize Notebook")
  assert(not package.loaded["config.platform.neovide"], "zoom must not initialize the platform")
  local platform = "win32"
  vim.fn.has = function(name)
    if name == "win32" or name == "macunix" then
      return name == platform and 1 or 0
    end
    return original_has(name)
  end

  vim.g.neovide_scale_factor = 0.8
  zoom.setup({ load = false })
  assert(vim.g.neovide_scale_factor == 0.8, "hot-load must retain the active scale")
  local modes = { "n", "i", "v", "c", "t" }
  local actions = { ["<C-=>"] = 1.1, ["<C-+>"] = 1.1, ["<C-->"] = 0.9, ["<C-0>"] = 1.0 }
  for _, mode in ipairs(modes) do
    for key, expected in pairs(actions) do
      local mapping = vim.fn.maparg(key, mode, false, true)
      assert(type(mapping.callback) == "function", "missing Windows " .. mode .. " " .. key)
      vim.g.neovide_scale_factor = 1.0
      mapping.callback()
      assert(math.abs(vim.g.neovide_scale_factor - expected) < 0.000001, "incorrect action " .. key)
    end
  end
  vim.g.neovide_scale_factor = 1.98
  zoom.adjust(0.1)
  assert(vim.g.neovide_scale_factor == 2.0, "upper bound changed")
  vim.g.neovide_scale_factor = 0.52
  zoom.adjust(-0.1)
  assert(vim.g.neovide_scale_factor == 0.5, "lower bound changed")
  vim.g.neovide_scale_factor = math.huge
  zoom.adjust(0.1)
  assert(vim.g.neovide_scale_factor == 1.1, "invalid scale must recover")
  zoom.reset()
  assert(vim.g.neovide_scale_factor == 1.0, "reset changed")

  vim.g.neovide_scale_factor = 0.9
  zoom.save_scale_factor()
  vim.g.neovide_scale_factor = 1.5
  zoom.load_scale_factor()
  assert(vim.g.neovide_scale_factor == 0.9, "saved scale must reload")
  zoom.setup({ load = false })
  assert(#vim.api.nvim_get_autocmds({ group = "UserNeovideScale" }) == 2, "setup must not duplicate persistence")

  platform = "macunix"
  zoom.setup({ load = false })
  local mac_actions = { ["<D-=>"] = 1.1, ["<D-+>"] = 1.1, ["<D-->"] = 0.9, ["<D-0>"] = 1.0 }
  for key, expected in pairs(mac_actions) do
    local mapping = vim.fn.maparg(key, "n", false, true)
    assert(type(mapping.callback) == "function", "missing Mac " .. key)
    vim.g.neovide_scale_factor = 1.0
    mapping.callback()
    assert(math.abs(vim.g.neovide_scale_factor - expected) < 0.000001, "incorrect Mac action " .. key)
  end
  print("PASS Neovide zoom: Windows n/i/v/c/t bindings, bounds/reset, persistence, safe hot-load, standard Mac plus/minus/reset bindings")
end, debug.traceback)

pcall(vim.api.nvim_del_augroup_by_name, "UserNeovideScale")
vim.fn.stdpath, vim.fn.has = original_stdpath, original_has
vim.fn.delete(state, "rf")
if not ok then
  error(err)
end
