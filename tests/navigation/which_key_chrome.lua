-- Real pinned WhichKey tree + renderer; isolated child, no existing UI/session.
-- GLOW_TEST_CONFIG=/path/to/config nvim --headless --noplugin -u NONE -i NONE -n -l tests/navigation/which_key_chrome.lua
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.fn.expand("~/.local/share/nvim/lazy/which-key.nvim"), vim.env.VIMRUNTIME }
local original_stdpath = vim.fn.stdpath
local state = vim.fn.tempname()
vim.fn.stdpath = function(name)
  return name == "state" and state or name == "config" and (state .. "/config") or original_stdpath(name)
end
vim.g.mapleader, vim.g.glow_ui_language = " ", "en"
local ok, err = xpcall(function()
  local locale = require("config.platform.locale")
  local adapter = require("config.platform.which_key_locale")
  -- Reproduce the already-running previous adapter's own marker wrappers.
  -- setup must migrate just these wrappers once, without nesting them.
  local view, text = require("which-key.view"), require("which-key.text")
  local original, append = view.item, text.append
  view.item = function(...) return original(...) end
  text.append = function(...) return append(...) end
  view._glow_locale_item, text._glow_locale_append = view.item, text.append
  adapter.setup() -- Real integration calls this while resolving WhichKey opts.
  local callback = function() end
  local spec = { { "gz", group = "Chrome fixture" },
    { "gzb1", callback, desc = "Fixture single action" },
    { "gzu", callback, desc = "14 keymaps" }, { "gzv", callback, desc = "close" },
    { "gzw", group = "back" }, { "gzw1", callback, desc = "User text" } }
  for index, key in ipairs(vim.split("abcdefghijklmn", "")) do
    spec[#spec + 1] = { "gza" .. key, callback, desc = "Fixture action " .. index }
  end
  for _, filename in ipairs({ "Config", "Keymaps" }) do
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, filename)
  end
  spec[#spec + 1] = { "gzf", group = "User files", expand = function()
    return require("which-key.extras").expand.buf()
  end }
  require("which-key").setup({ delay = 0, triggers = {}, notify = false,
    show_help = true, show_keys = true, icons = { mappings = false },
    replace = { desc = { function(value) return locale.t(value) end } },
    win = { no_overlap = false, width = 100, height = 8, row = 3, col = 2, border = "none", padding = { 0, 1 } },
    plugins = { marks = false, registers = false, spelling = { enabled = false },
      presets = { operators = false, motions = false, text_objects = false, windows = false, nav = false, z = false, g = false } },
    spec = spec })
  assert(vim.wait(1000, function() return require("which-key.config").loaded end, 10), "real provider setup")
  local wrapped_item, wrapped_show, wrapped_append = view.item, view.show, text.append
  adapter.item = function() error("stale translation module") end
  adapter.append = function() error("stale translation module") end
  package.loaded["config.platform.which_key_locale"] = nil
  require("config.platform.which_key_locale").setup()
  assert(view.item == wrapped_item and view.show == wrapped_show and text.append == wrapped_append,
    "module reload/setup must not stack wrappers")
  local mode = require("which-key.buf").get({ mode = "n", buf = vim.api.nvim_get_current_buf(), update = true })
  local root = assert(mode.tree:find("gz", { expand = true }))
  local function node(keys) return assert(mode.tree:find(keys, { expand = true })) end
  require("which-key.state").state = { mode = mode, node = root, filter = { mode = "n", keys = "gz" },
    show = true, started = vim.uv.hrtime() / 1e6 }
  local output = {}
  for _, language in ipairs({ "en", "zh", "en" }) do
    locale.set_lang(language, { save = false, silent = true })
    if not view.valid() then view.show() end
    local count14, count1 = view.item(node("gza")).desc, view.item(node("gzb")).desc
    local footer = table.concat(vim.api.nvim_buf_get_lines(view.footer.buf, 0, -1, false), "\n")
    local body = table.concat(vim.api.nvim_buf_get_lines(view.view.buf, 0, -1, false), "\n")
    if language == "zh" then
      assert(view.replace("desc", "Config") ~= "Config", "product translator must be active for this protection check")
      assert(count14 == "+14 个快捷键" and count1 == "+1 个快捷键", "automatic counts must localize")
      assert(footer:find("关闭", 1, true) and footer:find("返回", 1, true), "live footer must localize")
      assert(not footer:find("close", 1, true) and not footer:find("back", 1, true), "no English chrome residue")
    else
      assert(count14 == "+14 keymaps" and count1 == "+1 keymap", "English singular/plural must remain exact")
      assert(footer:find("close", 1, true) and footer:find("back", 1, true), "English footer must restore")
    end
    assert(body:find(count14, 1, true) and body:find(count1, 1, true), "actual rendered tree must contain the counts")
    -- `close` is now an explicit product action in locale_ui_messages; it goes
    -- through replace.desc normally, not this adapter's provider-footer hook.
    assert(view.item(node("gzu")).desc == "14 keymaps" and view.item(node("gzv")).desc == locale.t("close")
      and view.item(node("gzw")).desc == "+back", "ordinary labels must follow action translation, not provider chrome rules")
    local filenames = {}
    for _, child in ipairs(node("gzf"):children()) do filenames[view.item(child).desc] = true end
    assert(filenames.Config and filenames.Keymaps, "official dynamic extras must retain user file names")
    local outside = text.new():append(" close", "WhichKeySeparator")
    assert(outside._lines[1][1].str == " close", "segments outside provider show must remain intact")
    output[#output + 1] = { language = language, count14 = count14, count1 = count1, footer = vim.trim(footer) }
  end
  -- Force the renderer's own overflow help and verify scroll is translated,
  -- rather than editing a final buffer after the first draw.
  require("which-key.config").options.win.height = 3
  require("which-key.config").options.layout.width = { min = 100, max = 100 }
  locale.set_lang("zh", { save = false, silent = true })
  view.show()
  local footer = table.concat(vim.api.nvim_buf_get_lines(view.footer.buf, 0, -1, false), "\n")
  assert(footer:find("滚动", 1, true), "overflow help must localize scroll")
  output[#output + 1] = { language = "zh", overflow_footer = vim.trim(footer) }
  view.hide()
  print("REAL_WHICH_KEY_CHROME=" .. vim.json.encode(output))
  print("PASS real WhichKey counts/footer en->zh->en, open-window refresh, user labels, reload, overflow help")
end, debug.traceback)
vim.fn.stdpath = original_stdpath
vim.fn.delete(state, "rf")
if not ok then error(err) end
