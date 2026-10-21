-- Real pinned plugin chrome; no user config writes, file operations, kernel or build.
local config = assert(vim.env.GLOW_TEST_CONFIG)
local plugins = vim.env.GLOW_TEST_PLUGIN_ROOT or vim.fn.expand("~/.local/share/nvim/lazy")
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
for _, name in ipairs({ "snacks.nvim", "neo-tree.nvim", "nui.nvim", "plenary.nvim", "ui", "base46" }) do
  vim.opt.rtp:append(plugins .. "/" .. name)
end
local stdpath = vim.fn.stdpath
local work = vim.fn.tempname()
vim.fn.stdpath = function(name)
  return name == "state" and work or name == "config" and (work .. "/config") or stdpath(name)
end
vim.g.mapleader, vim.g.glow_ui_language = " ", "en"
vim.env.LANG, vim.env.LC_ALL = "en_US.UTF-8", "en_US.UTF-8"
vim.o.columns, vim.o.lines = 120, 50
local ok, err = xpcall(function()
  -- Load statusline first to cover the locale initialization re-entry boundary.
  local statusline = require("nvchad.stl.utils")
  local locale = require("config.platform.locale")
  local ui = require("config.platform.locale_ui")
  local snacks = require("snacks")
  snacks.setup({ picker = { enabled = true, ui_select = false }, input = { enabled = false }, notifier = { enabled = false } })
  ui.setup(locale)
  locale.set_lang("zh", { save = false, silent = true })
  assert(statusline.modes.n[1] == "普通模式")
  assert(statusline.file()[2] == "未命名")
  assert(ui.product_buffer_name("neo-tree filesystem [1]") == "NeoTree 文件浏览 [1]")
  assert(ui.product_buffer_name("C:/project/neo-tree filesystem [1]") == "C:/project/neo-tree filesystem [1]")
  local core = require("snacks.picker.core.picker")
  local item = { text = "Find File", file = "C:/Find File/中文.md" }
  local picker = core.new({ source = "files", find = false, items = { item } })
  assert(picker.title == "文件")
  assert(picker.opts.items[1].file == item.file and picker.opts.items[1].text == item.text)
  locale.set_lang("en", { save = false, silent = true })
  assert(picker.title == "Files" and statusline.modes.n[1] == "NORMAL")
  locale.set_lang("zh", { save = false, silent = true })
  assert(picker.title == "文件")
  picker:close()
  local custom = core.new({ source = "files", title = "C:/Find File/中文.md", find = false, items = {} })
  assert(custom.title == "C:/Find File/中文.md")
  custom:close()
  local labels = ui.picker_titles
  local missing = {}
  for source, title in pairs(labels) do if not locale.known(title) then missing[#missing + 1] = source .. ": " .. title end end
  assert(#missing == 0, "untranslated built-in picker titles: " .. vim.inspect(missing))
  local tree = require("config.navigation.neo_tree_locale")
  assert(tree.prompt('Enter new name for "Find File 中文":') == '为“Find File 中文”输入新名称：')
  assert(tree.prompt("Are you sure you want to delete 'Find File'? "):match("Are you"), "only exact known templates are translated")
  assert(tree.prompt("Are you sure you want to delete 'Find File'?") == '确定删除“Find File”？')
  assert(tree.prompt("WARNING: Dir not empty! Are you sure you want to delete 'Find File'?") == '文件夹不为空！确定删除“Find File”？')
  require("neo-tree").setup({ enable_git_status = false, enable_diagnostics = false, filesystem = { use_libuv_file_watcher = false } })
  require("neo-tree").ensure_config()
  tree.setup()
  local help = require("neo-tree.sources.common.help")
  help.show({ winid = vim.api.nvim_get_current_win(), current_position = "left", resolved_mappings = {
    a = { text = "add", handler = function() error("display test must not execute commands") end },
    r = { text = "rename", handler = function() error("display test must not execute commands") end },
  } })
  local help_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert(help_text:find("新建文件或文件夹", 1, true) and help_text:find("重新命名", 1, true))
  assert(help_text:find("按对应快捷键执行操作", 1, true))
  vim.cmd("close!")
  locale.set_lang("en", { save = false, silent = true })
  assert(tree.prompt('Enter new name for "Find File 中文":') == 'Enter new name for "Find File 中文":')
  local notebook = require("config.media.notebook")
  local document = { nbformat = 4, metadata = {}, cells = {{ cell_type = "code", source = "# 原文不翻译\nprint('Find File')", outputs = {{ output_type = "stream", name = "stdout", text = "原样输出" }} }} }
  for _, language in ipairs({ "en", "zh", "en" }) do
    locale.set_lang(language, { save = false, silent = true })
    local html = notebook.render(document, "/tmp/中文 Find File.ipynb")
    assert(html:find('lang="' .. (language == "zh" and "zh-CN" or "en") .. '"', 1, true))
    local encoded = assert(html:match('<script type="application/json" id="notebook%-data">(.-)</script>'))
    assert(vim.deep_equal(vim.json.decode(encoded), document), "language changed notebook source or saved output")
    local words = vim.json.decode(assert(html:match('<script type="application/json" id="notebook%-ui">(.-)</script>')))
    assert(words.png == (language == "zh" and "已保存的 PNG 图表" or "Saved PNG chart"))
    assert(words.count == (language == "zh" and "%d 个单元格 · 已保存的输出" or "%d cells · Saved outputs"))
  end
  print("PASS product UI: real picker/title refresh en-zh-en, user data intact, NeoTree help/prompts, statusline, Notebook HTML and saved output integrity")
end, debug.traceback)
vim.fn.stdpath = stdpath
vim.fn.delete(work, "rf")
if not ok then error(err) end
