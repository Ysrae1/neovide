-- Simulate Windows in isolated Neovim; no downloads, system Python or kernels.
local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local script = repo .. "/portable/windows/runtime/WindowsInit.lua"
local root = vim.fn.tempname() .. "-core-runtime"
local profile = root .. "/profile"
local original_has, original_executable, original_stdpath = vim.fn.has, vim.fn.executable, vim.fn.stdpath
vim.fn.has = function(name) return name == "win32" and 1 or original_has(name) end
vim.fn.stdpath = function(kind) return kind == "data" and profile or original_stdpath(kind) end
vim.env.NEOVIDE_GLOW_ROOT = root .. "/app"
vim.env.NEOVIDE_GLOW_DISTRIBUTION = "core"
vim.env.GLOW_PYTHON, vim.env.GLOW_JUPYTEXT = nil, nil
local runtime = { directory = function() return profile .. "/glow-notebook-venv" end, default_kernel = "glow-python" }
package.loaded["config.media.runtime"] = runtime
dofile(script)
assert(not runtime.ready() and runtime.python() == "" and runtime.jupytext() == "")
assert(vim.fn.exists(":GlowDependencies") == 2, "explicit setup remains available")
assert(vim.fn.isdirectory(profile) == 0, "missing optional Python must not create kernel/profile directories")
local ok, message = pcall(runtime.convert)
assert(not ok and tostring(message):find("GlowDependencies", 1, true), "Notebook reports actionable missing dependencies")

local python, jupytext = root .. "/existing user env/python.exe", root .. "/existing user env/Scripts/jupytext.exe"
vim.env.NEOVIDE_GLOW_ROOT = root .. "/second app"
vim.env.GLOW_PYTHON, vim.env.GLOW_JUPYTEXT = python, jupytext
vim.env.GLOW_LATEX2TEXT = root .. "/existing user env/Scripts/latex2text.exe"
vim.env.JUPYTER_DATA_DIR, vim.env.JUPYTER_RUNTIME_DIR = nil, nil
vim.env.JUPYTER_PATH = nil
vim.g.python3_host_prog = "C:/UserSelected/python.exe"
vim.fn.executable = function(path) return (path == python or path == jupytext) and 1 or original_executable(path) end
dofile(script)
assert(runtime.ready() and runtime.python() == python and runtime.jupytext() == jupytext)
assert(vim.g.python3_host_prog == "C:/UserSelected/python.exe", "explicit host remains authoritative")
assert(vim.env.GLOW_LATEX2TEXT:find("existing user env", 1, true), "core retains selected converter")
local kernel = runtime.directory() .. "/share/jupyter/kernels/glow-python/kernel.json"
local specification = vim.json.decode(table.concat(vim.fn.readfile(kernel), "\n"))
assert(specification.argv[1] == python, "kernel references reused system environment")
assert(vim.fn.filereadable(profile .. "/rplugin.vim") == 0, "test never starts a host or kernel")
vim.fn.has, vim.fn.executable, vim.fn.stdpath = original_has, original_executable, original_stdpath
vim.fn.delete(root, "rf")
print("PASS core runtime: optional dependencies, explicit setup, reused Python and isolated kernel metadata")
vim.cmd("qa!")
