-- Simulate Windows paths/events in an isolated real Neovim process. All writes
-- target fixtures; registration is modeled without starting a host or kernel.
local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
local script = repo .. "/portable/windows/runtime/WindowsInit.lua"
local work = vim.fn.tempname() .. "-packaged-runtime"
vim.fn.mkdir(work, "p")
local profile = work .. "/profile data"
local root = work .. "/installed with spaces and 'quotes'"
local real_has, real_executable, real_stdpath = vim.fn.has, vim.fn.executable, vim.fn.stdpath
local python = root .. "/runtime/python/python.exe"
vim.fn.has = function(name) return name == "win32" and 1 or real_has(name) end
vim.fn.executable = function(path)
  return (path == python or path == root .. "/bin/jupytext.exe") and 1 or real_executable(path)
end
vim.fn.stdpath = function(kind) return kind == "data" and profile or real_stdpath(kind) end
vim.env.NEOVIDE_GLOW_ROOT, vim.env.GLOW_PYTHON = root, python
vim.env.JUPYTER_PATH = "C:/OtherJupyter"
local runtime = { directory = function() return profile .. "/glow-notebook-venv" end,
  default_kernel = "glow-python", retained = function() return "retained" end }
package.loaded["config.media.runtime"] = runtime
vim.fn.mkdir(profile .. "/lazy/molten-nvim/rplugin/python3/molten", "p")
vim.fn.writefile({ "# fixture plugin" }, profile .. "/lazy/molten-nvim/rplugin/python3/molten/__init__.py")
local kernel = runtime.directory() .. "/share/jupyter/kernels/glow-python/kernel.json"
local manifest = profile .. "/rplugin.vim"
local registrations = 0
vim.api.nvim_create_user_command("UpdateRemotePlugins", function()
  registrations = registrations + 1
  vim.fn.writefile({ 'command! -nargs=* MoltenInit lua _G.glow_runtime_kernel_calls = (_G.glow_runtime_kernel_calls or 0) + 1' }, manifest)
end, {})
vim.g.loaded_remote_plugins = manifest

dofile(script)
assert(runtime.python() == python and runtime.jupytext() == root .. "/bin/jupytext.exe" and runtime.ready())
assert(runtime.retained() == "retained", "remaining Notebook implementation retained")
assert(vim.g.python3_host_prog == python and vim.env.GLOW_LATEX2TEXT == root .. "/bin/latex2text.exe")
local spec = vim.json.decode(table.concat(vim.fn.readfile(kernel), "\n"))
assert(spec.argv[1] == python and spec.argv[4] == "ipykernel_launcher" and spec.argv[6] == "{connection_file}")
assert(vim.env.JUPYTER_PATH == runtime.directory() .. "/share/jupyter;C:/OtherJupyter")
assert(registrations == 0 and not _G.glow_runtime_kernel_calls, "initialization never starts a host/kernel")
vim.api.nvim_exec_autocmds("VimEnter", { group = "GlowWindowsPackagedRuntime" })
assert(vim.wait(1000, function() return registrations == 1 and vim.fn.exists(":MoltenInit") == 2 end))
assert(not _G.glow_runtime_kernel_calls, "registration does not initialize a kernel")

-- Relocating the application rewrites only the managed kernel executable;
-- the already registered plugin lives at the same writable profile path.
root = work .. "/moved installation"
python = root .. "/runtime/python/python.exe"
vim.env.NEOVIDE_GLOW_ROOT, vim.env.GLOW_PYTHON = root, python
vim.g.python3_host_prog = "C:/ExplicitUserPython/python.exe"
dofile(script)
assert(runtime.python() == python and vim.g.python3_host_prog == "C:/ExplicitUserPython/python.exe", "explicit host respected")
spec = vim.json.decode(table.concat(vim.fn.readfile(kernel), "\n"))
assert(spec.argv[1] == python, "kernel path follows relocated application")
vim.api.nvim_exec_autocmds("VimEnter", { group = "GlowWindowsPackagedRuntime" })
vim.wait(10, function() return false end)
assert(registrations == 1 and not _G.glow_runtime_kernel_calls, "existing manifest avoids repeat registration")
assert(vim.env.JUPYTER_PATH == runtime.directory() .. "/share/jupyter;C:/OtherJupyter", "no duplicate kernel search path")
vim.fn.has, vim.fn.executable, vim.fn.stdpath = real_has, real_executable, real_stdpath
vim.fn.delete(work, "rf")
print("Packaged Windows runtime: relocation, kernelspec, host selection and one-time deferred registration passed")
vim.cmd("qa!")
