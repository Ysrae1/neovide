-- Isolated adapter contract: upstream shellescape() paths become literal argv.
-- Uses the existing pinned jupytext.nvim, never invokes a CLI or kernel.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or (root .. "/portable/payload/nvim"))
vim.opt.rtp:append(vim.env.GLOW_TEST_JUPYTEXT or vim.fn.expand("~/.local/share/nvim/lazy/jupytext.nvim"))
local runtime = require("config.media.runtime")
local captured
runtime.convert = function(args) captured = args; return "captured without execution" end
runtime.configure_jupytext()
local command = require("jupytext.commands").run_jupytext_command
local has = vim.fn.has
local notebook = "C:\\Notebook QA\\本地 Notebook's 文件\\result.ipynb"
local output = "C:\\Notebook cache\\用户's source.py"
vim.fn.has = function(feature) if feature == "win32" then return 1 end; return has(feature) end
-- Documented Windows default form produced by shellescape(): outer double quotes.
command('"' .. notebook .. '"', { ["--to"] = "py:percent", ["--output"] = '"' .. output .. '"' })
assert(vim.deep_equal(captured, { notebook, "--output", output, "--to", "py:percent" }),
  "Windows native separators, Unicode, spaces and apostrophes must remain literal argv: " .. vim.inspect(captured))
-- shellslash=true uses the POSIX quoting form even on Windows.
local posix_input, posix_output = "/tmp/Notebook's 中文.ipynb", "/tmp/output's source.py"
command(vim.fn.shellescape(posix_input), { ["--to"] = "py:percent", ["--output"] = vim.fn.shellescape(posix_output) })
assert(vim.deep_equal(captured, { posix_input, "--output", posix_output, "--to", "py:percent" }))
vim.fn.has = has
command(vim.fn.shellescape(posix_input), { ["--to"] = "py:percent", ["--output"] = vim.fn.shellescape(posix_output) })
assert(vim.deep_equal(captured, { posix_input, "--output", posix_output, "--to", "py:percent" }),
  "Existing POSIX quoting must stay unchanged")
print("PASS: Jupytext Windows/POSIX shell-escaped paths become exact argv without CLI execution")
vim.cmd("qa!")
