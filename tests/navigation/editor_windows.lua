-- Actual Neovim split frames, window IDs, buffers and views; isolated child.
-- GLOW_TEST_CONFIG=/path/to/config nvim --headless --noplugin -u NONE -i NONE -n -l tests/navigation/editor_windows.lua
vim.opt.rtp = { assert(vim.env.GLOW_TEST_CONFIG), vim.env.VIMRUNTIME }
local panes = require("config.navigation.editor_windows")
local api = vim.api
vim.o.columns, vim.o.lines, vim.o.hidden, vim.o.equalalways = 180, 52, true, false
vim.o.laststatus, vim.o.scrolloff, vim.o.sidescrolloff = 3, 0, 0

local function content(name, ft, bt)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, "glow-window-fixture://" .. name)
  local lines = {}
  for line = 1, 220 do lines[line] = name .. line .. string.rep("x", 200) end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype, vim.bo[buf].buftype, vim.bo[buf].modified = ft or "lua", bt or "", false
  api.nvim_win_set_buf(0, buf)
  vim.wo.wrap = false
  return api.nvim_get_current_win()
end

local function save(win)
  return { id = win, buf = api.nvim_win_get_buf(win), position = api.nvim_win_get_position(win),
    width = api.nvim_win_get_width(win), height = api.nvim_win_get_height(win),
    fixed_width = vim.wo[win].winfixwidth, fixed_height = vim.wo[win].winfixheight,
    view = api.nvim_win_call(win, vim.fn.winsaveview) }
end

local function layout()
  vim.cmd("tabnew")
  local a = content("a" .. api.nvim_get_current_tabpage())
  vim.cmd("botright vnew")
  local ai = content("ai" .. a, "Avante", "nofile")
  api.nvim_win_set_width(ai, 28)
  vim.wo[ai].winfixwidth = true
  vim.cmd("belowright split")
  local input = content("input" .. a, "AvanteInput", "nofile")
  api.nvim_win_set_height(input, 7)
  vim.wo[input].winfixwidth = true
  api.nvim_set_current_win(a)
  vim.cmd("topleft vnew")
  local tree = content("tree" .. a, "neo-tree", "nofile")
  api.nvim_win_set_width(tree, 22)
  api.nvim_set_current_win(a)
  vim.cmd("belowright vsplit")
  local b = content("b" .. a)
  vim.cmd("belowright split")
  local c = content("c" .. a)
  local float = api.nvim_open_win(api.nvim_create_buf(false, true), false,
    { relative = "editor", row = 2, col = 4, width = 10, height = 3 })
  for index, win in ipairs({ a, b, c, tree, ai, input }) do
    api.nvim_win_call(win, function()
      vim.fn.winrestview({ lnum = 70 + index, col = 15, topline = 60 + index, leftcol = 5 })
    end)
  end
  api.nvim_set_current_win(a)
  return { a = a, b = b, c = c, tree = tree, ai = ai, input = input, float = float,
    auxiliary = { save(tree), save(ai), save(input), save(float) } }
end

local function auxiliary_unchanged(state)
  for _, item in ipairs(state.auxiliary) do
    local actual = save(item.id)
    assert(vim.deep_equal(actual, item), "auxiliary position/size/content/view/options changed: " .. vim.inspect({ before = item, after = actual }))
  end
end

local function views_by_buffer()
  local result = {}
  for _, win in ipairs(panes.list()) do result[api.nvim_win_get_buf(win)] = save(win).view end
  return result
end

local function views_preserved(before)
  for _, win in ipairs(panes.list()) do
    assert(vim.deep_equal(save(win).view, before[api.nvim_win_get_buf(win)]), "buffer cursor/scroll view changed")
  end
end

local report = {}
for _, direction in ipairs({ "left", "right", "up", "down" }) do
  local state = layout()
  assert(#panes.list() == 3 and not panes.is_editor(state.float) and not panes.is_editor(state.input))
  local before, id, buf = views_by_buffer(), state.a, api.nvim_win_get_buf(state.a)
  assert(panes.move(direction))
  assert(api.nvim_win_is_valid(id) and api.nvim_win_get_buf(id) == buf, "move must preserve actual window ID/content")
  auxiliary_unchanged(state)
  views_preserved(before)
  report[#report + 1] = "move_" .. direction
end

local state = layout()
local original_order, before = panes.list(), views_by_buffer()
local first, second = api.nvim_win_get_buf(state.a), api.nvim_win_get_buf(state.b)
local set_buf, assignments = api.nvim_win_set_buf, 0
api.nvim_win_set_buf = function(win, buf)
  assignments = assignments + 1
  if assignments == 2 then error("owned exchange failure") end
  return set_buf(win, buf)
end
local exchanged, failure = panes.swap(state.b)
api.nvim_win_set_buf = set_buf
assert(not exchanged and failure:find("owned exchange failure", 1, true))
assert(api.nvim_win_get_buf(state.a) == first and api.nvim_win_get_buf(state.b) == second,
  "failed exchange must roll back assigned buffers")
auxiliary_unchanged(state); views_preserved(before)
assert(panes.swap(state.b))
assert(api.nvim_win_get_buf(state.a) == second and api.nvim_win_get_buf(state.b) == first)
auxiliary_unchanged(state); views_preserved(before)
assert(panes.rotate()); auxiliary_unchanged(state); views_preserved(before)
assert(panes.rotate(true)); auxiliary_unchanged(state); views_preserved(before)
assert(panes.swap(state.b))
assert(api.nvim_win_get_buf(state.a) == first and api.nvim_win_get_buf(state.b) == second)
assert(vim.deep_equal(panes.list(), original_order), "swap/rotate must keep split frames intact")
assert(panes.equalize()); auxiliary_unchanged(state); views_preserved(before)
report[#report + 1] = "swap_rotate_equalize"

-- Protection applies to nofile/malformed auxiliary panes by role, not just
-- buftype, and focus entry remains possible in both directions.
vim.bo[api.nvim_win_get_buf(state.ai)].buftype = ""
assert(not panes.is_editor(state.ai))
api.nvim_set_current_win(state.tree)
local geometry = vim.fn.winlayout()
assert(not panes.move("right") and not panes.swap(state.a) and not panes.rotate()
  and not panes.equalize() and not panes.close_others(), "auxiliary-origin operations must be inert")
assert(vim.deep_equal(vim.fn.winlayout(), geometry))
assert(panes.focus("right") and panes.is_editor(api.nvim_get_current_win()), "tree must retain editor focus entry")
assert(panes.focus("left") and api.nvim_get_current_win() == state.tree, "editor must retain sidebar focus entry")
api.nvim_set_current_win(state.a)

vim.wo[state.b].winfixbuf = true
assert(not panes.swap(state.b) and not panes.rotate(), "fixed editor buffers must be respected")
vim.wo[state.b].winfixbuf = false
vim.bo[api.nvim_win_get_buf(state.b)].modified = true
vim.o.hidden = false
assert(not panes.close_others() and #panes.list() == 3, "unsaved-buffer failure must precede any close")
vim.o.hidden = true
assert(panes.close_others() and #panes.list() == 1 and api.nvim_get_current_win() == state.a)
auxiliary_unchanged(state)
assert(api.nvim_buf_is_valid(first) and api.nvim_buf_is_valid(second), "closing editor windows must retain their buffers")
assert(not panes.move("right") and not panes.swap() and not panes.rotate() and not panes.equalize())
report[#report + 1] = "guards_focus_close_others"
local terminal_buffer = api.nvim_create_buf(false, true)
api.nvim_open_term(terminal_buffer, {}) -- Native terminal buffer, no process.
local terminal_window = api.nvim_open_win(terminal_buffer, false, { split = "below", win = state.a })
assert(not panes.is_editor(terminal_window), "terminal split must not be treated as an editor")
print("REAL_EDITOR_WINDOWS=" .. vim.json.encode(report))
print("PASS editor-only operations: fixed sidebars/floats, window IDs, buffers/views, focus access, unsaved/fixed-buffer guards")

-- Exercise the user-facing arrow and Ctrl-W/proxy entry points as well.
local mapped = layout()
require("config.navigation.editor_window_keymaps").setup()
for _, lhs in ipairs({ "<C-S-Left>", "<C-w>L", "<C-w>x", "<C-w>r", "<C-w>R", "<C-w>=", "<leader>wo" }) do
  local binding = vim.fn.maparg(lhs, "n", false, true)
  assert(type(binding.callback) == "function", "missing protected entry: " .. lhs)
  binding.callback()
  auxiliary_unchanged(mapped)
end
print("PASS protected arrow, Ctrl-W and direct leader window entry points")
