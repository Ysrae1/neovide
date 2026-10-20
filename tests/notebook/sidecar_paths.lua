-- Native Windows regression: equivalent real paths share one private sidecar.
-- Run: nvim --headless -u NONE -l tests/notebook/sidecar_paths.lua
assert(vim.fn.has("win32") == 1, "This fixture requires native Windows Neovim")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or (root .. "/portable/payload/nvim"))
local runtime = require("config.media.runtime")
local directory = vim.fn.tempname() .. " 本地 Notebook's 文件"
vim.fn.mkdir(directory, "p")
local first, second = directory .. "/first.ipynb", directory .. "/second.ipynb"
vim.fn.writefile({ "first fixture" }, first)
vim.fn.writefile({ "second fixture" }, second)
local stdpath = vim.fn.stdpath
vim.fn.stdpath = function(kind)
  return kind == "cache" and (directory .. "/cache") or stdpath(kind)
end
local ok, err = pcall(function()
  local forward = vim.fs.normalize(first, { expand_env = false })
  local backward = forward:gsub("/", "\\")
  assert(vim.fn.filereadable(forward) == 1 and vim.fn.filereadable(backward) == 1,
    "Both path spellings must address an existing Windows fixture")
  local a, b = runtime.sidecar(forward, "py"), runtime.sidecar(backward, "py")
  assert(a == b, "Same real file must have one cache key: " .. a .. " ~= " .. b)
  assert(a ~= runtime.sidecar(second, "py"), "Different real files must retain distinct cache keys")
  vim.fn.writefile({ "stale source" }, a)
  assert(vim.fn.delete(runtime.sidecar(backward, "py")) == 0 and vim.fn.filereadable(a) == 0,
    "Invalidation through the opposite path spelling must remove the existing sidecar")
end)
vim.fn.stdpath = stdpath
vim.fn.delete(directory, "rf")
assert(ok, err)
print("PASS: native Windows slash aliases share and invalidate one sidecar; different files stay distinct")
vim.cmd("qa!")
