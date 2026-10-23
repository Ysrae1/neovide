-- Real native diagnostic store/renderers + pinned Snacks/Trouble; no server or user buffer.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local plugins = vim.env.GLOW_TEST_PLUGIN_ROOT or vim.fn.expand("~/.local/share/nvim/lazy")
for _, name in ipairs({ "snacks.nvim", "trouble.nvim", "nui.nvim", "plenary.nvim" }) do vim.opt.rtp:append(plugins .. "/" .. name) end
vim.o.columns, vim.o.lines = 140, 60
vim.g.glow_ui_language = "en"
local M = require("config.locale.diagnostics")
local catalog = require("config.locale.diagnostic_messages")
local aliases = { lua_ls = "Lua Diagnostics.", go = "gopls", json = "jsonls" }
local count = 0
for source, rows in pairs(catalog) do
  for _, row in ipairs(rows) do
    local function sample(template) return (template:gsub("{([%w_]+)}", function(key) return "x_" .. key .. "_中文%20" end)) end
    local english, chinese = sample(row[1]), sample(row[2])
    local code = type(row[3]) == "table" and row[3][1] or row[3]
    local d = { source = aliases[source] or source, code = code, message = english }
    assert(M.message(d, "zh") == chinese, source .. " fails English: " .. english .. " -> " .. M.message(d, "zh"))
    d.message = chinese
    assert(M.message(d, "en") == english, source .. " fails roundtrip: " .. english .. " -> " .. M.message(d, "en"))
    if row[4] then d.message = sample(row[4]); assert(M.message(d, "en") == english, source .. " upstream alias fails: " .. d.message .. " -> " .. M.message(d, "en")) end
    count = count + 1
  end
end
local cases = {
  { source = "mypy", code = "import-not-found", message = 'Cannot find implementation or library stub for module named "akshare"', expected = '找不到模块“akshare”的实现或类型存根' },
  { source = "mypy", code = "import-untyped", message = 'Library stubs not installed for "pandas"', expected = '尚未安装“pandas”的类型存根' },
  { source = "Pyright", code = "reportMissingImports", message = 'Import "numpy" could not be resolved', expected = '无法解析导入“numpy”' },
  { source = "Ruff", code = "F401", message = '`numpy` imported but unused', expected = '导入 `numpy` 后未使用' },
  { source = "clang", message = "Use of undeclared identifier 'vector'", expected = '标识符“vector”尚未声明' },
  { source = "gopls", message = 'undefined: calculate', expected = '未定义：calculate' },
  { source = "jsonls", message = 'Missing property "version".', expected = '缺少属性“version”。' },
  { source = "Marksman", message = "Link to non-existent heading '开发笔记'", expected = '链接指向不存在的标题“开发笔记”' },
  { source = "Texlab", message = 'Undefined reference', expected = '引用未定义' },
  { source = "neocmakelsp", message = 'File "C:/中文 目录/test.cmake" does not exist or is inaccessible', expected = '文件“C:/中文 目录/test.cmake”不存在或无法访问' },
  { source = "yamllint", code = "key-duplicates", message = 'duplication of key "test" in mapping', expected = '映射中的键“test”重复' },
  { source = "shellcheck", code = 2086, message = 'Double quote to prevent globbing and word splitting.', expected = '请加双引号，防止通配符展开和单词拆分。' },
  { source = "LTeX", message = 'Possible spelling mistake found.', expected = '此处可能存在拼写错误。' },
}
for _, d in ipairs(cases) do assert(M.message(d, "zh") == d.expected, d.source) end
for _, d in ipairs({
  { source = "Ruff", code = "OTHER", message = '`numpy` imported but unused' },
  { source = "user-tool", code = "F401", message = '`numpy` imported but unused' },
  { source = "mypy", message = 'Module notes: Library stubs not installed for "pandas"' },
  { source = "Pyright", message = 'New upstream syntax 2027 C:\\project\\开发.py' },
}) do assert(M.message(d, "zh") == d.message, "unknown must remain original") end
local detail = { source = "pyright", code = "reportAssignmentType", message = 'Type "int" is not assignable to declared type "str"\n  "int" is not assignable to "str"\n  exact user excerpt: foo(中文)' }
assert(M.message(detail, "zh") == '无法将类型“int”的值赋给声明为“str”的变量\n  “int”不能赋给“str”\n  exact user excerpt: foo(中文)')

local snacks = require("snacks")
snacks.setup({ picker = { enabled = true }, input = { enabled = false }, notifier = { enabled = false } })
require("trouble").setup({ auto_open = false })
M.setup()
local first_float = vim.diagnostic.open_float
M.setup()
assert(first_float == vim.diagnostic.open_float, "setup must not stack wrappers")
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = "python"
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. " 中文.py")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "import akshare", "import pandas", "import numpy", "x = 1" })
local ns = vim.api.nvim_create_namespace("glow-localization-fixture")
local diagnostics = {}
for i = 1, 4 do
  local case = cases[i]
  diagnostics[i] = { lnum = i - 1, col = 0, end_lnum = i - 1, end_col = 6, severity = i == 4 and 2 or 1,
    source = case.source, code = case.code, message = case.message,
    user_data = { lsp = { code = case.code, data = { untouched = "Fix import / 用户数据" }, tags = { 1 } } } }
end
diagnostics[1].user_data.lsp.relatedInformation = {{
  message = 'Name "upstream_symbol" is not defined',
  location = { uri = vim.uri_from_bufnr(buf), range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 6 } } },
}}
vim.diagnostic.config({ virtual_text = true, virtual_lines = true, update_in_insert = true, float = { source = true } })
vim.diagnostic.set(ns, buf, diagnostics)
local original = vim.deepcopy(vim.diagnostic.get(buf, { namespace = ns }))
local published = 0
vim.api.nvim_create_autocmd("DiagnosticChanged", { callback = function() published = published + 1 end })
vim.diagnostic.setqflist({ open = false })
local qf = vim.fn.getqflist({ id = 0, items = 0 })
vim.diagnostic.setloclist({ open = false })
local owner_win = vim.api.nvim_get_current_win()
local loc = vim.fn.getloclist(owner_win, { id = 0, items = 0 })
local fbuf, fwin = vim.diagnostic.open_float({ bufnr = buf, scope = "buffer", focus = false })
assert(fbuf and fwin)
local trouble_view = require("trouble").open({ mode = "diagnostics", focus = false, filter = { buf = buf } })
assert(trouble_view)
assert(vim.wait(1000, function() return trouble_view.win.buf and vim.api.nvim_buf_is_valid(trouble_view.win.buf) end, 10))
local raw_codeaction = vim.deepcopy(vim.lsp.diagnostic.from(original))
local item = { item = original[1], file = vim.api.nvim_buf_get_name(buf), pos = { 1, 0 } }
local format = require("snacks.picker.format")
local picker = { opts = require("snacks.picker.config").get({ source = "diagnostics" }) }
-- Native virtual text/lines/float and list rendering all use the same stored diagnostics.
for _, language in ipairs({ "zh", "en", "zh", "en" }) do
  vim.g.glow_ui_language = language
  vim.api.nvim_exec_autocmds("User", { pattern = "GlowLanguageChanged" })
  local expected = language == "zh" and cases[1].expected or cases[1].message
  local lines = table.concat(vim.api.nvim_buf_get_lines(fbuf, 0, -1, false), "\n")
  assert(lines:find(expected, 1, true), "existing float failed refresh: " .. lines)
  assert(lines:find(language == "zh" and '名称“upstream_symbol”未定义' or 'Name "upstream_symbol" is not defined', 1, true), "related information display")
  local float_marks = vim.api.nvim_buf_get_extmarks(fbuf, -1, 0, -1, { details = true })
  local spans = 0
  for _, mark in ipairs(float_marks) do
    local detail = mark[4]
    if detail.hl_group == "DiagnosticFloatingError" then
      assert(detail.end_row == mark[2] and detail.end_col > mark[3], "float diagnostic severity range collapsed")
      spans = spans + 1
    end
  end
  assert(spans >= 3, "severity highlights must survive language refresh")
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
  local rendered = vim.inspect(extmarks)
  assert(rendered:find(language == "zh" and "类型存根" or "library stub", 1, true), "virtual decorations not localized")
  local fmt = format.diagnostic(item, picker)
  assert(fmt[1][1] == expected, "Snacks diagnostic renderer")
  assert(item.item.message == original[1].message)
  local trouble = require("trouble.format").field({ field = "message", item = { source = "diagnostics", item = original[1], message = original[1].message }, opts = {} })
  assert(trouble[1].text == expected, "Trouble diagnostic renderer")
  assert(vim.wait(1000, function()
    return table.concat(vim.api.nvim_buf_get_lines(trouble_view.win.buf, 0, -1, false), "\n"):find(expected, 1, true) ~= nil
  end, 10), "existing Trouble view render cache did not refresh")
  local qtext = M.quickfix_text({ quickfix = 1, id = qf.id, start_idx = 1, end_idx = #qf.items })
  assert(qtext[1]:find(expected, 1, true), "quickfix display")
  local ltext = M.quickfix_text({ quickfix = 0, winid = owner_win, id = loc.id, start_idx = 1, end_idx = #loc.items })
  assert(ltext[1]:find(expected, 1, true), "location list display")
  assert(vim.deep_equal(qf.items, vim.fn.getqflist({ id = qf.id, items = 0 }).items), "quickfix original data changed")
  assert(vim.deep_equal(loc.items, vim.fn.getloclist(owner_win, { id = loc.id, items = 0 }).items), "location original data changed")
  assert(vim.deep_equal(original, vim.diagnostic.get(buf, { namespace = ns })), "diagnostic cache changed")
  assert(vim.deep_equal(raw_codeaction, vim.lsp.diagnostic.from(vim.diagnostic.get(buf, { namespace = ns }))), "code action diagnostics changed")
end
assert(published == 0, "language refresh must not publish synthetic diagnostics")
-- Opening a location list changes focus; registration must retain its owner window.
vim.api.nvim_set_current_win(owner_win)
vim.diagnostic.setloclist({ open = true })
local open_loc = vim.fn.getloclist(owner_win, { id = 0, items = 0 })
vim.g.glow_ui_language = "zh"
M.refresh()
local open_text = M.quickfix_text({ quickfix = 0, winid = owner_win, id = open_loc.id, start_idx = 1, end_idx = #open_loc.items })
assert(open_text[1]:find(cases[1].expected, 1, true), "location list owner after opening")
-- Export from the actual Snacks action bypasses vim.diagnostic.setqflist.
local actual_item = { item = original[1], buf = buf, pos = { 1, 0 }, comment = original[1].message, severity = 1 }
require("snacks.picker.actions").qflist_all({
  opts = { format = "diagnostic" }, main = owner_win,
  close = function() end, items = function() return { actual_item } end,
})
local exported = vim.fn.getqflist({ id = 0, items = 0 })
assert(exported.items[1].text == original[1].message, "Snacks export original changed")
assert(M.quickfix_text({ quickfix = 1, id = exported.id, start_idx = 1, end_idx = 1 })[1]:find(cases[1].expected, 1, true), "Snacks quickfix export display")
local keep = vim.diagnostic.get(buf, { namespace = ns })
vim.diagnostic.config({ virtual_text = { format = function() return nil end } })
M.refresh()
assert(vim.deep_equal(keep, vim.diagnostic.get(buf, { namespace = ns })), "custom formatter changed original data")
print(("PASS diagnostic localization: %d reviewed templates / %d source families; native float + virtual text/lines, real Snacks/Trouble, quickfix/loclist en-zh-en; cache/actions/unknown text intact"):format(count, vim.tbl_count(catalog)))
