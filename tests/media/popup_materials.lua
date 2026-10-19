-- Isolated real floating windows; no user session, plugin installation or GUI required.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local module = "config.appearance.popups"
local root = vim.api.nvim_get_current_win()
local root_options = { vim.wo[root].winhighlight, vim.wo[root].winblend }
local function rgb(value) return tonumber(value:sub(2), 16) end
local function hl(namespace, name)
  -- By-name readers can remap UI groups such as FloatBorder; inspect the actual namespace definition.
  return vim.api.nvim_get_hl(namespace, {})[name] or {}
end
local function window_hl(win, name)
  local namespace = math.max(vim.api.nvim_get_hl_ns({ winid = win }), 0)
  local target = vim.wo[win].winhighlight:match("%f[%w]" .. name .. ":([^,]+)")
  -- A headless window may not allocate its internal mapping namespace until drawn.
  local value = hl(namespace, namespace == 0 and (target or name) or name)
  -- Neovim's generated winhighlight namespace links to its global target.
  return value.link and hl(0, value.link) or value
end
local function floating(filetype, mapping)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = filetype or ""
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "popup text" })
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = 2, col = 2, width = 24, height = 2, border = "single", style = "minimal",
  })
  vim.wo[win].winhighlight, vim.wo[win].winblend = mapping or "", 65
  return win
end

-- Terminal Neovim must retain its existing transparency and backdrop behavior.
vim.g.neovide, vim.o.pumblend = nil, 35
local terminal = floating("lazy_backdrop", "Normal:NormalFloat")
require(module).apply()
assert(vim.api.nvim_win_is_valid(terminal) and vim.wo[terminal].winblend == 65
  and vim.wo[terminal].winhighlight == "Normal:NormalFloat" and vim.o.pumblend == 35, "terminal policy changed")
vim.api.nvim_win_close(terminal, true)

vim.g.neovide, vim.g.neovide_normal_opacity = true, .85
for _, theme in ipairs({ "dark", "light" }) do
  local colors = require("config.appearance.themes.ayu_" .. theme .. "_customed").base_30
  local normal, popup = rgb(colors.black), rgb(colors.darker_black)
  package.loaded.base46 = { get_theme_tb = function() return colors end }
  vim.api.nvim_set_hl(0, "Normal", { fg = rgb(colors.white), bg = normal })
  vim.api.nvim_set_hl(0, "NormalNC", {})
  vim.api.nvim_set_hl(0, "PopupSource", { fg = 0x123456, bold = true })
  vim.api.nvim_set_hl(0, "PopupAlias", { link = "PopupSource" })
  vim.api.nvim_set_hl(0, "PopupBorder", { fg = 0x4488aa, bg = normal, blend = 80 })
  vim.api.nvim_set_hl(0, "CursorLine", { bg = rgb(colors.one_bg), blend = 20 })
  vim.api.nvim_set_hl(0, "Visual", { fg = 0x335577, bg = rgb(colors.visual_selection or colors.one_bg3), blend = 45 })
  vim.api.nvim_set_hl(0, "PopupNormalBackground", { fg = 0x336699, bg = normal, blend = 0 })
  local cursorline, visual = hl(0, "CursorLine"), hl(0, "Visual")
  local base = hl(0, "Normal")
  local ordinary_mapping = "Normal:PopupAlias,FloatBorder:PopupBorder,Search:Visual"
  local ordinary = floating("", ordinary_mapping)
  vim.wo[ordinary].cursorline = true
  local namespaced = floating("", "Normal:PopupAlias")
  local provider = vim.api.nvim_create_namespace("PopupProvider_" .. theme)
  local semantic = { fg = 0xaa4400, bg = 0x998877, bold = true }
  vim.api.nvim_set_hl(provider, "Normal", { fg = 0x654321, bg = normal, italic = true, blend = 40 })
  vim.api.nvim_set_hl(provider, "PopupSemantic", semantic)
  vim.api.nvim_set_hl(provider, "CursorLine", { fg = 0x775533, bg = rgb(colors.one_bg2), blend = 60 })
  vim.api.nvim_win_set_hl_ns(namespaced, provider)
  local dashboard = floating("terminal", "Normal:SnacksDashboardTerminal")
  local backdrops = {}
  for _, filetype in ipairs({ "lazy_backdrop", "mason_backdrop", "snacks_win_backdrop" }) do
    backdrops[#backdrops + 1] = floating(filetype)
  end
  backdrops[#backdrops + 1] = floating("", "Normal:CustomBackdrop")

  local helper = require(module)
  assert(helper.background() == popup and popup ~= normal, theme .. " theme popup background")
  helper.apply()
  for _, win in ipairs(backdrops) do assert(not vim.api.nvim_win_is_valid(win), "explicit backdrop survived") end
  assert(vim.o.pumblend == 0, "completion menu remains transparent")
  local mapping, namespace = vim.wo[ordinary].winhighlight, vim.api.nvim_get_hl_ns({ winid = namespaced })
  -- A theme refresh and module reload must follow new foregrounds, not the previous derived group.
  vim.api.nvim_set_hl(0, "PopupSource", { fg = 0x224466, bold = true })
  vim.api.nvim_set_hl(provider, "Normal", { fg = 0x765432, bg = normal, italic = true, blend = 40 })
  package.loaded[module] = nil
  helper = require(module)
  for _, current in ipairs({ ordinary, namespaced, root }) do
    vim.api.nvim_set_current_win(current)
    helper.apply()
    for _, case in ipairs({ { ordinary, 0x224466, "bold" }, { namespaced, 0x765432, "italic" } }) do
      for _, name in ipairs({ "Normal", "NormalFloat", "NormalNC" }) do
        local attrs = window_hl(case[1], name)
        assert(attrs.bg == popup and attrs.blend == 0 and attrs.fg == case[2] and attrs[case[3]],
          theme .. " focused/unfocused popup lost opacity or source styling: " .. name .. " " .. vim.inspect(attrs)
            .. " ns=" .. vim.api.nvim_get_hl_ns({ winid = case[1] }) .. " " .. vim.wo[case[1]].winhighlight)
      end
      assert(vim.wo[case[1]].winblend == 0, "window blend survived")
    end
  end
  local border = window_hl(ordinary, "FloatBorder")
  assert(border.bg == popup and border.fg == 0x4488aa and border.blend == 0, "border lost color/opacity: " .. vim.inspect(border))
  local row, selected, same = window_hl(ordinary, "CursorLine"), window_hl(ordinary, "Visual"), window_hl(ordinary, "PopupNormalBackground")
  assert(row.bg == cursorline.bg and row.blend == 0 and selected.bg == visual.bg and selected.fg == visual.fg
    and selected.blend == 0 and same.bg == popup and same.fg == 0x336699, "semantic backgrounds still transparent")
  local private_row, mapped = window_hl(namespaced, "CursorLine"), window_hl(ordinary, "Search")
  assert(private_row.bg == rgb(colors.one_bg2) and private_row.fg == 0x775533 and private_row.blend == 0
    and mapped.bg == visual.bg and mapped.fg == visual.fg and mapped.blend == 0, "private style or non-base mapping lost")
  assert(vim.wo[ordinary].winhighlight == mapping
    and vim.api.nvim_get_hl_ns({ winid = namespaced }) == namespace, "reload stacked mappings/namespaces")
  local actual = hl(namespace, "PopupSemantic")
  assert(actual.fg == semantic.fg and actual.bg == semantic.bg and actual.bold, "provider semantic highlight changed")
  assert(vim.wo[dashboard].winblend == 65 and vim.wo[dashboard].winhighlight == "Normal:SnacksDashboardTerminal",
    "embedded Dashboard terminal changed")
  assert(vim.deep_equal(base, hl(0, "Normal")) and vim.deep_equal(cursorline, hl(0, "CursorLine"))
    and vim.deep_equal(visual, hl(0, "Visual")) and vim.wo[root].winhighlight == root_options[1]
    and vim.wo[root].winblend == root_options[2], "root editor material changed")
  local clone = floating("", ordinary_mapping)
  local count = vim.tbl_count(vim.api.nvim_get_namespaces())
  helper.apply()
  assert(vim.api.nvim_get_hl_ns({ winid = clone }) == vim.api.nvim_get_hl_ns({ winid = ordinary })
    and vim.tbl_count(vim.api.nvim_get_namespaces()) == count, "same popup policy allocated another namespace")
  vim.api.nvim_win_close(clone, true)
  for _, win in ipairs({ ordinary, namespaced, dashboard }) do vim.api.nvim_win_close(win, true) end
end
print("PASS: opaque popup classes, backdrop removal, light/dark focus/reload/namespace styling; terminal, Dashboard and editor isolation")
