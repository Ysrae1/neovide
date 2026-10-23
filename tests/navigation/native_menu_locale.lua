-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE -l tests/navigation/native_menu_locale.lua
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local original_stdpath, original_has = vim.fn.stdpath, vim.fn.has
local original_notify, original_host = vim.rpcnotify, _G.neovide
local state = vim.fn.tempname()
vim.fn.stdpath = function(name)
  return name == "state" and state or name == "config" and (state .. "/config") or original_stdpath(name)
end
local mac = true
vim.fn.has = function(name)
  if name == "macunix" then return mac and 1 or 0 end
  return original_has(name)
end
vim.g.mapleader, vim.g.glow_ui_language = " ", "en"
vim.g.neovide_native_menu_version, vim.g.neovide_channel_id = nil, 17
_G.neovide = {}
local calls = {}
vim.rpcnotify = function(channel, method, snapshot)
  assert(channel == 17 and method == "neovide.native_menu.language")
  assert(snapshot.version == 1)
  calls[#calls + 1] = snapshot.language
end
local ok, err = xpcall(function()
  local locale = require("config.platform.locale")
  assert(#calls == 0, "old hosts must not receive unsupported RPC")
  dofile("lua/native_menu.lua")
  assert(vim.deep_equal(calls, { "en" }), "late capability must publish current preference")
  locale.set_lang("zh", { silent = true, save = false })
  locale.set_lang("en", { silent = true, save = false })
  assert(vim.deep_equal(calls, { "en", "zh", "en" }), "language changes must reach native host")
  require("config.locale.native_menu").setup(locale)
  calls = {}
  locale.set_lang("zh", { silent = true, save = false })
  assert(vim.deep_equal(calls, { "zh" }), "repeated setup must not duplicate subscriptions")
  mac = false
  locale.set_lang("en", { silent = true, save = false })
  assert(#calls == 1, "Windows and Linux must not send the macOS RPC")
  mac = true
  vim.g.neovide_native_menu_version = 2
  locale.set_lang("zh", { silent = true, save = false })
  assert(#calls == 1, "unknown capability versions must not send")
  assert(not pcall(_G.neovide.set_native_menu_language, "fr"), "invalid languages must be rejected")
  print("PASS native menu bridge: capability readiness, en/zh/en RPC, idempotent setup, legacy/non-Mac/version guards")
end, debug.traceback)
vim.fn.stdpath, vim.fn.has, vim.rpcnotify, _G.neovide = original_stdpath, original_has, original_notify, original_host
vim.fn.delete(state, "rf")
if not ok then error(err) end
