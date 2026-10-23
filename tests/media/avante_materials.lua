-- Isolated real Avante-owned split/float windows; no AI provider or GUI.
local config = assert(vim.env.GLOW_TEST_CONFIG or arg[1])
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
vim.g.neovide, vim.g.neovide_normal_opacity = true, .78
local profiles = require("config.appearance.popup_materials")
assert(profiles.config.avante.mode == "editor", "Avante default must inherit editor")
local helper = require("config.appearance.popups")
local main = vim.api.nvim_get_current_win()
vim.wo[main].winhighlight = "WinSeparator:AvanteSidebarWinSeparator"
vim.cmd("leftabove vnew")
local tree = vim.api.nvim_get_current_win()
vim.bo.filetype = "neo-tree"
vim.wo.winhighlight = "Normal:NeoTreeNormal,WinSeparator:NeoTreeWinSeparator"
vim.api.nvim_set_current_win(main)
local owned = {}
for _, ft in ipairs({ "Avante", "AvanteSelectedCode", "AvanteInput" }) do
  vim.cmd(#owned == 0 and "rightbelow vnew" or "rightbelow new")
  local win = vim.api.nvim_get_current_win()
  vim.bo.filetype = ft
  vim.wo.winhighlight = "Normal:AvanteSidebarNormal,WinSeparator:AvanteSidebarWinSeparator,CursorLine:Normal"
  vim.wo.winbar = "%#AvanteSidebarWinHorizontalSeparator# Gap %#AvanteReversedTitle#%#AvanteTitle# Title %#AvanteReversedTitle#"
  owned[#owned + 1] = win
end
vim.cmd("rightbelow new")
local explicit = vim.api.nvim_get_current_win()
vim.w[explicit].glow_popup_profile = "avante"
owned[#owned + 1] = explicit
vim.cmd("rightbelow new")
local mapped = vim.api.nvim_get_current_win()
vim.wo[mapped].winhighlight = "Normal:AvanteSidebarNormal"
owned[#owned + 1] = mapped
local buf = vim.api.nvim_create_buf(false, true)
vim.bo[buf].filetype = "AvantePromptInput"
local prompt = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 2, col = 2, width = 20, height = 2, border = "single" })
vim.wo[prompt].winhighlight = "Normal:AvantePromptInput,FloatBorder:AvantePromptInputBorder"
owned[#owned + 1] = prompt
local function attrs(win, name)
  local namespace = vim.api.nvim_get_hl_ns({ winid = win })
  local value = vim.api.nvim_get_hl(namespace, {})[name]
  if not value or not next(value) then return vim.api.nvim_get_hl(0, { name = name, link = false }) end
  return value.link and vim.api.nvim_get_hl(0, { name = value.link, link = false }) or value
end
local original_options = { vim.wo[main].winhighlight, vim.wo[tree].winhighlight }
local cases = {}
for _, theme in ipairs({ "dark", "light" }) do
  vim.o.background = theme
  local normal, popup = theme == "dark" and 0x0b0e14 or 0xfafafa, theme == "dark" and 0x05080e or 0xf0f0f0
  local fg = theme == "dark" and 0xc9c7be or 0x5c6166
  package.loaded.base46 = { get_theme_tb = function(kind) return kind == "base_30" and { darker_black = popup } or {} end }
  vim.api.nvim_set_hl(0, "Normal", { fg = fg, bg = normal })
  vim.api.nvim_set_hl(0, "NormalFloat", { fg = fg, bg = popup })
  vim.api.nvim_set_hl(0, "AvanteSidebarNormal", { link = "NormalFloat" })
  vim.api.nvim_set_hl(0, "AvantePromptInput", {})
  vim.api.nvim_set_hl(0, "AvantePromptInputBorder", { fg = 0x66aacc, bg = popup })
  vim.api.nvim_set_hl(0, "AvantePopupHint", { link = "NormalFloat" })
  vim.api.nvim_set_hl(0, "AvanteTitle", { fg = 0x112233, bg = 0x98c379, bold = true })
  vim.api.nvim_set_hl(0, "Visual", { fg = 0x113355, bg = 0x445566 })
  vim.api.nvim_set_hl(0, "NeoTreeNormal", { fg = fg, bg = popup, blend = 30 })
  for _, name in ipairs({ "AvanteSidebarWinSeparator", "AvanteSidebarWinHorizontalSeparator" }) do
    vim.api.nvim_set_hl(0, name, { fg = popup, bg = popup, blend = 30 })
  end
  for _, name in ipairs({ "AvanteReversedTitle", "AvanteReversedSubtitle", "AvanteReversedThirdTitle" }) do
    vim.api.nvim_set_hl(0, name, { fg = 0x98c379, bg = popup, bold = true })
  end
  local editor_before = vim.api.nvim_get_hl(0, { name = "Normal" })
  local tree_before = vim.api.nvim_get_hl(0, { name = "NeoTreeNormal" })
  for _, case in ipairs({
    { mode = "editor", opacity = .78, blend = 22, bg = normal },
    { mode = "editor", opacity = .85, blend = 15, bg = normal },
    { mode = "editor", opacity = .98, blend = 2, bg = normal },
    { mode = "opaque", opacity = .78, blend = 0, bg = popup },
    { mode = "custom", opacity = .78, blend = 37, bg = 0x223344 },
  }) do
    vim.g.neovide_normal_opacity = case.opacity
    profiles.config.avante = { mode = case.mode, blend = case.blend, bg = case.bg }
    helper.apply()
    for _, win in ipairs(owned) do
      assert(vim.w[win].glow_popup_material.profile == "avante", "exact Avante ownership")
      for _, group in ipairs({ "Normal", "NormalNC", "NormalFloat", "FloatBorder" }) do
        local value = attrs(win, group)
        assert(value.bg == case.bg and value.blend == case.blend, group .. ": " .. vim.inspect(value))
      end
      local cap = attrs(win, "AvanteReversedTitle")
      assert(cap.fg == 0x98c379 and cap.bg == case.bg and cap.blend == case.blend and cap.bold, "cap exterior/accent")
      if vim.wo[win].winhighlight:find("WinSeparator:AvanteSidebarWinSeparator", 1, true) then
        local seam = attrs(win, "WinSeparator")
        assert(seam.bg == case.bg and seam.fg == case.bg and seam.blend == case.blend, "local seam mapping")
      end
      local title = attrs(win, "AvanteTitle")
      assert(title.bg == 0x98c379 and (title.blend or 0) == 0, "solid title body")
      local selected = attrs(win, "Visual")
      assert(selected.bg == 0x445566 and selected.fg == 0x113355 and (selected.blend or 0) == 0, "semantic selection")
    end
    for _, name in ipairs({ "AvanteSidebarWinSeparator", "AvanteSidebarWinHorizontalSeparator" }) do
      local value = vim.api.nvim_get_hl(0, { name = name, link = false })
      assert(value.bg == case.bg and value.fg == case.bg and value.blend == case.blend, "adjacent seam")
    end
    assert(vim.w[main].glow_popup_material == nil and vim.w[tree].glow_popup_material == nil, "ordinary split became popup")
    assert(vim.wo[main].winhighlight == original_options[1] and vim.wo[tree].winhighlight == original_options[2], "split mappings changed")
    assert(vim.deep_equal(editor_before, vim.api.nvim_get_hl(0, { name = "Normal" })), "editor RGB/blend changed")
    assert(vim.deep_equal(tree_before, vim.api.nvim_get_hl(0, { name = "NeoTreeNormal" })), "NeoTree material changed")
    cases[#cases + 1] = { theme = theme, mode = case.mode, blend = case.blend, opacity = case.opacity }
  end
  -- Explicit editor blend takes priority over the opacity fallback.
  vim.api.nvim_set_hl(0, "Normal", { fg = fg, bg = normal, blend = 63 })
  profiles.config.avante = { mode = "editor" }
  helper.apply()
  assert(attrs(owned[1], "Normal").blend == 63, "explicit editor blend was capped")
  local transparency = require("config.appearance.transparency")
  local user_windows = vim.deepcopy(transparency.config.windows)
  transparency.apply_windows()
  assert(attrs(owned[1], "Normal").blend == 63, "transparency window refresh replaced Avante profile")
  assert(vim.deep_equal(user_windows, transparency.config.windows), "Windows user material settings changed")
end
vim.wo[mapped].winhighlight = ""
helper.apply()
assert(vim.w[mapped].glow_popup_material == nil and vim.api.nvim_get_hl_ns({ winid = mapped }) <= 0,
  "reused ordinary split retained Avante namespace")
vim.g.neovide = nil
local before = vim.api.nvim_get_hl(0, { name = "AvanteReversedTitle" })
helper.apply()
assert(vim.deep_equal(before, vim.api.nvim_get_hl(0, { name = "AvanteReversedTitle" })), "terminal changed")
if arg[2] then vim.fn.writefile({ vim.json.encode({ state = "passed", cases = cases, window_count = #owned, gui_pixels = false }) }, arg[2]) end
print("PASS: Avante editor/opaque/custom material, all owned split/float panels, seams/caps, theme refresh and unrelated editor/tree preserved")
