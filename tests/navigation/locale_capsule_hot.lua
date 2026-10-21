-- Existing-state hot patch fixture: never starts a kernel, reads a PDF or sends RPC.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local original_stdpath = vim.fn.stdpath
local temp = vim.fn.tempname()
vim.fn.stdpath = function(name)
  return name == "state" and temp or name == "config" and config or original_stdpath(name)
end
vim.g.mapleader = " "
vim.o.columns, vim.o.lines = 420, 65
local locale = require("config.platform.locale")
locale.set_lang("zh", { save = false, silent = true })
local notebook = require("config.media.notebook_edit")
local image = require("config.media.image")
local preview = require("config.media.preview")
local function upvalue(fn, wanted)
  for index = 1, 80 do
    local name, value = debug.getupvalue(fn, index)
    if not name then break end
    if name == wanted then return value end
  end
  error("missing fixture upvalue " .. wanted)
end
local sessions = upvalue(notebook.status, "sessions")
local image_views, image_active = upvalue(image.refresh, "views"), upvalue(image.on_status, "active")
local preview_views, preview_active = upvalue(preview.refresh, "views"), upvalue(preview.on_status, "active")
local function window(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  return win, buf
end
local notebook_win, notebook_buf = window({ "# %%", "print('preserve edited Notebook')", "unsaved = 7" })
sessions[notebook_buf] = { buf = notebook_buf, ready = true, kernel = "existing-kernel-id", owned = true,
  selected = { name = "fixture", display_name = "Existing Fixture Python", executable = "/fixture/python" },
  imported = true, pending = false, restore_path = "/fixture/saved-output.ipynb" }
vim.api.nvim_buf_set_extmark(notebook_buf, vim.api.nvim_create_namespace("molten-extmarks"), 1, 0,
  { virt_lines = { { { "[OLD] Out[1]: 7", "Normal" } } } })
local image_win, image_buf = window({ "native image placeholder" })
local image_view = { id = 41, win = image_win, buf = image_buf, width = 547, height = 434,
  zoom = 1.5, pan_x = 7, pan_y = -3, geometry = { row = 1, col = 1, width = 120, height = 60 } }
image_views[image_win], image_active[41] = image_view, image_view
local pdf_win, pdf_buf = window({ "native PDF placeholder" })
local pdf_view = { id = 73, win = pdf_win, buf = pdf_buf, kind = "pdf", source = "/fixture/user.pdf",
  status = { state = "ready", page = 3, pages = 19, zoom = .7 },
  geometry = { row = 1, col = 1, width = 120, height = 60 } }
preview_views[pdf_win], preview_active[73] = pdf_view, pdf_view
-- Simulate the exact cache problem: old renderers still produce English despite zh.
notebook.render_title = function() return "KERNEL CELLS MENU" end
image.render_title = function() return "VIEW ZOOM PAN CLOSE" end
preview.render_title = function() return "PDF PAGE ZOOM FOCUS CLOSE" end
for _, item in ipairs({ { notebook_win, notebook.render_title }, { image_win, image.render_title }, { pdf_win, preview.render_title } }) do
  vim.wo[item[1]].winbar = item[2]()
end
local rpc = vim.rpcnotify
vim.rpcnotify = function() error("hot patch must not send RPC") end
local script = assert(vim.env.GLOW_CAPSULE_HOT_SCRIPT)
local result = dofile(script)
assert(result.state_preserved and result.before_sha256 == result.after_sha256)
assert(package.loaded["config.media.notebook_edit"] == notebook and upvalue(notebook.status, "sessions") == sessions)
assert(upvalue(image.refresh, "views") == image_views and upvalue(preview.refresh, "views") == preview_views)
local function title(win)
  return vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true, maxwidth = 500 }).str
end
local initial = { title(notebook_win), title(image_win), title(pdf_win) }
for _, word in ipairs({ "内核", "单元格", "菜单" }) do assert(initial[1]:find(word, 1, true), word) end
for _, word in ipairs({ "视图", "缩放", "平移", "关闭" }) do assert(initial[2]:find(word, 1, true), word) end
for _, word in ipairs({ "PDF", "3/19", "70%", "翻页", "缩放", "进入", "关闭" }) do assert(initial[3]:find(word, 1, true), word) end
locale.set_lang("en", { save = false, silent = true })
assert(title(notebook_win):find("KERNEL", 1, true) and title(image_win):find("VIEW", 1, true) and title(pdf_win):find("PAGE", 1, true))
locale.set_lang("zh", { save = false, silent = true })
assert(vim.deep_equal(initial, { title(notebook_win), title(image_win), title(pdf_win) }), "capsules did not repaint after two language switches")
-- A second application must stay state-safe and keep a single event handler.
local second = dofile(script)
assert(second.state_preserved)
assert(#vim.api.nvim_get_autocmds({ group = "GlowLiveCapsuleLocale", event = "User" }) == 1)
assert(sessions[notebook_buf].kernel == "existing-kernel-id" and sessions[notebook_buf].ready)
assert(preview.status().page == 3 and preview.status().zoom == .7)
vim.rpcnotify, vim.fn.stdpath = rpc, original_stdpath
vim.fn.delete(temp, "rf")
print("PASS hot capsule renderers: existing module/session/view identities, edited text/output extmarks/kernel/page/zoom/window hashes preserved; no RPC; zh/en/zh and repeat apply")
