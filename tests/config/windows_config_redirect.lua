-- Native Windows or macOS isolated bootstrap contract; no real profile access.
-- nvim --headless --noplugin -u NONE -i NONE -l tests/config/windows_config_redirect.lua
local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
local helper = vim.env.GLOW_TEST_CONFIG_REDIRECT or (repo .. "/portable/windows/runtime/ConfigRedirect.lua")
local redirect = dofile(helper)
local work = vim.fs.normalize(vim.fn.tempname() .. "-config-redirect")
local old = work .. "/old profile/config/nvim"
local target = work .. "/User 中文 O'Connor, QA/.config/nvim"
local names = { "NVIM_APPNAME", "XDG_CONFIG_HOME", "MYVIMRC", "NEOVIDE_GLOW_LEGACY_CONFIG",
  "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "NEOVIDE_GLOW_INIT", "JUPYTER_CONFIG_DIR" }
local saved = { rtp = vim.o.runtimepath, pp = vim.o.packpath, env = {} }
for _, name in ipairs(names) do saved.env[name] = vim.env[name] end
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines, path) == 0)
end
local function prepare()
  package.loaded["neovide_glow.config_redirect_state"] = nil
  vim.env.NVIM_APPNAME = "nvim"
  vim.env.XDG_CONFIG_HOME = vim.fs.dirname(old)
  vim.env.MYVIMRC = old .. "/init.lua"
  vim.env.NEOVIDE_GLOW_LEGACY_CONFIG = nil
  vim.opt.runtimepath = { old, old .. "-other", old .. "/after", work .. "/unrelated" }
  vim.opt.packpath = { old, old .. "/after", work .. "/packages" }
end
local function snapshot()
  local state = { rtp = vim.o.runtimepath, pp = vim.o.packpath, env = {} }
  for _, name in ipairs(names) do state.env[name] = vim.env[name] end
  return state
end
local function rejected(path, expected)
  local before = snapshot()
  local ok, err = pcall(redirect.load, path, { legacy_config = old })
  assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
  assert(vim.deep_equal(before, snapshot()), "failure changed bootstrap paths/environment")
end
local ok, err = xpcall(function()
  write(old .. "/init.lua", { "-- original user configuration" })
  write(target .. "/init.lua", {
    'local config = vim.fs.normalize(vim.fn.stdpath("config"), { expand_env = false }):gsub("/+$", "")',
    'local expected = vim.fs.normalize(vim.fs.dirname(vim.env.MYVIMRC), { expand_env = false }):gsub("/+$", "")',
    'if vim.fn.has("win32") == 1 then config, expected = config:lower(), expected:lower() end',
    'assert(config == expected, "stdpath(config) does not identify the redirected configuration")',
    'assert(require("redirect_fixture").value == "user theme retained")',
    'dofile(vim.env.NEOVIDE_GLOW_INIT)',
    'return "migrated init loaded"',
  })
  write(target .. "/lua/redirect_fixture.lua", { 'return { value = "user theme retained" }' })
  write(old .. "/lua/redirect_fixture.lua", { 'error("old module must not load")' })
  write(work .. "/WindowsInit.lua", { '_G.redirect_runtime_calls = (_G.redirect_runtime_calls or 0) + 1' })
  vim.env.NEOVIDE_GLOW_INIT = work .. "/WindowsInit.lua"
  vim.env.XDG_DATA_HOME, vim.env.XDG_STATE_HOME, vim.env.XDG_CACHE_HOME = work .. "/data", work .. "/state", work .. "/cache"
  vim.env.JUPYTER_CONFIG_DIR = work .. "/profile/config/jupyter"
  prepare()
  local before = snapshot()
  local rollback = redirect.activate(target, { legacy_config = old })
  assert(not _G.redirect_runtime_calls and not package.loaded.redirect_fixture, "activate executed init or loaded a user module")
  local active = snapshot()
  redirect.activate(target, { legacy_config = old })
  assert(vim.deep_equal(active, snapshot()), "repeated activate changed paths")
  redirect.activate(target)
  assert(vim.deep_equal(active, snapshot()), "repeat without opts lost legacy path")
  redirect.restore(rollback)
  assert(vim.deep_equal(before, snapshot()), "explicit activation rollback failed")
  assert(redirect.load(target, { legacy_config = old }) == "migrated init loaded")
  assert(redirect.load(target, { legacy_config = old }) == "migrated init loaded", "repeat load lost its result")
  assert(vim.env.NEOVIDE_GLOW_LEGACY_CONFIG == old and vim.env.MYVIMRC == target .. "/init.lua")
  local escaped = target:gsub(",", "\\,")
  assert(vim.o.runtimepath == table.concat({ escaped, old .. "-other", escaped .. "/after", work .. "/unrelated" }, ","))
  assert(vim.o.packpath == table.concat({ escaped, escaped .. "/after", work .. "/packages" }, ","))
  for _, name in ipairs({ "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "NEOVIDE_GLOW_INIT", "JUPYTER_CONFIG_DIR" }) do
    assert(vim.env[name] == before.env[name], name .. " changed")
  end
  assert(_G.redirect_runtime_calls == 1 and vim.fn.readfile(old .. "/init.lua")[1] == "-- original user configuration")

  prepare()
  rejected(work .. "/missing/nvim", "does not exist")
  rejected("relative/nvim", "must be absolute")
  rejected(old, "own source")
  local noinit = work .. "/missing-init/nvim"
  vim.fn.mkdir(noinit, "p")
  rejected(noinit, "init.lua is missing")
  write(target .. "/init.lua", { "invalid lua syntax !" })
  rejected(target, "Cannot load Glow configuration")
  write(target .. "/init.lua", { 'error("fixture failure")' })
  rejected(target, "fixture failure")
  write(target .. "/init.lua", { string.format("return dofile(%q).load(%q, {legacy_config=%q})", helper, target, old) })
  rejected(target, "Recursive Glow configuration redirect")
  vim.env.NVIM_APPNAME = "another-editor"
  rejected(target, "NVIM_APPNAME=nvim")
end, debug.traceback)
for _, name in ipairs(names) do vim.env[name] = saved.env[name] end
vim.o.runtimepath, vim.o.packpath = saved.rtp, saved.pp
package.loaded.redirect_fixture = nil
package.loaded["neovide_glow.config_redirect_state"] = nil
vim.fn.delete(work, "rf")
assert(ok, err)
print("Config redirect passed: target modules/init, precise search paths, private data/runtime retained, no writes, guarded failures and rollback")
vim.cmd("qa!")
