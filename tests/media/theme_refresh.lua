-- Real, already-installed Base46/FFF/Noice sources; no installation or user session.
-- GLOW_TEST_CONFIG=/path/to/nvim GLOW_TEST_PLUGIN_ROOT=/path/to/lazy
-- GLOW_TEST_NEOVIDE=1 nvim --headless --noplugin -u NONE -i NONE -l tests/media/theme_refresh.lua
local config = assert(vim.env.GLOW_TEST_CONFIG)
local plugins = assert(vim.env.GLOW_TEST_PLUGIN_ROOT)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
for _, name in ipairs({ "base46", "plenary.nvim", "ui", "fff", "noice.nvim", "lazy.nvim", "mason.nvim", "which-key.nvim" }) do
  assert(vim.fn.isdirectory(plugins .. "/" .. name) == 1, "missing existing test dependency: " .. name)
  vim.opt.rtp:append(plugins .. "/" .. name)
end
vim.g.neovide = vim.env.GLOW_TEST_NEOVIDE == "1" and true or nil
local cache = vim.fn.tempname() .. "/"
vim.fn.mkdir(cache, "p")
vim.g.base46_cache = cache
local options = require("nvconfig")
options.ui.cmp.style = "atom" -- Covers the completion integration's background branch.
local compat = require("config.appearance.base46")
compat.setup()
require("lazy.view.colors").set_hl()
require("mason.ui.colors")
require("which-key.colors").setup()
local bodies = {
  LazyNormal = "NormalFloat", MasonNormal = "NormalFloat", WhichKeyNormal = "NormalFloat",
  NoicePopup = "NormalFloat", NoiceMini = "MsgArea", SnacksInputNormal = "Normal",
  TelescopeResultsNormal = "TelescopeNormal", TelescopePreviewNormal = "TelescopeNormal",
  BlinkCmpMenu = "Pmenu", BlinkCmpDoc = "NormalFloat", BlinkCmpSignatureHelp = "NormalFloat",
}
for name, target in pairs(bodies) do vim.api.nvim_set_hl(0, name, { link = target, default = true }) end
local function rgb(value) return tonumber(value:gsub("^#", ""), 16) end
local function hl(name, namespace)
  local values = vim.api.nvim_get_hl(namespace or 0, {})
  local attrs = values[name]
  if not attrs or next(attrs) == nil then attrs = vim.api.nvim_get_hl(0, { name = name, link = false }) end
  return attrs
end
local function settle()
  vim.wait(80, function() return false end, 10)
end
local function check_sources()
  local b = require("base46")
  local syntax, colors = b.get_theme_tb("base_16"), b.get_theme_tb("base_30")
  local mode = b.get_theme_tb("type")
  local change = require("base46.colors").change_hex_lightness
  assert(vim.o.background == mode, "target mode not applied")
  assert(hl("LazyButton").fg == rgb(syntax.base05), "Lazy button retained old foreground")
  assert(hl("LazyButton").bg == rgb(colors.one_bg), "Lazy button lost its theme background")
  local inlay = rgb(change(colors.black2, mode == "dark" and 0 or 3))
  local kind = rgb(change(colors.black2, mode == "dark" and 6 or -6))
  assert(hl("LspInlayHint").bg == inlay, "LSP integration used the previous background mode")
  assert(hl("CmpItemKindText").bg == kind, "completion integration used the previous background mode")
  for _, item in ipairs({ { "lsp", "LspInlayHint", inlay }, { "cmp", "CmpItemKindText", kind } }) do
    vim.api.nvim_set_hl(0, item[2], { bg = 0x123456 })
    dofile(cache .. item[1])
    assert(hl(item[2]).bg == item[3], item[1] .. " cache retained old mode")
  end
  vim.api.nvim_set_hl(0, "LazyButton", { fg = 0x123456 })
  dofile(cache .. "defaults")
  assert(hl("LazyButton").fg == rgb(syntax.base05) and vim.o.background == mode,
    "defaults cache retained old foreground or lost its background prefix")
  compat.apply() -- Final material follows the repaired cache, including namespaced floats.
end
local popup, body_windows = nil, {}
local notification, preview
local text_groups = {
  "LazyNormal", "LazyComment", "LazyDimmed", "LazyProp", "MasonNormal", "MasonMuted",
  "WhichKeyNormal", "WhichKeySeparator", "WhichKeyValue", "TelescopeNormal", "TelescopeResultsComment",
  "TelescopePromptCounter", "SnacksPickerFile", "SnacksPickerDir", "SnacksPickerDesc", "SnacksPickerTotals",
  "SnacksNotifierInfo", "NoiceMini", "NoiceFormatEvent", "FFFFileInfoValue", "FFFFileInfoLabel",
}
local function window_hl(win, name)
  local namespace = math.max(vim.api.nvim_get_hl_ns({ winid = win }), 0)
  return hl(name, namespace)
end
local function check_popup_text()
  local syntax = require("base46").get_theme_tb("base_16")
  local colors = require("base46").get_theme_tb("base_30")
  for _, name in ipairs(text_groups) do
    assert(hl(name).fg == rgb(syntax.base05), name .. " does not use the active theme's neutral text")
  end
  assert(hl("Comment").fg == rgb(colors.light_grey), "global code comments were recolored")
  if vim.g.neovide and notification then
    for _, name in ipairs({ "Comment", "NonText" }) do
      assert(window_hl(notification, name).fg == rgb(syntax.base05), "notification detail retained old theme: " .. name)
      assert(window_hl(preview, name).fg == hl(name).fg, "picker code preview text was recolored: " .. name)
    end
  end
end
local function check_bodies()
  if not vim.g.neovide then return end
  local foreground = hl("Normal").fg
  local background = require("config.appearance.popups").background()
  for name, win in pairs(body_windows) do
    local value = hl(name)
    local namespace = vim.api.nvim_get_hl_ns({ winid = win })
    local normal = hl("Normal", namespace)
    assert(value.fg == foreground, name .. " retained a previous theme foreground: " .. vim.inspect(value))
    assert(normal.fg == foreground and normal.bg == background and normal.blend == 0,
      name .. " window namespace retained previous theme colors: " .. vim.inspect(normal))
  end
end
local function check_copies()
  local value, score, match = hl("FFFFileInfoValue"), hl("FFFFileInfoTotalScore"), hl("FFFFileInfoMatchType")
  assert(value.fg == hl("Normal").fg and not value.bg, "FFF value text is stale or imports a background")
  assert(score.fg == hl("Number").fg and score.bold, "FFF score text is stale")
  assert(match.fg == hl("Special").fg and match.bold, "FFF match type text is stale")
  assert(hl("NoiceFormatProgressDone").fg == hl("Search").fg
    and hl("NoiceFormatProgressDone").bg == hl("Search").bg, "Noice copied Search color is stale")
  local ns = math.max(vim.api.nvim_get_hl_ns({ winid = popup }), 0)
  assert(hl("LazyButton", ns).fg == hl("LazyButton").fg, "popup namespace retained old button text")
  if vim.g.neovide then
    assert(hl("Normal", ns).bg == require("config.appearance.popups").background()
      and hl("Normal", ns).blend == 0 and vim.wo[popup].winblend == 0, "popup opacity was not restored")
  else
    assert(vim.wo[popup].winblend == 35, "terminal popup policy changed")
  end
end
for index, mode in ipairs({ "light", "dark", "light" }) do
  options.base46.theme = "ayu_" .. mode
  vim.o.background = mode == "light" and "dark" or "light"
  require("base46").load_all_highlights()
  settle()
  check_sources()
  if index == 1 then
    -- Lazy-loaded providers must also refresh after their first setup.
    require("fff.highlights").setup()
    require("noice.config.highlights").setup()
    -- Late providers register otherwise absent groups after the first theme.
    -- Their literal defaults must be replaced by the central neutral mapping.
    for _, name in ipairs(text_groups) do
      if vim.fn.hlexists(name) == 0 then vim.api.nvim_set_hl(0, name, { fg = 0x123456 }) end
    end
    local buffer = vim.api.nvim_create_buf(false, true)
    popup = vim.api.nvim_open_win(buffer, false, {
      relative = "editor", row = 1, col = 1, width = 32, height = 2, style = "minimal",
    })
    vim.wo[popup].winhighlight, vim.wo[popup].winblend = "Normal:NormalFloat", 35
    for name in pairs(bodies) do
      local win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
        relative = "editor", row = 1, col = 1, width = 32, height = 2, style = "minimal",
      })
      vim.wo[win].winhighlight = "Normal:" .. name
      body_windows[name] = win
    end
    local function float(filetype, source)
      local buffer = vim.api.nvim_create_buf(false, true)
      vim.bo[buffer].filetype = filetype
      local win = vim.api.nvim_open_win(buffer, false, {
        relative = "editor", row = 1, col = 1, width = 32, height = 2, style = "minimal",
      })
      vim.wo[win].winhighlight = "Normal:" .. source
      return win
    end
    -- Identical mappings must not share notification-only text overrides.
    notification = float("snacks_notif", "NormalFloat")
    preview = float("snacks_picker_preview", "NormalFloat")
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", modeline = false })
    settle()
  end
  check_copies()
  check_bodies()
  check_popup_text()
  package.loaded["config.appearance.base46"], package.loaded["config.appearance.fff"] = nil, nil
  compat = require("config.appearance.base46")
  compat.setup()
  -- A compatibility-module reload may start with old live groups/cache without
  -- NvThemeReload. Its public apply/ColorScheme/LazyLoad path repairs that too.
  vim.api.nvim_set_hl(0, "LazyButton", { fg = 0x123456 })
  require("base46").str_to_cache("defaults", "vim.api.nvim_set_hl(0,'LazyButton',{fg=0x123456})")
  compat.apply()
  check_sources()
  check_copies()
  check_bodies()
  check_popup_text()
  if vim.g.neovide and index == 3 then
    -- Reproduce a pre-fix Dark session: the old material helper resolved each
    -- default link into a concrete Dark fg. Reloading new code must repair that
    -- already-broken state, without needing the provider to re-register links.
    for name in pairs(bodies) do
      vim.api.nvim_set_hl(0, name, { fg = 0xC9C7BE, bg = 0x05080E, blend = 0 })
    end
    package.loaded["config.appearance.transparency"] = nil
    require("config.appearance.transparency").apply()
    check_bodies()
    -- The central per-group override wins over its shared body role.
    require("config.appearance.popup_text").overrides.LazyNormal = "#345678"
    require("config.appearance.transparency").apply()
    assert(hl("LazyNormal").fg == 0x345678, "explicit popup foreground override lost")
    require("config.appearance.popup_text").overrides.LazyNormal = nil
    require("config.appearance.transparency").apply()
    check_bodies()
  end
end

-- All three public knobs accept literal colors without importing a background
-- or replacing the existing font style. Full material refresh must retain the
-- configured text, including notification-local detail overrides.
local text = require("config.appearance.popup_text")
local saved = vim.deepcopy(text.config)
local global_comment, global_nontext = hl("Comment"), hl("NonText")
local probes = {
  { "path_prefix", "SnacksPickerDir", "#345678" },
  { "secondary", "LazyComment", "#456789" },
  { "notification_body", "SnacksNotifierInfo", "#56789A" },
}
for _, item in ipairs(probes) do
  local before = hl(item[2])
  before.bg, before.bold, before.italic = before.bg or 0x234567, true, true
  vim.api.nvim_set_hl(0, item[2], before)
  text.config[item[1]] = item[3]
  text.apply()
  local actual = hl(item[2])
  assert(actual.fg == rgb(item[3]) and actual.bg == before.bg and actual.bold and actual.italic,
    item[1] .. " changes text styling/background: " .. vim.inspect(actual))
end
text.config.notification_detail = "#6789AB"
local title = hl("SnacksNotifierTitleInfo")
require("config.appearance.transparency").apply()
for _, item in ipairs(probes) do assert(hl(item[2]).fg == rgb(item[3]), item[1] .. " lost on material refresh") end
assert(vim.deep_equal(hl("Comment"), global_comment) and vim.deep_equal(hl("NonText"), global_nontext),
  "notification detail changed global code highlights")
assert(vim.deep_equal(hl("SnacksNotifierTitleInfo"), title), "default notification title lost semantic styling")
if vim.g.neovide then
  for _, name in ipairs({ "Comment", "NonText" }) do
    assert(window_hl(notification, name).fg == 0x6789AB, "custom notification detail not applied to actual window")
    assert(window_hl(preview, name).fg == hl(name).fg, "custom notification detail leaked into code preview")
  end
end
-- A late-loading plugin can write its literal color after a theme event.
for _, name in ipairs(text_groups) do vim.api.nvim_set_hl(0, name, { fg = 0x102030 }) end
text.config = saved
compat.apply()
check_popup_text()
vim.api.nvim_win_close(popup, true)
for _, win in pairs(body_windows) do vim.api.nvim_win_close(win, true) end
vim.api.nvim_win_close(notification, true)
vim.api.nvim_win_close(preview, true)
vim.fn.delete(cache, "rf")
print("PASS: Light/Dark/Light branches/caches, lazy providers, Noice/FFF copies, popup text knobs/styles, notification-only details and late-load recovery")
