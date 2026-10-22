-- Isolated headless check. No terminal process or external shell is started.
vim.opt.rtp:prepend(assert(vim.env.GLOW_TEST_CONFIG))
local selected, prompt, selects, opened, callbacks = nil, nil, 0, 0, 0
local locale = {
  t = function(text) return text == "Command Prompt" and "命令提示符" or text end,
  command = function(name, callback, opts) vim.api.nvim_create_user_command(name, callback, opts) end,
  select = function(items, opts, callback)
    selects = selects + 1
    selected, prompt = callback, opts.prompt
    assert(#items == 2 and items[1].id == "zsh" and items[2].id == "powershell")
  end,
}
package.loaded["config.platform.locale"] = locale
local real_has, real_exepath, real_executable = vim.fn.has, vim.fn.exepath, vim.fn.executable
local executables = { ["C:/Program Files/Git/usr/bin/zsh.exe"] = true, ["C:/Windows/PowerShell/powershell.exe"] = true }
vim.fn.has = function(name) return name == "win32" and 1 or real_has(name) end
vim.fn.exepath = function(name)
  if name == "zsh" then return "C:/Program Files/Git/usr/bin/zsh.exe" end
  if name == "powershell" then return "C:/Windows/PowerShell/powershell.exe" end
  return executables[name] and name or ""
end
vim.fn.executable = function(path) return executables[path] and 1 or 0 end
vim.o.shell = "powershell.exe"
local globals = { vim.o.shell, vim.o.shellcmdflag, vim.o.shellquote, vim.o.shellxquote, vim.o.shellredir, vim.o.shellpipe }
local preference = vim.fn.stdpath("state") .. "/preferences/terminal-shell.json"
vim.fn.delete(preference)
local function provider()
  package.loaded["config.platform.terminal_shell"] = nil
  return require("config.platform.terminal_shell")
end
local m = provider()
m.with_shell(function() callbacks = callbacks + 1 end)
assert(selects == 1 and callbacks == 0 and prompt == "Choose Terminal Shell")
selected(nil)
assert(callbacks == 0 and vim.fn.filereadable(preference) == 0, "cancel must not select or start")
m.with_shell(function(shell)
  callbacks = callbacks + 1
  assert(vim.deep_equal(m.argv(shell), { "C:/Program Files/Git/usr/bin/zsh.exe", "-l", "-i" }))
  assert(m.command(shell) == "& 'C:/Program Files/Git/usr/bin/zsh.exe' '-l' '-i'")
end)
selected(m.available()[1])
assert(callbacks == 1 and vim.fn.filereadable(preference) == 1)
m = provider()
m.with_shell(function(shell) assert(shell.id == "zsh"); callbacks = callbacks + 1 end)
assert(selects == 2 and callbacks == 2, "selection must survive reload without a prompt")
local term = nil
package.loaded["toggleterm.terminal"] = {
  get_toggled_id = function() return term and 1 or nil end,
  get = function() return term end,
}
local toggle_config = {}
package.loaded["toggleterm.config"] = { get = function() return toggle_config end }
package.loaded.toggleterm = {
  toggle = function() opened = opened + 1 end,
  setup = function(opts) assert(opts.open_mapping == false) end,
}
m.toggleterm()
assert(opened == 1 and toggle_config.shell == "& 'C:/Program Files/Git/usr/bin/zsh.exe' '-l' '-i'")
local snack = nil
package.loaded["snacks.terminal"] = {
  get = function(cmd, opts) assert(opts.create == false); return snack end,
  toggle = function(cmd)
    assert(vim.deep_equal(cmd, { "C:/Program Files/Git/usr/bin/zsh.exe", "-l", "-i" }))
    snack = { toggle = function() opened = opened + 1 end }
    opened = opened + 1
  end,
}
m.snacks({ cwd = "C:/work" })
executables["C:/Program Files/Git/usr/bin/zsh.exe"] = nil
term = { job_id = 12 }
m.toggleterm()
m.snacks({ cwd = "C:/work" })
assert(opened == 4 and selects == 2, "existing terminals must toggle even if their shell disappears")
term = nil
-- New terminals reselect when a saved executable disappears.
locale.select = function(items, opts, callback)
  selects = selects + 1
  assert(#items == 1 and items[1].id == "powershell")
  selected = callback
end
m.with_shell(function(shell) assert(shell.id == "powershell"); callbacks = callbacks + 1 end)
assert(selects == 3 and callbacks == 2)
selected(m.available()[1])
assert(callbacks == 3 and m.current().id == "powershell")
_G.LazyVim = { root = function() return "C:/work" end }
vim.g.mapleader = " "
m.setup()
for _, key in ipairs({ "<c-/>", "<c-_>", "<leader>ft", "<leader>fT" }) do
  assert(type(vim.fn.maparg(key, "n", false, true).callback) == "function", key)
end
assert(vim.fn.exists(":GlowTerminalShell") == 2)
local spec = dofile(vim.env.GLOW_TEST_CONFIG .. "/lua/plugins/tools/toggleterm.lua")
spec[1].config()
for _, mode in ipairs({ "n", "i", "t" }) do assert(type(vim.fn.maparg("<c-t>", mode, false, true).callback) == "function") end
assert(vim.deep_equal(globals, { vim.o.shell, vim.o.shellcmdflag, vim.o.shellquote, vim.o.shellxquote, vim.o.shellredir, vim.o.shellpipe }), "command job options changed")
vim.fn.has, vim.fn.exepath, vim.fn.executable = real_has, real_exepath, real_executable
print("PASS terminal shell selection, cancellation, persistence, missing shell, toggles, argv, mappings and command options")
vim.cmd("qa!")
