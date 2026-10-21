-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE -l tests/navigation/locale.lua
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local original_stdpath, original_lang, original_lc = vim.fn.stdpath, vim.env.LANG, vim.env.LC_ALL
local state = vim.fn.tempname()
vim.fn.stdpath = function(name)
  return name == "state" and state or name == "config" and (state .. "/config") or original_stdpath(name)
end
vim.g.mapleader = " "
vim.env.LANG, vim.env.LC_ALL = "en_US.UTF-8", "en_US.UTF-8"
vim.g.glow_ui_language = nil
local ok, err = xpcall(function()
  local locale = require("config.platform.locale")
  local original = "Find File"
  assert(locale.t(original) == original)
  local action = function() end
  vim.keymap.set("n", "<leader>f", action, { desc = original })
  locale.command("GlowLocaleFixture", action, { desc = "关闭原生预览面板" })
  local updated = 0
  package.loaded["snacks.dashboard"] = { update = function() updated = updated + 1 end }
  locale.set_lang("zh", { silent = true })
  assert(locale.t(original) == "查找文件")
  assert(locale.t("Enable Wrap") == "启用自动换行")
  assert(locale.t("C:/Users/Find File.ipynb") == "C:/Users/Find File.ipynb")
  assert(locale.t("My custom user label") == "My custom user label")
  assert(vim.api.nvim_get_commands({}).GlowLocaleFixture.definition == "关闭原生预览面板")
  local mapping = vim.fn.maparg("<leader>f", "n", false, true)
  assert(mapping.callback == action and mapping.desc == original, "language must not rebind keys or rewrite source descriptions")
  local before = vim.ui.input
  local prompt, default
  vim.ui.input = function(opts, callback) prompt, default = opts.prompt, opts.default; callback(opts.default) end
  local user_value = "中文 USER /path/Config"
  locale.set_lang("en", { silent = true })
  locale.input({ prompt = "GitHub 用户名 / 个人主页：", default = user_value }, function(value) assert(value == user_value) end)
  assert(prompt == "GitHub username / profile URL:" and default == user_value)
  vim.ui.input = before
  assert(locale.t(original) == original and locale.t("关闭原生预览面板") == "Close native preview")
  assert(vim.api.nvim_get_commands({}).GlowLocaleFixture.definition == "Close native preview")
  assert(updated == 2, "an already open Dashboard must refresh immediately")
  locale.set_lang("zh", { silent = true })
  assert(vim.fn.readfile(state .. "/preferences/language.txt")[1] == "zh_CN.UTF-8")
  vim.g.glow_ui_language = "en"
  locale.load_language_settings()
  assert(locale.current() == "zh", "preference must survive reload")
  local notices = {}
  local notify = vim.notify
  vim.notify = function(message) notices[#notices + 1] = message end
  locale.toggle_lang()
  assert(locale.current() == "en" and notices[#notices] == "Language switched to English.")
  vim.notify = notify
  local chosen
  local ui_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    assert(opts.format_item(items[1]) == "Open profile")
    chosen = items[1]
  end
  package.loaded["config.integrations.github"] = nil
  require("config.integrations.github").menu()
  assert(chosen[1] == "打开个人主页", "select must retain original action identity")
  vim.ui.select = ui_select
  print("PASS live locale: en/zh/en, menu values preserved, command metadata, Dashboard refresh, persisted setting, unchanged key actions")
end, debug.traceback)
vim.fn.stdpath = original_stdpath
vim.env.LANG, vim.env.LC_ALL = original_lang, original_lc
vim.fn.delete(state, "rf")
if not ok then error(err) end
