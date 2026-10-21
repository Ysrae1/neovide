-- Real LazyVim shell configuration, with platform/tool availability modeled.
-- Does not spawn a shell or change the user's terminal/profile settings.
-- GLOW_TEST_CONFIG=/path/to/config GLOW_LAZYVIM_PLUGIN=/path/to/LazyVim
-- nvim --headless --noplugin -u NONE -i NONE -l tests/navigation/windows_shell.lua
local config = assert(vim.env.GLOW_TEST_CONFIG, "GLOW_TEST_CONFIG is required")
local lazyvim = assert(vim.env.GLOW_LAZYVIM_PLUGIN, "GLOW_LAZYVIM_PLUGIN is required")
vim.opt.rtp = { config, lazyvim, vim.env.VIMRUNTIME }
local module = require("config.platform.windows_shell")
local original = { has = vim.fn.has, executable = vim.fn.executable }
local original_toggleterm = package.loaded["toggleterm.config"]
local toggleterm_options = { shell = "cmd.exe", direction = "float", shading_factor = 2 }
package.loaded["toggleterm.config"] = { get = function() return toggleterm_options end }
local names = { "shell", "shellcmdflag", "shellredir", "shellpipe", "shellquote", "shellxquote" }
local before = {}
for _, name in ipairs(names) do
  before[name] = vim.o[name]
end
local windows, available = false, {}
vim.fn.has = function(name)
  if name == "win32" then
    return windows and 1 or 0
  end
  return original.has(name)
end
vim.fn.executable = function(name)
  return available[name] and 1 or 0
end

local ok, err = xpcall(function()
  local function reset()
    for name, value in pairs(before) do
      vim.o[name] = value
    end
  end
  local function unchanged()
    for name, value in pairs(before) do
      assert(vim.o[name] == value, "changed " .. name .. " outside PowerShell setup")
    end
  end
  available = { pwsh = true, powershell = true }
  assert(module.setup() == false)
  unchanged()
  assert(toggleterm_options.shell == "cmd.exe", "non-Windows must not touch loaded terminals")

  windows = true
  assert(module.setup() == "pwsh", "PowerShell 7 must take precedence")
  assert(vim.o.shell == "pwsh")
  assert(toggleterm_options.shell == "pwsh", "future ToggleTerm jobs must use the same shell")
  assert(toggleterm_options.direction == "float" and toggleterm_options.shading_factor == 2,
    "terminal window settings must be preserved")
  assert(vim.o.shellcmdflag:find("System.Text.UTF8Encoding", 1, true), "missing UTF-8 command setup")
  local guarded_style = "if (Get-Variable -Name PSStyle -ErrorAction Ignore) {$PSStyle.OutputRendering='plaintext';};"
  assert(vim.o.shellcmdflag:find(guarded_style, 1, true), "PSStyle must be optional on 5.1 and pre-7.2 pwsh")
  assert(vim.o.shellcmdflag:find("$PSDefaultParameterValues['Out-File:Encoding']='utf8';", 1, true),
    "Out-File must retain UTF-8 output")
  local removal = "Remove-Item -LiteralPath Alias:tee -Force -ErrorAction SilentlyContinue;"
  assert(vim.o.shellcmdflag:find(removal, 1, true) and not vim.o.shellcmdflag:find("Remove-Alias", 1, true),
    "tee alias removal must work in both Windows PowerShell 5.1 and pwsh")
  assert(vim.o.shellcmdflag:find("-Command", 1, true), "missing PowerShell command flag")
  assert(not vim.o.shellcmdflag:lower():find("-noprofile", 1, true), "interactive profiles must remain available")
  assert(vim.o.shellredir:find("Out-File", 1, true), "missing PowerShell redirection")
  assert(vim.o.shellpipe:find("$LastExitCode", 1, true), "pipeline must retain command exit status")
  assert(vim.o.shellquote == "" and vim.o.shellxquote == "", "cmd quoting must be cleared")
  local first_flags = vim.o.shellcmdflag
  assert(module.setup() == "pwsh", "setup may run in an existing session")
  assert(vim.o.shellcmdflag == first_flags, "repeated setup must not nest the compatibility guard")

  reset()
  available.pwsh = nil
  assert(module.setup() == "powershell", "Windows PowerShell must be the fallback")
  assert(toggleterm_options.shell == "powershell")
  assert(vim.o.shellcmdflag:find("-Command", 1, true))
  assert(vim.o.shellcmdflag:find(guarded_style, 1, true), "Windows PowerShell fallback must not assign absent PSStyle")
  assert(vim.o.shellcmdflag:find(removal, 1, true), "5.1 fallback must use the Alias provider")

  reset()
  available = {}
  assert(module.setup() == false)
  unchanged()
  print("PASS Windows shell: real LazyVim UTF-8 rules, optional PSStyle, PS5 tee removal, pwsh precedence, profiles and idempotence")
end, debug.traceback)
vim.fn.has, vim.fn.executable = original.has, original.executable
package.loaded["toggleterm.config"] = original_toggleterm
for name, value in pairs(before) do
  vim.o[name] = value
end
if not ok then
  error(err)
end
