-- Terminal round caps inherit the bar, across modes and theme reloads.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or root .. "/portable/payload/nvim")
local config = { theme = "minimal", separator_style = "round" }
package.loaded.nvconfig = { ui = { statusline = config } }
local caps = require("config.appearance.capsules")
local status = {}
for _, mode in ipairs({ "Normal", "Visual", "Insert", "Terminal", "NTerminal", "Replace", "Confirm", "Command", "Select" }) do
  status[#status + 1] = "St_" .. mode .. "ModeSep"
end
for _, name in ipairs({ "file", "Pos", "cwd", "lsp" }) do status[#status + 1] = "St_" .. name .. "_sep" end
local avante = { "AvanteReversedTitle", "AvanteReversedSubtitle", "AvanteReversedThirdTitle" }
local function attributes(name) return vim.api.nvim_get_hl(0, { name = name, link = false, create = false }) end
for _, theme in ipairs({ "dark", "light" }) do
  vim.o.background = theme
  local outside = theme == "dark" and 0x0b0e14 or 0xfafafa
  local ink, accent = theme == "dark" and 0x14171d or 0xefefef, 0x00bfff
  local function reset()
    for _, names in ipairs({ status, avante }) do
      for _, name in ipairs(names) do vim.api.nvim_set_hl(0, name, { fg = accent, bg = outside, bold = true, ctermbg = 0 }) end
    end
    vim.api.nvim_set_hl(0, "St_NormalMode", { fg = ink, bg = accent })
    vim.api.nvim_set_hl(0, "AvanteTitle", { fg = ink, bg = accent })
    vim.api.nvim_set_hl(0, "St_sep_r", { fg = accent })
  end
  reset()
  local body, title, right = attributes("St_NormalMode"), attributes("AvanteTitle"), attributes("St_sep_r")
  caps.apply()
  for _, names in ipairs({ status, avante }) do
    for _, name in ipairs(names) do
      local hl = attributes(name)
      assert(hl.bg == nil and hl.ctermbg == nil, theme .. " outside background: " .. name)
      assert(hl.fg == accent and hl.bold, "cap color/style preserved: " .. name)
    end
  end
  assert(vim.deep_equal(body, attributes("St_NormalMode")) and vim.deep_equal(title, attributes("AvanteTitle")), "solid bodies preserved")
  assert(vim.deep_equal(right, attributes("St_sep_r")), "correct right cap preserved")
  caps.apply()
  assert(attributes(status[1]).bg == nil, "idempotent theme refresh")
  reset(); vim.g.neovide = true; caps.apply(); vim.g.neovide = nil
  assert(attributes(status[1]).bg == outside and attributes(avante[1]).bg == outside, "native GUI keeps its separate material handling")
  for _, settings in ipairs({ { "minimal", "block" }, { "default", "round" } }) do
    reset(); config.theme, config.separator_style = unpack(settings); caps.apply()
    assert(attributes(status[1]).bg == outside, "other statusline styles preserved")
    assert(attributes(avante[1]).bg == nil, "Avante cap backgrounds independent of statusline style")
  end
  config.theme, config.separator_style = "minimal", "round"
end
vim.api.nvim_set_hl(0, "AvanteReversedThirdTitle", {})
caps.apply()
assert(next(attributes("AvanteReversedThirdTitle")) == nil, "absent plugin groups are not created")
print("Capsule backgrounds: terminal dark/light, all cap roles, bodies and GUI isolation passed")
vim.cmd.qa()
