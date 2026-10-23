-- Private Windows provider defaults; no Python host, kernel or user config.
vim.opt.rtp:prepend(assert(vim.env.GLOW_TEST_CONFIG))
local root = vim.fn.tempname() .. '-notebook-windows-host'
local has, executable, stdpath = vim.fn.has, vim.fn.executable, vim.fn.stdpath
vim.fn.has = function(name) return name == 'win32' and 1 or has(name) end
vim.fn.stdpath = function(kind) return kind == 'data' and root or stdpath(kind) end
local runtime = require('config.media.runtime')
vim.fn.executable = function(path) return path == runtime.python() and 1 or executable(path) end
local old_data, old_runtime, old_host = vim.env.JUPYTER_DATA_DIR, vim.env.JUPYTER_RUNTIME_DIR, vim.g.python3_host_prog
vim.env.JUPYTER_DATA_DIR, vim.env.JUPYTER_RUNTIME_DIR, vim.g.python3_host_prog = nil, nil, nil
runtime.prepare_host()
assert(vim.g.python3_host_prog == runtime.python())
assert(vim.env.JUPYTER_DATA_DIR == runtime.directory() .. '/share/jupyter')
assert(vim.fn.isdirectory(vim.env.JUPYTER_DATA_DIR .. '/runtime') == 1)
assert(vim.env.JUPYTER_RUNTIME_DIR == vim.env.JUPYTER_DATA_DIR .. '/runtime')
vim.env.JUPYTER_DATA_DIR, vim.env.JUPYTER_RUNTIME_DIR = 'C:/ExplicitData', 'C:/ExplicitRuntime'
runtime.prepare_host()
assert(vim.env.JUPYTER_DATA_DIR == 'C:/ExplicitData' and vim.env.JUPYTER_RUNTIME_DIR == 'C:/ExplicitRuntime')
vim.env.JUPYTER_DATA_DIR, vim.env.JUPYTER_RUNTIME_DIR, vim.g.python3_host_prog = nil, nil, 'C:/UserPython/python.exe'
runtime.prepare_host()
assert(vim.g.python3_host_prog == 'C:/UserPython/python.exe' and not vim.env.JUPYTER_DATA_DIR and not vim.env.JUPYTER_RUNTIME_DIR)
vim.fn.has, vim.fn.executable, vim.fn.stdpath = has, executable, stdpath
vim.env.JUPYTER_DATA_DIR, vim.env.JUPYTER_RUNTIME_DIR, vim.g.python3_host_prog = old_data, old_runtime, old_host
vim.fn.delete(root, 'rf')
print('Windows private Notebook provider and Jupyter directories passed')
vim.cmd('qa!')
