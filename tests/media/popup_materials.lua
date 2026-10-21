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
  -- User defaults are editable; establish the policies exercised by this fixture.
  local profiles = require("config.appearance.popup_materials")
  for name in pairs(profiles.config) do profiles.config[name] = { mode = "opaque" } end
  profiles.config.notebook_output = { mode = "editor" }
  profiles.config.matrix_dashboard = { mode = "editor" }
  local theme_data = require("config.appearance.themes.ayu_" .. theme .. "_customed")
  local colors = theme_data.base_30
  vim.o.background = theme
  local normal, popup = rgb(colors.black), rgb(colors.darker_black)
  package.loaded.base46 = { get_theme_tb = function(kind)
    return kind == "base_30" and colors or kind == "base_16" and theme_data.base_16 or {}
  end }
  vim.api.nvim_set_hl(0, "Normal", { fg = rgb(colors.white), bg = normal })
  vim.api.nvim_set_hl(0, "NormalNC", {})
  vim.api.nvim_set_hl(0, "PopupSource", { fg = 0x123456, bold = true })
  vim.api.nvim_set_hl(0, "PopupAlias", { link = "PopupSource" })
  vim.api.nvim_set_hl(0, "PopupBorder", { fg = 0x4488aa, bg = normal, blend = 80 })
  vim.api.nvim_set_hl(0, "CursorLine", { bg = rgb(colors.one_bg), blend = 20 })
  vim.api.nvim_set_hl(0, "Visual", { fg = 0x335577, bg = rgb(colors.visual_selection or colors.one_bg3), blend = 45 })
  vim.api.nvim_set_hl(0, "PopupNormalBackground", { fg = 0x336699, bg = normal, blend = 0 })
  vim.api.nvim_set_hl(0, "St_EmptySpace", { fg = 0x334455, bg = rgb(colors.one_bg), blend = 80 })
  vim.api.nvim_set_hl(0, "StatusLine", { link = "St_EmptySpace" })
  vim.api.nvim_set_hl(0, "WinBar", { fg = 0x445566, bg = normal, blend = 70 })
  vim.api.nvim_set_hl(0, "TabLineFill", { bg = normal, blend = 60 })
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
  for _, win in ipairs({ ordinary, namespaced }) do
    local namespace = vim.api.nvim_get_hl_ns({ winid = win })
    assert(hl(namespace, "St_EmptySpace").blend == 80 and hl(namespace, "StatusLine").blend == 80
      and hl(namespace, "WinBar").blend == 70 and hl(namespace, "TabLineFill").blend == 60,
      "focused popup namespace must preserve global statusline/winbar/tabline material")
  end
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
  local dashboard_policy = profiles.resolve("matrix_dashboard", base, popup)
  local dashboard_material = window_hl(dashboard, "Normal")
  assert(vim.w[dashboard].glow_popup_material.profile == "matrix_dashboard"
    and vim.w[dashboard].glow_popup_material.mode == "editor"
    and dashboard_material.bg == dashboard_policy.bg and dashboard_material.blend == dashboard_policy.blend
    and vim.wo[dashboard].winhighlight == "Normal:SnacksDashboardTerminal",
    "embedded Dashboard Matrix must inherit the editor material")
  assert(vim.deep_equal(base, hl(0, "Normal")) and vim.deep_equal(cursorline, hl(0, "CursorLine"))
    and vim.deep_equal(visual, hl(0, "Visual")) and vim.wo[root].winhighlight == root_options[1]
    and vim.wo[root].winblend == root_options[2], "root editor material changed")
  local clone = floating("", ordinary_mapping)
  local count = vim.tbl_count(vim.api.nvim_get_namespaces())
  helper.apply()
  assert(vim.api.nvim_get_hl_ns({ winid = clone }) == vim.api.nvim_get_hl_ns({ winid = ordinary })
    and vim.tbl_count(vim.api.nvim_get_namespaces()) == count, "same popup policy allocated another namespace")
  vim.api.nvim_win_close(clone, true)
  local notebook = floating("molten_output", "Normal:PopupAlias")
  local preview = floating("noice", "Normal:SnacksPickerPreview")
  local manager = floating("lazy", "Normal:PopupAlias")
  helper.apply()
  assert(vim.w[notebook].glow_popup_material.profile == "notebook_output"
    and window_hl(notebook, "Normal").bg == normal and window_hl(notebook, "Normal").blend == 15,
    "Notebook output defaults to editor material")
  assert(vim.w[preview].glow_popup_material.profile == "snacks_picker_preview"
    and window_hl(preview, "Normal").bg == popup, "specific window role precedes reused filetype")
  local notebook_namespace = vim.api.nvim_get_hl_ns({ winid = notebook })
  profiles.config.notebook_output = { mode = "custom", blend = 37, bg = { light = "one_bg2", dark = "one_bg3" } }
  helper.apply()
  assert(window_hl(notebook, "Normal").bg == rgb(colors[theme == "light" and "one_bg2" or "one_bg3"])
    and window_hl(notebook, "Normal").blend == 37 and window_hl(manager, "Normal").blend == 0
    and window_hl(manager, "Normal").bg == popup, "custom profile stays independent of other popup classes")
  assert(vim.api.nvim_get_hl_ns({ winid = notebook }) == notebook_namespace,
    "changing material reuses the existing window namespace")
  profiles.config.lazy = { mode = "custom", blend = 64, bg = "#456789" }
  vim.w[preview].glow_popup_profile = "lazy"
  helper.apply()
  assert(vim.w[preview].glow_popup_material.profile == "lazy" and window_hl(preview, "Normal").bg == 0x456789
    and window_hl(preview, "Normal").blend == 64, "explicit window profile precedes plugin roles")
  profiles.config.notebook_output = { mode = "opaque" }
  helper.apply()
  assert(window_hl(notebook, "Normal").bg == popup and window_hl(notebook, "Normal").blend == 0,
    "already open Notebook can return to opaque")
  profiles.config.notebook_output = { mode = "editor" }
  profiles.config.completion_menu = { mode = "custom", blend = 29 }
  vim.api.nvim_set_hl(0, "Pmenu", { fg = 0x112233, bg = popup })
  helper.apply()
  assert(window_hl(notebook, "Normal").bg == normal and window_hl(notebook, "Normal").blend == 15
    and hl(0, "Pmenu").bg == popup and hl(0, "Pmenu").blend == 29,
    "editor mode and native Pmenu background policy apply without window blending")
  local body = require("config.appearance.popup_text").config.body
  local old_policy = package.loaded[module]
  profiles.reload()
  profiles = require("config.appearance.popup_materials")
  assert(package.loaded[module] ~= old_policy, "first reload must replace a cached older popup policy")
  local restored_notebook = profiles.resolve("notebook_output", base, popup)
  local restored_manager = profiles.resolve("lazy", base, popup)
  assert(window_hl(notebook, "Normal").bg == restored_notebook.bg
    and window_hl(notebook, "Normal").blend == restored_notebook.blend
    and window_hl(manager, "Normal").bg == restored_manager.bg
    and window_hl(manager, "Normal").blend == restored_manager.blend,
    "saved module reload refreshes already open windows through final transparency policy")
  assert(require("config.appearance.popup_text").config.body == body,
    "material reload must not reload or overwrite hand-edited popup text settings")
  local namespace_after_reload = vim.api.nvim_get_hl_ns({ winid = notebook })
  assert(hl(namespace_after_reload, "St_EmptySpace").blend == hl(0, "St_EmptySpace").blend,
    "theme/material reload must preserve global bottom-bar blend in a focused popup")
  for _, win in ipairs({ notebook, preview, manager }) do vim.api.nvim_win_close(win, true) end
  for _, win in ipairs({ ordinary, namespaced, dashboard }) do vim.api.nvim_win_close(win, true) end
end
print("PASS: per-class editor/custom/opaque popup materials, role precedence, reload and global chrome isolation; backdrop removal and terminal/Dashboard/editor preservation")
