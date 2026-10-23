-- Actual frozen Neo-tree/Nui input + navigation; temporary files only, no user GUI.
-- GLOW_TEST_CONFIG=/path/to/config nvim --headless --noplugin -u NONE -i NONE -l tests/navigation/neo_tree_path.lua
local config = assert(vim.env.GLOW_TEST_CONFIG)
local plugins = vim.env.GLOW_TEST_PLUGIN_ROOT or vim.fn.expand("~/.local/share/nvim/lazy")
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
for _, name in ipairs({ "neo-tree.nvim", "nui.nvim", "plenary.nvim" }) do vim.opt.rtp:append(plugins .. "/" .. name) end
local work = vim.fn.tempname()
local original_stdpath = vim.fn.stdpath
vim.fn.stdpath = function(name)
  if name == "config" or name == "state" then return work .. "/" .. name end
  return original_stdpath(name)
end
vim.g.mapleader, vim.g.glow_ui_language = " ", "en"
vim.o.columns, vim.o.lines = 120, 40
local messages = {}
vim.notify = function(message) messages[#messages + 1] = message end
local input
local function same_path(a, b)
  return vim.fs.normalize(a, { expand_env = false }) == vim.fs.normalize(b, { expand_env = false })
end
local ok, err = xpcall(function()
  local origin, destination = work .. "/origin", work .. "/destination 中文"
  vim.fn.mkdir(origin, "p")
  vim.fn.mkdir(destination .. "/nested", "p")
  vim.fn.writefile({ "original" }, origin .. "/original.c")
  vim.fn.writefile({ "target" }, destination .. "/nested/.hidden.c")
  vim.cmd.edit(vim.fn.fnameescape(origin .. "/original.c"))
  local editor_buf, editor_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(editor_buf, 0, -1, false, { "unsaved draft" })
  local nt = require("neo-tree")
  local setup = nt.setup
  nt.setup = function(opts)
    opts.enable_git_status, opts.enable_diagnostics = false, false
    opts.default_component_configs.container.enable_character_fade = false
    opts.filesystem.async_directory_scan = "never"
    return setup(opts)
  end
  local spec = require("plugins.navigation.neo_tree")[2]
  spec.config()
  local command, manager = require("neo-tree.command"), require("neo-tree.sources.manager")
  command.execute({ source = "filesystem", action = "focus", dir = origin })
  local state = manager.get_state("filesystem")
  assert(vim.wait(1000, function() return state.winid and vim.api.nvim_win_is_valid(state.winid) end))
  local navigation = require("config.navigation.neo_tree_path")
  local goto_path = navigation.goto_path
  navigation.goto_path = function(s) input = goto_path(s); return input end
  local follow = require("config.navigation.project_root")
  local function open_input(width, language)
    vim.api.nvim_set_current_win(state.winid)
    vim.api.nvim_win_set_width(state.winid, width)
    vim.g.glow_ui_language = language or "en"
    assert(state.resolved_mappings["g/"].text == "Go to path", "actual g/ mapping missing")
    state.resolved_mappings["g/"].handler()
    assert(vim.wait(1000, function() return input.winid and vim.api.nvim_get_current_win() == input.winid end))
    local wc, tw = vim.api.nvim_win_get_config(input.winid), vim.api.nvim_win_get_width(state.winid)
    local outer = wc.win == state.winid and wc or vim.api.nvim_win_get_config(wc.win)
    assert(outer.relative == "win" and outer.win == state.winid, "input must be anchored to the tree")
    local pos, tree_pos = vim.api.nvim_win_get_position(input.winid), vim.api.nvim_win_get_position(state.winid)
    assert(pos[2] > tree_pos[2] and pos[2] + wc.width < tree_pos[2] + tw, "input outside tree width")
    assert(pos[1] >= tree_pos[1] and pos[1] + 1 < tree_pos[1] + vim.api.nvim_win_get_height(state.winid), "input outside tree height")
    local border_text = wc.title[1][1]
    if language == "zh" and width > 20 then assert(border_text:find("跳转到路径", 1, true), "Chinese input title missing") end
  end
  local function submit(value)
    input.input_props.on_submit(value)
    assert(vim.wait(1000, function() return not input.winid end))
    vim.wait(300, function() return false end, 10)
  end
  open_input(40)
  submit(destination)
  assert(same_path(state.path, destination), "absolute directory did not become tree root")
  follow.sync()
  assert(same_path(state.path, destination), "automatic follow reverted manual navigation")
  open_input(18, "zh")
  submit("nested/.hidden.c")
  assert(same_path(state.path, destination .. "/nested"), "relative file parent did not become tree root")
  assert(same_path(state.tree:get_node():get_id(), destination .. "/nested/.hidden.c"), "hidden file was not selected")
  local before = state.path
  open_input(28, "zh")
  submit("missing-file")
  assert(state.path == before and messages[#messages]:find("路径不是文件或文件夹", 1, true), "invalid input changed tree/missed feedback")
  open_input(28)
  local escape = vim.fn.maparg("<Esc>", "n", false, true)
  escape.callback()
  assert(vim.wait(1000, function() return not input.winid end))
  assert(state.path == before and vim.api.nvim_get_current_win() == state.winid, "cancel did not preserve tree/focus")
  open_input(28)
  submit("")
  assert(state.path == before, "empty input changed tree")
  vim.g.glow_ui_language = "zh"
  state.resolved_mappings["?"].handler()
  local help_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert(help_text:find("g/", 1, true) and help_text:find("跳转到路径", 1, true), "localized help must list g/")
  vim.fn.maparg("<Esc>", "n", false, true).callback()
  command.execute({ source = "filesystem", action = "focus", position = "right", dir = before })
  open_input(28)
  vim.fn.maparg("<Esc>", "n", false, true).callback()
  assert(vim.wait(1000, function() return not input.winid end))
  assert(same_path(navigation.resolve("~/", origin), vim.fn.expand("~")), "home expansion")
  assert(same_path(navigation.resolve('"' .. destination .. '"', origin), destination), "quoted path")
  local utils = require("neo-tree.utils")
  local windows = utils.is_windows
  utils.is_windows = true
  assert(navigation.resolve([[D:\Work\Project]], [[C:\Users\Example]]) == [[D:\Work\Project]], "drive path")
  assert(navigation.resolve([[\\Mac\Home\Dev]], [[C:\Users\Example]]) == [[\\Mac\Home\Dev]], "UNC path")
  assert(navigation.resolve([[..\Project]], [[D:\Work\child]]) == [[D:\Work\Project]], "Windows relative path")
  assert(navigation.resolve([[\Project]], [[D:\Work]]) == [[D:\Project]], "Windows volume-relative path")
  utils.is_windows = windows
  vim.api.nvim_set_current_win(editor_win)
  follow.sync()
  assert(same_path(state.path, (vim.uv or vim.loop).fs_realpath(origin)) and not state._glow_manual_path, "editor entry must resume project follow")
  assert(vim.bo[editor_buf].modified and vim.api.nvim_buf_get_lines(editor_buf, 0, -1, false)[1] == "unsaved draft", "editor draft changed")
  print("PASS Neo-tree g/: real input anchored left/right (40/18/28 columns), directory/file/hidden selection, cancel/invalid/empty, locale/help, auto-follow and draft protection; Windows path normalization modeled")
end, debug.traceback)
vim.fn.stdpath = original_stdpath
require("neo-tree.command").execute({ action = "close" })
vim.fn.delete(work, "rf")
if not ok then error(err) end
