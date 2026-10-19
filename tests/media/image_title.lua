-- nvim --headless -u NONE -l tests/media/image_title.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or (root .. "/portable/payload/nvim"))
vim.o.columns = 120
vim.g.neovide, vim.g.neovide_native_image, vim.g.neovide_channel_id = true, true, 77
local sent = {}
vim.rpcnotify = function(channel, method, ...)
  assert(channel == 77)
  sent[#sent + 1] = { method = method, args = { ... } }
  return true
end
vim.notify = function() end
package.preload.base46 = function()
  return { get_theme_tb = function() return { base0B = "#C5F760" } end }
end
local function theme(background)
  vim.o.background = background
  local dark = background == "dark"
  vim.api.nvim_set_hl(0, "Normal", { fg = dark and 0xeeeeee or 0x303030, bg = dark and 0x171717 or 0xfafafa })
  vim.api.nvim_set_hl(0, "St_file_txt", { bg = dark and 0x252934 or 0xeeeeee })
  for name, color in pairs({ St_NormalMode = 0x5599cc, St_TerminalMode = 0x55bb99, St_InsertMode = 0xaa77cc }) do
    vim.api.nvim_set_hl(0, name, { fg = dark and 0x171717 or 0xffffff, bg = color })
  end
end
theme("dark")
vim.api.nvim_set_hl(0, "GlowNotebookKernel", { bg = 0x123456 })
local image = require("config.media.image")
local capsule = require("config.media.capsule")
local function rendered(view, width)
  return vim.api.nvim_eval_statusline(image.render_title(view, width), { use_winbar = true, maxwidth = width })
end
local view = { width = 547, height = 434, zoom = 1, path = "/tmp/hidden 100% 图像.png" }
assert(image.open(view.path))
local id = sent[1].args[1]
image.on_status(id, 547, 434, nil)
local win = vim.api.nvim_get_current_win()
local title = vim.api.nvim_eval_statusline(vim.wo[win].winbar, { use_winbar = true, maxwidth = 120 }).str
assert(title:find("VIEW  ×1 · 547×434", 1, true), title)
for _, text in ipairs({ "ZOOM  + − · 0", "PAN  hjkl", "CLOSE  q" }) do assert(title:find(text, 1, true), title) end
assert(not title:find("hidden", 1, true) and not title:find(".png", 1, true), "filename is only in the existing status line")
image.zoom(1.25)
assert(vim.wo[win].winbar:find("×1.2", 1, true), "zoom status updates")
image.fit()
assert(vim.wo[win].winbar:find("×1 ·", 1, true), "fit status updates")
for _, width in ipairs({ 120, 80, 64, 48, 40, 32, 24, 18, 12, 8, 4 }) do
  for _, state in ipairs({ view, { zoom = 1 }, { error = "failure", zoom = 1 } }) do
    local result = rendered(state, width)
    assert(result.width <= width and not result.str:find("<", 1, true), "bounded title " .. width .. " " .. result.str)
    local _, left = result.str:gsub("", "")
    local _, right = result.str:gsub("", "")
    assert(left == right, "complete capsule ends " .. width)
    assert(not result.str:find(" ", 1, true) and not result.str:find(" ", 1, true), "no external padding inside caps")
    assert(result.str:find("q", 1, true), "close stays discoverable")
  end
end
local escaped = vim.api.nvim_eval_statusline(capsule.format("GlowMediaInfo", "VIEW", "100% 中文 "), { use_winbar = true }).str
assert(escaped == "VIEW  100% 中文", escaped)
local function luminance(color)
  local function linear(c) c = c / 255; return c <= .04045 and c / 12.92 or ((c + .055) / 1.055) ^ 2.4 end
  return .2126 * linear(math.floor(color / 65536)) + .7152 * linear(math.floor(color / 256) % 256) + .0722 * linear(color % 256)
end
for _, background in ipairs({ "dark", "light" }) do
  theme(background)
  vim.api.nvim_exec_autocmds(background == "dark" and "ColorScheme" or "User", background == "dark" and {} or { pattern = "NvThemeReload" })
  vim.wait(20)
  for _, name in ipairs({ "Info", "Action", "Menu" }) do
    local function hl(suffix) return vim.api.nvim_get_hl(0, { name = "GlowMedia" .. name .. (suffix or ""), link = false }) end
    local body, value, cap, end_cap = hl(), hl("Value"), hl("Cap"), hl("ValueCap")
    assert(body.bg == value.fg and body.bg == cap.fg and value.bg == end_cap.fg, "one hue per capsule")
    assert(not cap.bg and not end_cap.bg and body.bold and not value.bold, "caps and segments")
    local a, b = luminance(value.fg), luminance(value.bg)
    assert((math.max(a, b) + .05) / (math.min(a, b) + .05) >= 4.5, background .. " value contrast")
    assert(value.bg == (background == "dark" and 0x252934 or 0xffffff), "theme surface")
  end
end
image.on_status(id, nil, nil, "failure")
assert(vim.wo[win].winbar:find("ERROR", 1, true) and vim.wo[win].winbar:find("RETRY", 1, true), "error and retry state")
assert(not package.loaded["config.media.notebook_edit"], "title does not load Notebook or change its layout/state")
assert(vim.api.nvim_get_hl(0, { name = "GlowNotebookKernel", link = false }).bg == 0x123456)
image.close()
print("image title: filename hidden, state/actions, capsule bounds, dark/light and theme refresh: PASS")
vim.cmd.qa()
