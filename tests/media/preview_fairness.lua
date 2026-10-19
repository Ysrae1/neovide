-- Isolated real companion modules; the RPC endpoint models the bounded native
-- slots without launching a GUI, Yazi process, kernel, or installed plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or root .. "/portable/payload/nvim")
vim.g.neovide, vim.g.neovide_native_image = true, true
vim.g.neovide_channel_id, vim.g.neovide_native_image_anchor = 42, true
vim.g.neovide_cell_width, vim.g.neovide_cell_height = 10, 20
local transport = require("config.media.image_transport")
local active, loads, errors, notifications = {}, {}, {}, {}
vim.notify = function(text) notifications[#notifications + 1] = text end
local function count(owner)
  local n = 0
  for _, request in pairs(active) do if not owner or request.owner == owner then n = n + 1 end end
  return n
end
vim.rpcnotify = function(channel, method, id, path, owner)
  assert(channel == 42)
  if method == "neovide.image.load" then
    assert(owner == "molten" or owner == "image" or owner == "yazi", "explicit load owner")
    loads[#loads + 1] = { id = id, owner = owner }
    local err
    if not active[id] and (count() >= 8 or owner == "molten" and count("molten") >= 6) then
      err = "Image preview capacity reached (application maximum 8; Notebook maximum 6)"
      errors[#errors + 1] = id
    else active[id] = { owner = owner, path = path } end
    vim.schedule(function() transport.on_status(id, 1, 1, err) end)
  elseif method == "neovide.image.close" then active[id] = nil end
  return true
end
local path = vim.fn.tempname() .. ".png"
-- Only the bounded PNG header is inspected by Lua; decoding is the GUI's job.
local uv = vim.uv or vim.loop
local file = assert(uv.fs_open(path, "w", 384))
assert(uv.fs_write(file, "\137PNG\13\10\26\10" .. string.rep("\0", 8)
  .. "\0\0\0\1\0\0\0\1" .. string.rep("\0", 8), 0))
uv.fs_close(file)
local buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "saved output", "second cell" })
vim.b[buffer].glow_notebook_edit = true
package.loaded["config.media.notebook_ui"] = {
  refresh = function() end,
  virtual_output_geometry = function()
    return { row = 1, col = 1, width = 30, clip = { row = 0, col = 0, width = 80, height = 20 },
      anchor = { epoch = 1 } }
  end,
}
local molten = require("config.media.molten_images")
assert(molten.setup())
local raw = {}
for _ = 1, 8 do
  local id = assert(transport.allocate("image"))
  transport.notify("image", "load", id, path)
  raw[#raw + 1] = id
end
local descriptors = {}
for _ = 1, 8 do descriptors[#descriptors + 1] = { path = path } end
local namespace = vim.api.nvim_create_namespace("preview-fairness-source")
molten.set_inline_output(buffer, namespace, 0, 0, {}, descriptors, "saved")
assert(vim.wait(1000, function() return #errors == 6 end), "full interactive use temporarily defers Notebook")
local initial_loads = #loads
for _ = 1, 20 do molten.refresh() end
assert(#loads == initial_loads, "capacity failure cannot spin on repeated redraws")
local function deferred_rows()
  local marks = molten.inline_output_marks(buffer)
  assert(#marks == 1 and marks[1].lines == 8, "all eight output records/padding retained")
  local mark = vim.api.nvim_buf_get_extmark_by_id(buffer, marks[1].namespace, marks[1].id, { details = true })
  local deferred = 0
  for _, line in ipairs(mark[3].virt_lines) do
    if line[1][1]:find("暂缓", 1, true) then deferred = deferred + 1 end
  end
  return deferred
end
assert(deferred_rows() == 8, "busy output has a visible placeholder, not a blank lost image")
for _, id in ipairs(raw) do transport.notify("image", "close", id) end
assert(vim.wait(2000, function() return count("molten") == 6 end), "interactive close resumes Notebook after backoff")
assert(deferred_rows() == 2, "two excess Notebook outputs retain visible placeholders")
local errors_before_mix = #errors
vim.cmd("vsplit")
local image_window = vim.api.nvim_get_current_win()
local image = require("config.media.image")
assert(image.open(path))
assert(vim.wait(1000, function() return count("image") == 1 end), "ordinary image gets first reserved interactive slot")
vim.cmd("split")
local yazi_window = vim.api.nvim_get_current_win()
local yazi_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(yazi_window, yazi_buffer)
local yazi = require("config.media.yazi")
local options = yazi.configure({ config_home = vim.fn.tempname() })
options.hooks.yazi_opened(path, yazi_buffer, {})
options.hooks.on_yazi_ready(yazi_buffer, {}, { yazi_id = "qa", emit_to_yazi = function() end })
vim.api.nvim_exec_autocmds("User", { pattern = "YaziDDSCustom", data = {
  type = "neovide-glow-preview", yazi_id = "qa",
  raw_data = vim.json.encode({ action = "preview", source = path, path = path, visible = true,
    area = { x = 0, y = 0, w = 2, h = 2 } }),
} })
assert(vim.wait(1000, function() return count("yazi") == 1 end), "Yazi gets second reserved interactive slot")
assert(count("molten") == 6 and count() == 8 and #errors == errors_before_mix, "actual three-module mix fits the application cap")
-- Selecting a previously deferred output must return an old slot before loading
-- its replacement, even while all eight shared native slots are occupied.
molten.image_api.from_file(path, { id = "inline:saved:1", buffer = buffer })
molten.refresh()
assert(count("molten") == 6 and #errors == errors_before_mix, "Notebook output selection recycles before load")
assert(deferred_rows() == 2, "changing the chosen output preserves the others")
assert(vim.wait(1000, function() return #notifications >= 1 end))
local capacity_notices = 0
for _, text in ipairs(notifications) do if text:find("最多 6", 1, true) then capacity_notices = capacity_notices + 1 end end
assert(capacity_notices == 1, "capacity explanation is shown once, without redraw floods")
vim.api.nvim_set_current_win(image_window)
image.close()
vim.api.nvim_buf_delete(yazi_buffer, { force = true })
molten.image_api.clear_all()
assert(vim.wait(1000, function() return count() == 0 end), "closing all three module owners returns every reservation")
vim.fn.delete(path)
print("Preview fairness: real three-module mix, deferred output preservation, bounded retry and release passed")
vim.cmd("qa!")
