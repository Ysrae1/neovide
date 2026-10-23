-- Isolated Avante split contract; no provider or native GUI is started.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local real_has = vim.fn.has
local platform = "macos"
vim.fn.has = function(feature)
  if feature == "win32" then return platform == "windows" and 1 or 0 end
  return real_has(feature)
end
vim.g.neovide, vim.g.neovide_normal_opacity = true, .85
vim.api.nvim_set_hl(0, "Normal", { fg = 0xc7c7c7, bg = 0x12151b })
vim.cmd.vsplit()
local left, right = vim.api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr("l"))
local positions = { { left, vim.api.nvim_win_get_position(left)[2] }, { right, vim.api.nvim_win_get_position(right)[2] } }
table.sort(positions, function(a, b) return a[2] < b[2] end)
left, right = positions[1][1], positions[2][1]
local panel_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(right, panel_buf)
vim.bo[panel_buf].filetype = "Avante"
vim.wo[right].winhighlight = "Normal:AvanteSidebarNormal,WinSeparator:AvanteSidebarWinSeparator"
local helper = require("config.appearance.transparency")
local caps = { "AvanteReversedTitle", "AvanteReversedSubtitle", "AvanteReversedThirdTitle" }
local dividers = { "AvanteSidebarWinSeparator", "AvanteSidebarWinHorizontalSeparator" }
local bodies = { "AvanteTitle", "AvanteSubtitle", "AvanteThirdTitle" }
local snapshots = {}
for _, name in ipairs({ "macos", "linux", "windows" }) do
  platform = name
  vim.g.neovide_liquid_glass = name ~= "windows"
  for _, theme in ipairs({ "dark", "light" }) do
    vim.o.background = theme
    local bg = theme == "dark" and 0x24272d or 0xf3f3f3
    local different = theme == "dark" and 0x12151b or 0xfafafa
    vim.api.nvim_set_hl(0, "NormalFloat", { fg = 0x989ba2, bg = different })
    vim.api.nvim_set_hl(0, "AvanteSidebarNormal", { fg = 0x989ba2, bg = bg })
    for _, group in ipairs(dividers) do vim.api.nvim_set_hl(0, group, { fg = 0x404854, bg = different }) end
    for i, group in ipairs(caps) do vim.api.nvim_set_hl(0, group, { fg = 0x90c070 + i, bg = different, bold = true }) end
    for i, group in ipairs(bodies) do vim.api.nvim_set_hl(0, group, { fg = 0x12151b, bg = 0x90c070 + i, bold = true }) end
    local before = {}
    for _, group in ipairs(bodies) do before[group] = vim.api.nvim_get_hl(0, { name = group }) end
    vim.wo[left].winhighlight = "CursorLine:CursorLine"
    helper.apply()
    local function attrs(group) return vim.api.nvim_get_hl(0, { name = group, link = false }) end
    local panel = vim.api.nvim_get_hl(vim.api.nvim_get_hl_ns({ winid = right }), { name = "Normal", link = false })
    local normal = attrs("Normal")
    local policy = require("config.appearance.popup_materials").resolve("avante", normal, different)
    assert(panel.bg == normal.bg and panel.blend == policy.blend, "Avante inherits actual editor policy")
    local row = { platform = name, theme = theme, panel = panel, groups = {}, left_map = vim.wo[left].winhighlight }
    for _, group in ipairs(dividers) do row.groups[group] = attrs(group) end
    for _, group in ipairs(caps) do row.groups[group] = attrs(group) end
    snapshots[#snapshots + 1] = row
    if vim.env.GLOW_AVANTE_MATERIAL_RECEIPT then
      vim.fn.writefile({ vim.json.encode(snapshots) }, vim.env.GLOW_AVANTE_MATERIAL_RECEIPT)
    end
    for _, group in ipairs(dividers) do
      local value = attrs(group)
      assert(value.bg == panel.bg and value.fg == panel.bg and value.blend == panel.blend, name .. ":" .. theme .. ": divider material " .. group)
    end
    for i, group in ipairs(caps) do
      local value = attrs(group)
      assert(value.bg == panel.bg and value.blend == panel.blend, name .. ":" .. theme .. ": cap exterior " .. group)
      assert(value.fg == 0x90c070 + i and value.bold, "cap accent/style retained")
      assert(require("config.appearance.render_roles").groups()[group][1] == "solid_title_cap", "native cap role retained")
    end
    assert(vim.wo[left].winhighlight:find("WinSeparator:AvanteSidebarWinSeparator", 1, true), "adjacent blank gap belongs to Avante")
    for _, group in ipairs(bodies) do assert(vim.deep_equal(before[group], attrs(group)), "solid body remains unchanged") end
    -- Later focus/layout events use the lighter material settlement path.
    helper.apply_windows()
    assert(attrs(caps[1]).bg == panel.bg and attrs(caps[1]).blend == panel.blend, "window refresh keeps cap material")
  end
end
platform = "windows"
vim.g.neovide = nil
local before = vim.api.nvim_get_hl(0, { name = caps[1] })
helper.apply_windows()
assert(vim.deep_equal(before, vim.api.nvim_get_hl(0, { name = caps[1] })), "terminal Neovim untouched")
print("PASS: Windows Avante separators, adjacent gap and cap exterior match sidebar; accents, solid bodies and Mac/Linux contracts retained")
