-- Real filetype detection, isolated buffers; no Notebook CLI, host or kernel.
-- GLOW_TEST_CONFIG=~/.config/nvim nvim --headless --noplugin -u NONE -i NONE -l tests/notebook/filetype.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp = { vim.env.GLOW_TEST_CONFIG or (root .. "/portable/payload/nvim"), vim.env.VIMRUNTIME }
vim.o.swapfile, vim.o.hidden = false, true
vim.cmd("filetype on")
local api = vim.api
local runtime = require("config.media.runtime")
local buf = api.nvim_get_current_buf()
api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".ipynb")
local lines = { "# ---", "# jupyter:", "# ---", "", "# %%", "value = 42", "print(value)" }
api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.bo[buf].modified = false
local outputs = api.nvim_create_namespace("molten-extmarks")
api.nvim_buf_set_extmark(buf, outputs, 6, 0, {
  virt_lines = { { { "Out[3]: retained output", "Normal" } } },
})
local marks = api.nvim_buf_get_extmarks(buf, outputs, 0, -1, { details = true })
local tick = api.nvim_buf_get_changedtick(buf)
local reads = 0
api.nvim_create_autocmd("BufReadPost", { buffer = buf, callback = function() reads = reads + 1 end })
local function retained(modified)
  assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), lines), "source must remain unchanged")
  assert(api.nvim_buf_get_changedtick(buf) == tick, "filetype recovery must not edit source")
  assert(vim.bo[buf].modified == modified, "retain the existing unsaved state")
  assert(vim.deep_equal(api.nvim_buf_get_extmarks(buf, outputs, 0, -1, { details = true }), marks),
    "existing output extmarks must remain unchanged")
end
assert(vim.filetype.match({ filename = api.nvim_buf_get_name(buf), buf = buf }) == "json",
  "fixture must exercise real .ipynb to JSON detection")
assert(runtime.complete_notebook_load(buf) and vim.bo[buf].filetype == "python",
  "first completion must finish as Python after built-in BufReadPost detection")
assert(reads == 1 and vim.b[buf].glow_notebook_read_complete, "complete the read lifecycle exactly once")
retained(false)
vim.bo[buf].modified = true
assert(runtime.complete_notebook_load(buf) and vim.bo[buf].filetype == "python" and reads == 1,
  "repeat completion must not replay read handlers")
retained(true)

local notebook = require("config.media.notebook_edit")
notebook.setup()
api.nvim_exec_autocmds("BufReadPost", { buffer = buf, modeline = false })
assert(vim.bo[buf].filetype == "python" and reads == 2,
  "Notebook attachment must recover a later BufReadPost detection")
retained(true)
vim.bo[buf].filetype = "json"
api.nvim_exec_autocmds("BufWinEnter", { buffer = buf, modeline = false })
assert(vim.bo[buf].filetype == "python" and reads == 2,
  "returning to a converted Notebook must repair its filetype without rereading")
retained(true)

local raw = api.nvim_create_buf(true, false)
api.nvim_buf_set_name(raw, vim.fn.tempname() .. ".ipynb")
api.nvim_buf_set_lines(raw, 0, -1, false, { '{"nbformat":4,"cells":[]}' })
vim.bo[raw].filetype = "json"
vim.bo[raw].modified = false
assert(not runtime.complete_notebook_load(raw) and vim.bo[raw].filetype == "json",
  "raw JSON must never be labelled Python")
-- A stale read-complete flag must still pass the percent-source check.
vim.b[raw].glow_notebook_read_complete = true
api.nvim_exec_autocmds("BufWinEnter", { buffer = raw, modeline = false })
assert(vim.bo[raw].filetype == "json" and not vim.bo[raw].modified, "attachment must revalidate raw JSON")

local ordinary = api.nvim_create_buf(true, false)
api.nvim_buf_set_name(ordinary, vim.fn.tempname() .. ".py")
api.nvim_buf_set_lines(ordinary, 0, -1, false, { "# %%", "ordinary = 42" })
vim.bo[ordinary].filetype = "python"
vim.bo[ordinary].modified = false
local ordinary_tick = api.nvim_buf_get_changedtick(ordinary)
api.nvim_exec_autocmds("BufReadPost", { buffer = ordinary, modeline = false })
api.nvim_exec_autocmds("BufWinEnter", { buffer = ordinary, modeline = false })
assert(vim.bo[ordinary].filetype == "python" and not vim.b[ordinary].glow_notebook_edit
  and not vim.b[ordinary].glow_notebook_read_complete and not vim.b[ordinary].glow_notebook_writer,
  "ordinary percent-style Python must not become a Notebook")
assert(api.nvim_buf_get_changedtick(ordinary) == ordinary_tick and not vim.bo[ordinary].modified,
  "ordinary Python source state must remain unchanged")
print("PASS: real filetype detection preserves converted Python on first/repeated load and read/window reentry; raw JSON and ordinary Python stay unchanged")
