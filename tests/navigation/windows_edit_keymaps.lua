-- Isolated real key dispatch with an in-memory OS clipboard, never the user's.
-- GLOW_TEST_CONFIG=/path/to/config nvim --headless --noplugin -u NONE -i NONE -n -l tests/navigation/windows_edit_keymaps.lua
vim.opt.rtp = { assert(vim.env.GLOW_TEST_CONFIG), vim.env.VIMRUNTIME }
local api = vim.api
local module = require("config.platform.windows_edit_keymaps")
local original_has = vim.fn.has
vim.g.neovide = true
assert(not module.setup(), "Mac must not receive Windows keymaps")
assert(vim.tbl_isempty(vim.fn.maparg("<C-v>", "n", false, true)))
local mac_opts = { normal_keys = { original = true } }
assert(module.configure_multicursors(mac_opts) == mac_opts and mac_opts.normal_keys["<A-LeftMouse>"] == nil)
vim.fn.has = function(name) return name == "win32" and 1 or name == "macunix" and 0 or original_has(name) end
vim.o.hidden, vim.o.swapfile, vim.o.clipboard = true, false, "unnamedplus"
vim.g.glow_ui_language = "en"
local clipboard = { ["+"] = { { "" }, "v" }, ["*"] = { { "" }, "v" } }
local function copy(reg)
  return function(lines, regtype) clipboard[reg] = { vim.deepcopy(lines), regtype } end
end
local function paste(reg) return function() return vim.deepcopy(clipboard[reg]) end end
vim.g.clipboard = { name = "owned test clipboard", copy = { ["+"] = copy("+"), ["*"] = copy("*") },
  paste = { ["+"] = paste("+"), ["*"] = paste("*") }, cache_enabled = 0 }

local sentinel = function() error("reserved shortcut must not be dispatched by this test") end
for _, key in ipairs({ "<C-t>", "<C-/>", "<C-k>", "<C-=>", "<C-0>" }) do
  vim.keymap.set("n", key, sentinel, { desc = "existing reserved key" })
end
vim.keymap.set("t", "<C-c>", "<C-c>", { desc = "existing interrupt" })
assert(module.setup())
for _, key in ipairs({ "<C-t>", "<C-/>", "<C-k>", "<C-=>", "<C-0>" }) do
  assert(vim.fn.maparg(key, "n", false, true).callback == sentinel, "reserved key overwritten: " .. key)
end
assert(vim.fn.maparg("<C-c>", "t", false, true).desc == "existing interrupt")
assert(vim.tbl_isempty(vim.fn.maparg("<C-z>", "t", false, true)))

local function keys(value)
  api.nvim_feedkeys(api.nvim_replace_termcodes(value, true, false, true), "xt", false)
end
local function lines() return api.nvim_buf_get_lines(0, 0, -1, false) end
local function fixture(content)
  keys("<Esc>")
  api.nvim_set_current_buf(api.nvim_create_buf(true, false))
  api.nvim_buf_set_lines(0, 0, -1, false, content)
  api.nvim_win_set_cursor(0, { 1, 0 })
end
local function expect(content, why)
  assert(vim.deep_equal(lines(), content), why .. ": " .. vim.inspect(lines()))
end

fixture({ "alpha beta", "second" })
keys("viw<C-c>")
assert(vim.fn.getreg("+") == "alpha", "Visual copy must write + register")
expect({ "alpha beta", "second" }, "copy changed source")
keys("0viw<C-x>")
assert(vim.fn.getreg("+") == "alpha", "Visual cut must write + register")
expect({ " beta", "second" }, "Visual cut")

fixture({ "alpha beta" })
keys("viw<C-g><C-c>")
assert(vim.fn.getreg("+") == "alpha", "Select copy must write + register")
expect({ "alpha beta" }, "Select copy changed source")
keys("0viw<C-g><C-x>")
expect({ " beta" }, "Select cut")
assert(vim.fn.getreg("+") == "alpha")

fixture({ "old value" })
vim.fn.setreg("+", "你好\r\nβ", "v")
keys("viw<C-v>")
expect({ "你好", "β value" }, "Visual paste, UTF8 and CRLF")
assert(vim.fn.getreg("+") == "你好\r\nβ", "replacing selection changed OS clipboard")
assert(vim.o.clipboard == "unnamedplus")
fixture({ "old value" })
vim.fn.setreg("+", "new", "v")
keys("viw<C-g><C-v>")
expect({ "new value" }, "Select paste")
fixture({ "ab" })
vim.fn.setreg("+", "中文\r\nβ", "v")
vim.bo.formatoptions = "cro"
keys("i<C-v><Esc>")
expect({ "中文", "βab" }, "Insert paste")
assert(vim.bo.formatoptions == "cro", "paste changed formatoptions")
fixture({ "ab" })
vim.fn.setreg("+", "XY", "v")
keys("<C-v>")
expect({ "aXYb" }, "Normal paste after cursor")
vim.bo.modifiable = false
local paste_ok = pcall(module.paste)
assert(not paste_ok and vim.o.clipboard == "unnamedplus" and vim.bo.formatoptions == "tcqj",
  "paste failure must restore options")
vim.bo.modifiable = true

fixture({ "keep rest" })
vim.fn.setreg("+", "clipboard survives", "v")
keys("viw<BS>")
expect({ " rest" }, "delete selection")
assert(vim.fn.getreg("+") == "clipboard survives", "selection delete replaced clipboard")
keys("viw<C-z>")
expect({ "keep rest" }, "Visual undo must undo, not lowercase")
keys("<C-S-z>")
expect({ " rest" }, "redo")

fixture({ "one", "two" })
keys("<C-a><C-c>")
assert(vim.fn.getreg("+") == "one\ntwo\n", "Normal select all/copy")
keys("i<C-a><C-x>")
expect({ "" }, "Insert select all/cut")
assert(vim.fn.getreg("+") == "one\ntwo\n")

fixture({ "abc" })
keys("<End>")
assert(api.nvim_win_get_cursor(0)[2] == 2, "native End must reach line end")
keys("<Home>")
assert(api.nvim_win_get_cursor(0)[2] == 0, "native Home must reach line start")
keys("i<End>X<Home>Y<Esc>")
expect({ "YabcX" }, "native Insert Home/End")

fixture({ "abc" })
vim.fn.setreg("+", "quoted\nignored", "v")
local commandline
_G.glow_capture_edit_cmdline = function() commandline = vim.fn.getcmdline() end
vim.keymap.set("c", "<F4>", function() _G.glow_capture_edit_cmdline() end)
keys(":<C-v><F4><C-u><Esc>")
assert(commandline == "quoted", "command-line paste must use first line only: " .. tostring(commandline))

local temporary = vim.fn.tempname()
api.nvim_buf_set_name(0, temporary)
keys("<C-s>")
assert(vim.fn.readfile(temporary)[1] == "abc", "Normal save")
keys("A!<C-s><Esc>")
assert(vim.fn.readfile(temporary)[1] == "abc!", "Insert save: " .. vim.inspect({lines(), vim.fn.readfile(temporary), vim.fn.mode(), vim.fn.maparg("<C-s>", "i", false, true)}))
vim.fn.delete(temporary)

-- Callback dispatch and locale changes preserve user overrides and buffer maps.
local calls = 0
package.loaded["Comment.api"] = { toggle = { linewise = setmetatable({ current = function() calls = calls + 1 end },
  { __call = function() calls = calls + 1 end }) } }
keys("<C-S-c>i<C-S-c><Esc>viw<C-S-c>")
assert(calls == 3, "comment bindings")
local completion = function() end
vim.keymap.set("i", "<C-y>", completion, { buffer = true, desc = "completion confirmation" })
vim.g.glow_ui_language = "zh"
api.nvim_exec_autocmds("User", { pattern = "GlowLanguageChanged" })
assert(vim.fn.maparg("<C-c>", "x", false, true).desc == "复制到系统剪贴板")
assert(vim.fn.maparg("<C-s>", "n", false, true).desc == "保存文件")
assert(vim.fn.maparg("<C-y>", "i", false, true).callback == completion)
vim.keymap.set("n", "<C-s>", sentinel, { desc = "user override" })
vim.g.glow_ui_language = "en"
api.nvim_exec_autocmds("User", { pattern = "GlowLanguageChanged" })
assert(vim.fn.maparg("<C-c>", "x", false, true).desc == "Copy to System Clipboard")
assert(vim.fn.maparg("<C-s>", "n", false, true).callback == sentinel, "user override lost on refresh")
assert(vim.fn.maparg("<C-v>", "t", false, true).rhs == nil, "terminal Ctrl+V must remain native")
local term_input = ""
local term = api.nvim_create_buf(false, true)
api.nvim_open_term(term, { on_input = function(_, _, _, input) term_input = term_input .. input end })
api.nvim_set_current_buf(term)
vim.fn.setreg("+", "echo not executed\r\nsecond", "v")
keys("i<C-S-v><C-\\><C-n>")
vim.wait(100, function() return term_input ~= "" end)
assert(term_input:find("echo not executed", 1, true) and term_input:find("second", 1, true),
  "terminal clipboard must be sent as terminal input: " .. vim.inspect(term_input))
assert(not table.concat(api.nvim_buf_get_lines(term, 0, -1, false), "\n"):find("echo not executed", 1, true),
  "terminal paste must not write terminal display lines")
fixture({ "first selection", "second selection" })
for _, name in ipairs({ "multicursors.nvim", "hydra.nvim" }) do
  local path = vim.fn.expand("~/.local/share/nvim/lazy/") .. name
  assert(vim.fn.isdirectory(path) == 1, "real installed plugin missing: " .. name)
  vim.opt.rtp:append(path)
end
local specification = dofile(vim.env.GLOW_TEST_CONFIG .. "/lua/plugins/editor/multicursors.lua")[1]
local opts = specification.opts()
assert(opts.normal_keys["<A-LeftMouse>"] and opts.normal_keys["<D-LeftMouse>"], "Windows and Mac mouse entries must coexist")
require("multicursors").setup(opts)
require("config.editor.multicursor_mouse").setup()
local original_mouse = vim.fn.getmousepos
local mouse_row, mouse_column = 1, 1
vim.fn.getmousepos = function() return { winid = api.nvim_get_current_win(), line = mouse_row, column = mouse_column } end
local function mouse(action)
  local mapping = vim.fn.maparg("<A-Left" .. action .. ">", "n", false, true)
  assert(type(mapping.callback) == "function", "Alt mouse lost in the active Hydra layer: " .. action)
  mapping.callback()
end
mouse("Mouse"); mouse_column = 5; mouse("Drag"); mouse("Release")
assert(vim.fn.maparg("<A-LeftMouse>", "n", false, true).buffer == 1, "active Hydra did not install Alt mouse head")
mouse_row, mouse_column = 2, 1
mouse("Mouse"); mouse_column = 6; mouse("Drag"); mouse("Release")
local main = api.nvim_buf_get_extmarks(0, api.nvim_create_namespace("multicursorsmaincursor"), 0, -1, {})
local others = api.nvim_buf_get_extmarks(0, api.nvim_create_namespace("multicursors"), 0, -1, {})
assert(#main == 1 and #others == 1, "second Alt drag must retain the previous independent selection")
expect({ "first selection", "second selection" }, "mouse selections changed user text")
vim.fn.getmousepos = original_mouse
print("PASS Windows editor keys: real selection copy/cut/paste + register, UTF8/CRLF, Insert/Select/Normal/command line, undo/redo/save, reserved keys and bilingual descriptions")
print("PASS real terminal input-channel paste and two independent Alt-drag selections in the actual Hydra layer")
