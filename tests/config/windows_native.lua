-- Isolated compatibility checks: model Windows APIs without launching programs
-- or changing installed configuration. Yazi's overlay helper runs on fixtures.
local config = assert(vim.env.GLOW_TEST_CONFIG, "GLOW_TEST_CONFIG is required")
local root = vim.fn.tempname() .. "-windows-config"
vim.fn.mkdir(root, "p")

local function load_spec(relative, windows, extra)
  extra = extra or {}
  local env = { HOME = "/home/test", USERPROFILE = "C:/Users/Test", PATH = "C:/Bundle/bin",
    OPENAI_API_KEY = "fixture-openai", CODEX_API_KEY = "fixture-codex" }
  for name, value in pairs(extra.env or {}) do env[name] = value end
  local mock = {
    env = env, g = {}, log = vim.log, notify = function() end,
    fn = {
      has = function(name) return windows and name == "win32" and 1 or 0 end,
      exepath = function(name) return (extra.paths or {})[name] or "" end,
      executable = function(name) return (extra.paths or {})[name] and 1 or 0 end,
      stdpath = function() return "C:/Bundle/data" end,
      environ = function()
        return { PATH = env.PATH, SystemRoot = "C:/Windows", TEMP = "C:/Temp", USERPROFILE = env.USERPROFILE,
          OPENAI_API_KEY = "fixture-openai", codex_api_key = "fixture-codex" }
      end,
    },
    api = { nvim_create_autocmd = function() end, nvim_create_augroup = function() return 1 end },
    keymap = { set = function() end },
  }
  local chunk = assert(loadfile(config .. "/" .. relative))
  setfenv(chunk, setmetatable({ vim = mock }, { __index = _G }))
  return chunk(), mock
end

local ai = "lua/plugins/ai/avante.lua"
local spec = load_spec(ai, true, { paths = { node = "C:/Program Files/Glow/node.exe" } })[1]
local codex = spec.opts.acp_providers.codex
assert(codex.command == "C:/Program Files/Glow/node.exe" and #codex.args == 1)
assert(codex.args[1]:match("/codex%-acp/node_modules/@agentclientprotocol/codex%-acp/dist/index.js$"))
assert(codex.env.OPENAI_API_KEY == nil and codex.env.codex_api_key == nil, "API keys excluded case-insensitively")
assert(codex.env.SystemRoot == "C:/Windows" and codex.env.HOME == "C:/Users/Test", "Windows spawn environment retained")
assert(spec.build:find("Build.ps1", 1, true) and not spec.build:find("make", 1, true))
local function converter(value) return value.dependencies[#value.dependencies].opts.latex.converter end
assert(converter(spec) == "C:/Bundle/data/latex2text-venv/Scripts/latex2text.exe")
assert(converter(load_spec(ai, true, { env = { GLOW_LATEX2TEXT = "C:/Bundle/bin/latex2text.exe" } })[1])
  == "C:/Bundle/bin/latex2text.exe")
local unix = load_spec(ai, false)[1]
assert(unix.opts.acp_providers.codex.command:match("env$") and unix.opts.acp_providers.codex.args[1] == "-u")
assert(converter(unix) == "C:/Bundle/data/latex2text-venv/bin/latex2text")

local viewer = "lua/plugins/languages/vimtex.lua"
local sumatra, sumatra_vim = load_spec(viewer, true)
sumatra.init()
assert(sumatra_vim.g.vimtex_view_method == "sumatra_async", "Windows needs both directions, not the generic browser opener")
assert(vim.tbl_contains(sumatra_vim.g.vimtex_compiler_latexmk.options, "-synctex=1"))

vim.opt.rtp = { config, vim.env.VIMRUNTIME }
vim.g.neovide_native_image, vim.g.neovide_channel_id = true, 42
local uv = vim.uv or vim.loop
local saved = { symlink = uv.fs_symlink, has = vim.fn.has, exepath = vim.fn.exepath,
  system = vim.fn.system, runtime = package.loaded["config.media.runtime"],
  appdata = vim.env.APPDATA, config_home = vim.env.YAZI_CONFIG_HOME }
local python = vim.env.GLOW_TEST_PYTHON or vim.fn.exepath("python3")
assert(python ~= "", "Python 3.11+ is required for the fixture overlay")
local original = '[mgr]\nshow_hidden = true\n'
local function fixture(path)
  vim.fn.mkdir(path .. "/plugins/custom.yazi/nested", "p")
  vim.fn.mkdir(path .. "/flavors/test.yazi", "p")
  vim.fn.writefile(vim.split(original, "\n", { trimempty = true }), path .. "/yazi.toml")
  vim.fn.writefile({ "custom theme" }, path .. "/theme.toml")
  vim.fn.writefile({ "return {}" }, path .. "/plugins/custom.yazi/main.lua")
  vim.fn.writefile({ "nested fixture" }, path .. "/plugins/custom.yazi/nested/file.txt")
  vim.fn.writefile({ "flavor fixture" }, path .. "/flavors/test.yazi/flavor.toml")
end
local defaults = root .. "/Roaming/yazi/config"
local overridden = root .. "/override with spaces and 'quotes'"
fixture(defaults)
fixture(overridden)
local generated, calls = {}, {}
local ok, err = xpcall(function()
  vim.fn.has = function(name) return name == "win32" and 1 or saved.has(name) end
  uv.fs_symlink = function() return nil, "EPERM: fixture disallows symlinks" end
  vim.fn.exepath = function(name)
    if name == "python3" then return "" end
    if name == "python" then return python end
    return saved.exepath(name)
  end
  package.loaded["config.media.runtime"] = { python = function() return root .. "/not-installed-python" end }
  vim.fn.system = function(command)
    calls[#calls + 1] = command
    return saved.system(command)
  end
  vim.env.APPDATA, vim.env.YAZI_CONFIG_HOME = root .. "/Roaming", nil
  local function check(options, expected)
    package.loaded["config.media.yazi"] = nil
    local result = require("config.media.yazi").configure(options)
    generated[#generated + 1] = result.config_home
    result.hooks.before_opening_window({})
    local command = calls[#calls]
    assert(command[1] == python and command[3] == vim.fs.normalize(expected), "Python fallback and config source")
    assert(uv.fs_lstat(result.config_home .. "/theme.toml").type == "file", "symlink privilege failure copies files")
    assert(uv.fs_lstat(result.config_home .. "/plugins/custom.yazi").type == "directory", "copies plugin directories")
    assert(vim.fn.readfile(result.config_home .. "/plugins/custom.yazi/nested/file.txt")[1] == "nested fixture")
    assert(vim.fn.readfile(result.config_home .. "/flavors/test.yazi/flavor.toml")[1] == "flavor fixture")
    assert(table.concat(vim.fn.readfile(result.config_home .. "/yazi.toml"), "\n"):find("neovide-glow-native-preview", 1, true), "preview bridge remains installed")
    assert(table.concat(vim.fn.readfile(expected .. "/yazi.toml"), "\n") .. "\n" == original, "source config preserved")
  end
  check({}, defaults)
  vim.env.YAZI_CONFIG_HOME = overridden
  check({}, overridden)
  check({ config_home = defaults }, defaults)
  vim.fn.has = saved.has
  package.loaded["config.media.yazi"] = nil
  local denied = require("config.media.yazi").configure({ config_home = defaults })
  generated[#generated + 1] = denied.config_home
  local linked, link_error = pcall(denied.hooks.before_opening_window, {})
  assert(not linked and tostring(link_error):find("EPERM", 1, true), "copy fallback is Windows-only")
  uv.fs_symlink, vim.fn.exepath = saved.symlink, saved.exepath
  package.loaded["config.media.yazi"] = nil
  local unix_overlay = require("config.media.yazi").configure({ config_home = defaults })
  generated[#generated + 1] = unix_overlay.config_home
  unix_overlay.hooks.before_opening_window({})
  assert(uv.fs_lstat(unix_overlay.config_home .. "/theme.toml").type == "link", "Unix symlink behavior preserved")
end, debug.traceback)
uv.fs_symlink, vim.fn.has, vim.fn.exepath, vim.fn.system = saved.symlink, saved.has, saved.exepath, saved.system
vim.env.APPDATA, vim.env.YAZI_CONFIG_HOME = saved.appdata, saved.config_home
package.loaded["config.media.runtime"] = saved.runtime
for _, target in ipairs(generated) do vim.fn.delete(target, "rf") end
vim.fn.delete(root, "rf")
assert(ok, err)
print("Windows config: ACP environment, native build command, converter, PDF viewer and Yazi copy overlay passed")
vim.cmd("qa!")
