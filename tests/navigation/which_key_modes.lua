-- Loaded by which_key_modes.py in its own embedded Neovim, never a user GUI.
local config = assert(vim.env.GLOW_TEST_CONFIG)
local plugins = vim.fn.expand("~/.local/share/nvim/lazy/")
vim.opt.rtp = { config, plugins .. "which-key.nvim", vim.env.VIMRUNTIME }
vim.g.mapleader, vim.g.glow_ui_language = " ", "en"
vim.o.columns, vim.o.lines, vim.o.swapfile = 230, 80, false
local api, locale = vim.api, require("config.platform.locale")
local stdpath = vim.fn.stdpath
vim.fn.stdpath = function(name) return name == "config" and config or stdpath(name) end
local callback = function() error("renderer checks must not execute actions") end
local flash_descriptions = {}
local specs = { { "<leader>a", group = "Avante", mode = { "n", "x" } },
  { "<leader>r", group = "Renaming", mode = { "n", "x" } },
  { "<leader>rx", callback, desc = "User original text", mode = { "n", "x" } },
  { "<leader>ax", callback, desc = "User original text", mode = { "n", "x" } } }
-- Reuse the actual pinned LazyVim Flash declarations, without loading Flash or
-- invoking any mapped action. Descriptions/modes/keys are the installed source.
for _, plugin in ipairs(dofile(plugins .. "LazyVim/lua/lazyvim/plugins/editor.lua")) do
  if plugin[1] == "folke/flash.nvim" then
    for _, mapping in ipairs(plugin.keys) do
      local clone = vim.deepcopy(mapping)
      flash_descriptions[#flash_descriptions + 1] = mapping.desc
      clone[2] = callback
      specs[#specs + 1] = clone
    end
  end
end
local options = locale.setup_which_key({ delay = 0, triggers = {}, notify = false, show_help = true,
  icons = { mappings = false }, win = { no_overlap = false, border = "single", title = true, row = 2, col = 1,
    width = 220, height = 60 }, layout = { width = { min = 80, max = 110 } },
  plugins = { marks = true, registers = true, spelling = { enabled = false }, presets = {
    operators = true, motions = true, text_objects = true, windows = true, nav = true, z = true, g = true } }, spec = specs })
require("which-key").setup(options)
assert(vim.wait(1000, function() return require("which-key.config").loaded end))
local source_buf = api.nvim_get_current_buf()
api.nvim_buf_set_lines(source_buf, 0, -1, false, { "alpha_beta.foo bar", "", "second line" })
api.nvim_buf_set_name(source_buf, vim.env.GLOW_TEST_STATE .. "/Find Files")
local before = vim.fn.sha256(table.concat(api.nvim_buf_get_lines(source_buf, 0, -1, false), "\n"))
local clipboard = { ["+"] = { { "Start of line" }, "v" }, ["*"] = { { "Prev word" }, "v" } }
vim.g.clipboard = { name = "owned fixture", cache_enabled = 0,
  copy = { ["+"] = function(value, kind) clipboard["+"] = { value, kind } end,
    ["*"] = function(value, kind) clipboard["*"] = { value, kind } end },
  paste = { ["+"] = function() return clipboard["+"] end, ["*"] = function() return clipboard["*"] end } }
vim.fn.setreg("+", "Start of line", "v")
vim.fn.setreg("*", "Prev word", "v")
vim.fn.setreg("0", "Start of line", "v")
vim.fn.setreg("a", "Remote Flash", "v")
vim.fn.setreg("/", "Find Files", "v")
vim.fn.setpos("'A", { source_buf, 1, 1, 0 })

local function labels(fn)
  for index = 1, 30 do
    local name, value = debug.getupvalue(fn, index)
    if not name then break end
    if name == "labels" then return value end
  end
  error("Pinned provider label table not found")
end
-- Config.add consumes preset spec tables during registration in this version.
-- Read the pinned declaration afresh, rather than auditing its consumed cache.
local presets = dofile(plugins .. "which-key.nvim/lua/which-key/plugins/presets.lua")
local descriptions, unique = {}, {}
for _, name in ipairs({ "operators", "motions", "text_objects", "windows", "nav", "z", "g" }) do
  for _, mapping in ipairs(presets[name]) do
    local text = mapping.desc or mapping.group
    if text and not unique[text] then descriptions[#descriptions + 1], unique[text] = text, true end
  end
end
for _, provider in ipairs({ "registers", "marks" }) do
  for _, text in pairs(labels(require("which-key.plugins." .. provider).expand)) do
    if not unique[text] then descriptions[#descriptions + 1], unique[text] = text, true end
  end
end
vim.list_extend(descriptions, flash_descriptions)
for _, text in ipairs(descriptions) do assert(locale.known(text), "untranslated pinned motion/operator/provider label: " .. text) end

_G.GlowModes = {}
function GlowModes.render(mode, prefix, language)
  local actual = api.nvim_get_mode().mode
  assert(mode ~= "o" or actual:find("o"), "not actually waiting for an operator motion: " .. actual)
  assert(mode ~= "x" or actual == "v", "not actually in Visual mode: " .. actual)
  locale.set_lang(language, { save = false, silent = true })
  local registered = require("which-key.buf").get({ mode = mode, buf = source_buf, update = true })
  local node = prefix == "" and registered.tree.root or registered.tree:find(prefix, { expand = true })
  assert(node, "actual menu subtree absent: " .. prefix)
  require("which-key.state").state = { mode = registered, node = node, filter = { mode = mode, keys = prefix },
    show = true, started = vim.uv.hrtime() / 1e6 }
  local view = require("which-key.view")
  view.show()
  if vim.env.GLOW_TEST_WHICH_HOT then
    local receipt = dofile(vim.env.GLOW_TEST_WHICH_HOT)
    assert(receipt.pending_prefix_preserved and receipt.applied)
  end
  local rows = {}
  for _, child in ipairs(node:children()) do
    local item = view.item(child)
    rows[#rows + 1] = { keys = child.keys, original = child.desc or "", desc = item.desc,
      value = item.value, original_value = child.value }
    if child.desc and child.desc ~= "" and child.parent.plugin ~= "marks" then
      assert(locale.known(child.desc) or child.desc == "User original text", "actual menu label missed: " .. child.desc)
    end
  end
  table.sort(rows, function(a, b) return a.keys < b.keys end)
  assert(vim.fn.sha256(table.concat(api.nvim_buf_get_lines(source_buf, 0, -1, false), "\n")) == before, "rendering changed user text")
  local title = ""
  for _, chunk in ipairs(api.nvim_win_get_config(view.view.win).title or {}) do title = title .. chunk[1] end
  return { actual_mode = actual, prefix = prefix, language = language, rows = rows, title = title,
    rendered = table.concat(api.nvim_buf_get_lines(view.view.buf, 0, -1, false), "\n"),
    footer = table.concat(api.nvim_buf_get_lines(view.footer.buf, 0, -1, false), "\n") }
end
function GlowModes.audit()
  locale.set_lang("zh", { save = false, silent = true })
  for _, text in ipairs(descriptions) do assert(locale.t(text) ~= text, "Chinese phrase unchanged: " .. text) end
  assert(locale.t("Prev word") ~= locale.t("Prev WORD"), "word and WORD semantics collapsed")
  assert(locale.t("Move before prev char") == "向左移到指定字符之后")
  assert(locale.t("Avante") == "Avante AI功能")
  assert(locale.t("Renaming") == "重命名功能")
  return { phrases = #descriptions, word = locale.t("Prev word"), WORD = locale.t("Prev WORD"), avante = locale.t("Avante") }
end
