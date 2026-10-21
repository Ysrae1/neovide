-- One real grep picker; exercise dynamic live/flag title chunks, not other UIs.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.fn.expand("~/.local/share/nvim/lazy/snacks.nvim"), vim.env.VIMRUNTIME }
vim.g.neovide, vim.g.glow_ui_language = true, "zh"
vim.o.columns, vim.o.lines = 170, 56
local api, work, stdpath = vim.api, vim.fn.tempname(), vim.fn.stdpath
vim.fn.mkdir(work, "p")
vim.fn.stdpath = function(name) return name == "state" and work or stdpath(name) end
local locale = require("config.platform.locale")
local ui = require("config.platform.locale_ui")
require("snacks").setup({ picker = { enabled = true, ui_select = false }, notifier = { enabled = false } })
ui.setup(locale)
local file = work .. "/中文  文件.txt"
vim.fn.writefile({ "matched 中文" }, file)
local picker = require("snacks.picker.core.picker").new({ source = "grep", cwd = work, show_delay = 0, focus = "list",
  finder = function() return { { file = file, text = "matched 中文", line = "matched 中文", pos = { 1, 0 } } } end,
  layout = { preset = "telescope" }, preview = "file",
  toggles = { cwd = { icon = "󰉋 ", value = work } } })
assert(vim.wait(1000, function() return picker.list:count() == 1 and picker.preview.win:valid() end))
locale.set_lang("zh", { save = false, silent = true })
local windows, seen = {}, {}
for _, collection in ipairs({ { picker.layout.root }, picker.layout.wins, picker.layout.box_wins }) do
  for _, win in pairs(collection) do if not seen[win] then windows[#windows + 1], seen[win] = win, true end end
end
local combinations = {
  { live = false, hidden = false, ignored = false, follow = false, modified = false, regex = true },
  { live = true, hidden = false, ignored = false, follow = false, modified = false, regex = true },
  { live = true, hidden = true, ignored = true, follow = true, modified = true, regex = false },
  { live = false, hidden = false, ignored = false, follow = false, modified = false, regex = true },
}
local output = {}
for _, language in ipairs({ "en", "zh", "en" }) do
locale.set_lang(language, { save = false, silent = true })
for _, flags in ipairs(combinations) do
  for name, value in pairs(flags) do picker.opts[name] = value end
  picker:_show_preview()
  picker:update_titles()
  local sample, roles = {}, {}
  for _, win in ipairs(windows) do
    local role = win.meta._glow_title_role
    if role and win:valid() then
    local native, text = api.nvim_win_get_config(win.win), ""
      for _, chunk in ipairs(native.title or {}) do text = text .. chunk[1] end
      local left, body, right = text:match("^(%s*)(.-)(%s*)$")
      assert(native.title_pos == "center", role .. " not centered")
      assert(vim.fn.strdisplaywidth(left) == 1 and vim.fn.strdisplaywidth(right) == 1,
        role .. " padding is asymmetric or exceeds one cell: " .. vim.inspect(text))
      if role == "Prompt" then
        assert(body:find(locale.t("Grep"), 1, true), "grep Chinese title absent")
        assert(not body:find("  ", 1, true), "flag chunk boundaries contain duplicate spaces: " .. body)
        assert(not not body:find(vim.trim(picker.opts.icons.ui.live), 1, true) == flags.live, "live icon did not update")
        assert(body:find("󰉋", 1, true), "cwd flag lost")
        assert(not not body:find(" h ", 1, true) == flags.hidden or body:sub(-1) == "h" and flags.hidden,
          "hidden flag did not update")
      elseif role == "Preview" then
        assert(body == "中文  文件.txt", "normalization changed whitespace inside a user filename: " .. body)
      elseif role == "Results" then
        assert(body == locale.t("Results"), "result caption wrong")
      end
      roles[role], sample[role] = true, text
    end
  end
  assert(roles.Prompt and roles.Preview and roles.Results, "not all actual picker title roles were checked")
  sample.language = language
  output[#output + 1] = sample
end
end
-- Inspect every pinned layout template: all source/live/flags, preview and
-- results captions feed the same normalized provider title boundary.
local layouts = dofile(vim.fn.expand("~/.local/share/nvim/lazy/snacks.nvim/lua/snacks/picker/config/layouts.lua"))
local count = 0
local function visit(value)
  if type(value) ~= "table" then return end
  if value.title then
    assert(value.title:find("{title}", 1, true) or value.title:find("{preview", 1, true) or vim.trim(value.title) == "Results",
      "unhandled pinned title kind: " .. value.title)
    count = count + 1
  end
  for _, child in pairs(value) do if type(child) == "table" then visit(child) end end
end
visit(layouts)
picker:close()
vim.fn.stdpath = stdpath
vim.fn.delete(work, "rf")
print("PASS one actual grep picker en/zh/en: source/results/filename titles centered; live+cwd+all flags added/removed, exactly one outer cell, no duplicate chunk spaces; filename internal spaces preserved; pinned title templates=" .. count)
print("GREP_TITLE_CHUNKS=" .. vim.json.encode(output))
