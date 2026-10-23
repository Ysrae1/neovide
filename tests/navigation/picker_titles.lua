-- Real pinned providers/windows; isolated config, own files, no user's GUI.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local plugins = vim.fn.expand("~/.local/share/nvim/lazy/")
for _, plugin in ipairs({ "snacks.nvim", "telescope.nvim", "plenary.nvim" }) do vim.opt.rtp:append(plugins .. plugin) end
vim.g.neovide, vim.g.glow_ui_language = true, "en"
vim.o.columns, vim.o.lines, vim.o.swapfile = 160, 54, false
local api, work = vim.api, vim.fn.tempname()
vim.fn.mkdir(work, "p")
local original_stdpath = vim.fn.stdpath
vim.fn.stdpath = function(name) return name == "state" and work or name == "config" and config or original_stdpath(name) end
local locale = require("config.platform.locale")
local ui = require("config.locale.ui")
require("snacks").setup({ picker = { enabled = true, ui_select = false }, notifier = { enabled = false } })
require("telescope").setup({ defaults = { initial_mode = "normal", dynamic_preview_title = false } })
-- Reproduce the exact legacy wrapper shape held by an already-open GUI.
local legacy = require("snacks.picker.core.picker")
if not legacy._glow_ui_locale then
  local new, update_titles = legacy.new, legacy.update_titles
  legacy._glow_ui_locale = true
  legacy.new = function(opts) return new(opts) end
  legacy.update_titles = function(self, ...) return update_titles(self, ...) end
end
ui.setup(locale)
local materials = require("config.appearance.popups")
local function rgb(value) return tonumber(value:sub(2), 16) end
local function palette(name)
  local theme = require("config.appearance.themes.ayu_" .. name .. "_customed").base_30
  package.loaded.base46 = { get_theme_tb = function() return theme end }
  api.nvim_set_hl(0, "Normal", { bg = rgb(theme.black), fg = rgb(theme.white) })
  api.nvim_set_hl(0, "NormalFloat", { bg = rgb(theme.darker_black), fg = rgb(theme.white) })
  api.nvim_set_hl(0, "FloatBorder", { fg = rgb(theme.grey), bg = rgb(theme.darker_black) })
  api.nvim_set_hl(0, "TelescopePromptTitle", { fg = rgb(theme.black), bg = rgb(theme.red) })
  api.nvim_set_hl(0, "TelescopePreviewTitle", { fg = rgb(theme.black), bg = rgb(theme.green) })
  api.nvim_set_hl(0, "TelescopeResultsTitle", { fg = rgb(theme.white), bg = rgb(theme.darker_black) })
  return theme
end
local function caption(win)
  local conf = api.nvim_win_get_config(win)
  local text = ""
  for _, chunk in ipairs(conf.title or {}) do text = text .. chunk[1] end
  return text, conf
end
local function caption_token(win, background)
  local text, conf = caption(win)
  assert(text ~= "" and conf.title_pos == "center", "missing/non-centered native title")
  local left, body, right = text:match("^(%s*)(.-)(%s*)$")
  assert(vim.fn.strdisplaywidth(left) == vim.fn.strdisplaywidth(right), "asymmetric CJK/icon padding: " .. vim.inspect(text))
  local namespace = api.nvim_get_hl_ns({ winid = win })
  local highlights = api.nvim_get_hl(namespace, {})
  for _, chunk in ipairs(conf.title) do
    local name = type(chunk[2]) == "number" and api.nvim_get_hl_name_by_id(chunk[2]) or chunk[2]
    local value = highlights[name]
    assert(value and value.bg == rgb(background) and (value.blend or 0) == 0,
      "semantic caption RGB/blend lost: " .. vim.inspect({ chunk, value }))
  end
  return body
end
local files = { work .. "/中文 文件.lua", work .. "/Results.lua" }
for index, file in ipairs(files) do vim.fn.writefile({ "return " .. index }, file) end
local core = require("snacks.picker.core.picker")
local picker = core.new({ source = "files", show_delay = 0, focus = "list", format = "file", preview = "file",
  finder = function() return { { text = files[1], file = files[1] }, { text = files[2], file = files[2] } } end,
  layout = { preset = "default" } })
assert(vim.wait(1500, function() return picker.list:count() == 2 and picker.preview.win:valid() end), "actual picker did not show")
local ids = { picker.input.win.win, picker.list.win.win, picker.preview.win.win }
package.loaded["config.locale.ui"] = nil
ui = require("config.locale.ui")
ui.refresh_pickers(locale)
assert(vim.deep_equal(ids, { picker.input.win.win, picker.list.win.win, picker.preview.win.win }), "hot update recreated the active picker")
if vim.env.GLOW_TEST_PICKER_HOT then
  local receipt = dofile(vim.env.GLOW_TEST_PICKER_HOT)
  assert(receipt.applied and receipt.documents_unchanged and receipt.window_views_unchanged)
end
for _, mode in ipairs({ "dark", "light" }) do
  local colors = palette(mode)
  for _, language in ipairs({ "en", "zh", "en" }) do
    locale.set_lang(language, { save = false, silent = true })
    picker.list:move(1, true)
    picker:_show_preview()
    picker:update_titles()
    materials.apply()
    local preview = caption_token(picker.preview.win.win, colors.green)
    assert(preview == "中文 文件.lua" or preview == "Results.lua", "file name missing/translated: " .. preview)
    local input
    for _, win in ipairs({ picker.layout.root, unpack(vim.tbl_values(picker.layout.box_wins)) }) do
      if win.meta._glow_title_role == "Prompt" then input = win end
    end
    assert(input and caption_token(input.win, colors.red):find(language == "zh" and "文件" or "Files", 1, true), "source title wrong")
    -- Provider transient reset must recover the actual preview item filename.
    picker.preview.title = nil
    picker:update_titles()
    assert(caption(picker.preview.win.win):find(preview, 1, true), "preview reset lost current filename")
  end
end
picker:close()

local telescope_pickers = require("telescope.pickers")
local p = telescope_pickers.new({}, { prompt_title = "Find Files", results_title = "Results", preview_title = "Grep Preview",
  finder = require("telescope.finders").new_table({ "one", "two" }),
  sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
  previewer = require("telescope.previewers").new_buffer_previewer({ title = "Grep Preview", define_preview = function(self)
    api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "user text remains English" })
  end }) })
p:find()
assert(vim.wait(1000, function() return p.layout and p.layout.prompt end))
for _, language in ipairs({ "en", "zh", "en" }) do
  locale.set_lang(language, { save = false, silent = true })
  local expected = language == "zh" and { prompt = "查找文件", results = "结果", preview = "文本搜索预览" }
    or { prompt = "Find Files", results = "Results", preview = "Grep Preview" }
  for kind, text in pairs(expected) do
    local border = p.layout[kind].border
    local lines = table.concat(api.nvim_buf_get_lines(border.bufnr, 0, -1, false), "\n")
    assert(lines:find(text, 1, true), "rendered Telescope title not localized: " .. kind .. " " .. lines)
  end
  assert(p.previewer:title({}, false) == expected.preview, "selection refresh reverted static preview title")
  assert(p.previewer:title({ filename = "Find Files" }, true) ~= "查找文件", "dynamic filename translated")
end
require("telescope.actions").close(p.prompt_bufnr)
vim.fn.stdpath = original_stdpath
vim.fn.delete(work, "rf")
print("PASS actual Snacks dynamic file/title cells and semantic red/green capsules in Ayu dark/light; actual Telescope three border titles en-zh-en, dynamic filename protected")
