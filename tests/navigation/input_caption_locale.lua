-- Real Snacks input, no file rename or user profile writes.
-- GLOW_TEST_CONFIG=/path nvim --headless --noplugin -u NONE -i NONE -n -l this-file
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME,
  (vim.env.GLOW_TEST_PLUGIN_ROOT or vim.fn.expand("~/.local/share/nvim/lazy")) .. "/snacks.nvim" }
local stdpath, work = vim.fn.stdpath, vim.fn.tempname()
vim.fn.stdpath = function(name)
  return name == "state" and work or name == "config" and (work .. "/config") or stdpath(name)
end
vim.o.columns, vim.o.lines = 120, 40
local ok, err = xpcall(function()
  if vim.env.GLOW_TEST_LOCALE_UI_BASE then
    package.loaded["config.locale.ui"] = dofile(vim.env.GLOW_TEST_LOCALE_UI_BASE)
  end
  local locale = require("config.platform.locale")
  require("snacks").setup({ input = { enabled = true }, notifier = { enabled = false } })
  require("config.locale.ui").setup(locale)
  locale.set_lang("en", { save = false, silent = true })
  local input = require("snacks.input").input({ prompt = "Rename File", default = "Find Files 中文.lua" }, function()
    error("language refresh must not confirm or cancel the input")
  end)
  local win, buf = input.win, input.buf
  if vim.env.GLOW_TEST_LOCALE_UI_BASE then
    package.loaded["config.locale.ui"] = nil
    require("config.locale.ui").setup(locale)
    local dispatch = require("snacks.win").win_opts
    require("config.locale.ui").setup(locale)
    assert(require("snacks.win").win_opts == dispatch, "hot setup stacked caption wrappers")
  end
  vim.api.nvim_win_set_cursor(win, { 1, 4 })
  local cursor = vim.api.nvim_win_get_cursor(win)
  for _, lang in ipairs({ "en", "zh", "en", "zh" }) do
    locale.set_lang(lang, { save = false, silent = true })
    -- Text/width updates use the original opts.title too; they must retain
    -- the new language after the language-change event has finished.
    input:update()
    local chunks = vim.api.nvim_win_get_config(win).title
    local title = table.concat(vim.tbl_map(function(chunk) return chunk[1] end, chunks))
    assert(title == " " .. locale.t("Rename File") .. " ", title)
    assert(input.win == win and input.buf == buf and input:valid(), "input was recreated")
    assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "Find Files 中文.lua", "input value changed")
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor), "input cursor moved")
  end
  input:close()
  local custom = require("snacks.input").input({ prompt = "C:/Rename File/中文", default = "Rename File" }, function() end)
  locale.set_lang("en", { save = false, silent = true })
  custom:update()
  local title = table.concat(vim.tbl_map(function(chunk) return chunk[1] end,
    vim.api.nvim_win_get_config(custom.win).title))
  assert(title == " C:/Rename File/中文 ", "custom prompt/path was translated")
  custom:close()
  print("PASS live input captions en/zh/en and later update; same window/value/cursor; user prompts intact")
end, debug.traceback)
vim.fn.stdpath = stdpath
vim.fn.delete(work, "rf")
if not ok then error(err) end
