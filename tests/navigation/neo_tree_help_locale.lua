-- Real pinned NeoTree defaults, resolver and show_help path; never run file/Git actions.
local config = assert(vim.env.GLOW_TEST_CONFIG)
local plugins = vim.env.GLOW_TEST_PLUGIN_ROOT or vim.fn.expand('~/.local/share/nvim/lazy')
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
for _, name in ipairs({ 'neo-tree.nvim', 'nui.nvim', 'plenary.nvim' }) do vim.opt.rtp:append(plugins .. '/' .. name) end
local stdpath, work = vim.fn.stdpath, vim.fn.tempname()
vim.fn.stdpath = function(name) return name == 'state' and work or name == 'config' and work .. '/config' or stdpath(name) end
local language = 'en'
local catalog = require('config.locale.catalog').new(function() return language end)
package.loaded['config.platform.locale'] = { current = function() return language end, t = catalog.t }
vim.o.columns, vim.o.lines, vim.o.laststatus, vim.o.showtabline = 160, 80, 0, 0
local sources = { 'filesystem', 'buffers', 'git_status', 'document_symbols' }
require('neo-tree').setup({ sources = sources, enable_git_status = false, enable_diagnostics = false,
  window = { position = 'left', width = 28 }, filesystem = { use_libuv_file_watcher = false } })
require('neo-tree').ensure_config()
local renderer = require('neo-tree.ui.renderer')
local manager = require('neo-tree.sources.manager')
require('neo-tree.sources.common.help').show = require('config.navigation.neo_tree_help').show
local popups = require('neo-tree.ui.popups')
local popup_options, last_title = popups.popup_options, nil
popups.popup_options = function(title, ...) last_title = title; return popup_options(title, ...) end
local checked, total, states = {}, 0, {}
local function labels(buf)
  local result = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local key, text = line:match('^%s*(.-) %-> (.*)$')
    if key then result[key] = text end
  end
  return result
end
local function set_language(value)
  language = value
  vim.api.nvim_exec_autocmds('User', { pattern = 'GlowLanguageChanged', modeline = false })
end
local function close_help(win)
  local esc = vim.fn.maparg('<Esc>', 'n', false, true)
  assert(type(esc.callback) == 'function', 'real help must preserve Esc close binding')
  esc.callback()
  assert(not vim.api.nvim_win_is_valid(win), 'Esc did not close its own popup')
end
local function help_roundtrip(state, trigger, prefix)
  set_language('en')
  local handlers = {}
  for key, mapping in pairs(state.resolved_mappings) do handlers[key] = mapping.handler end
  local bindings = vim.deepcopy(state.window.mappings)
  state.resolved_mappings[trigger].handler() -- actual configured command -> pinned show_help -> adapted view
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  assert(win ~= state.winid and vim.bo[buf].filetype == 'neo-tree-popup')
  local english = labels(buf)
  local english_title = last_title
  if not prefix then assert(english_title == 'NeoTree Shortcuts') end
  for key, mapping in pairs(state.resolved_mappings) do
    if not prefix or #key > #prefix and key:sub(1, #prefix) == prefix then
      local visible = prefix and key:sub(#prefix + 1) or key
      assert(english[visible] == catalog.t(mapping.text), 'English command bytes changed: ' .. key)
    end
  end
  vim.api.nvim_win_set_cursor(win, { math.min(8, vim.api.nvim_buf_line_count(buf)), 0 })
  local cursor = vim.api.nvim_win_get_cursor(win)
  set_language('zh')
  assert(vim.api.nvim_get_current_win() == win and vim.api.nvim_get_current_buf() == buf, 'language rebuilt/focused another window')
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor), 'selected help row moved')
  local chinese = labels(buf)
  if not prefix then assert(last_title:find('NeoTree', 1, true) and last_title ~= english_title, 'NeoTree product name lost') end
  for key, text in pairs(chinese) do
    assert(text ~= english[key], 'untranslated default help: ' .. state.name .. '/' .. key .. ': ' .. text)
    assert(not text:find('scroll_preview', 1, true) and not text:find('clear_clipboard', 1, true)
      and not text:find('toggle_auto_expand_width', 1, true), 'raw internal command exposed')
  end
  if not prefix then
    assert(chinese['<C-f>'] == '向下滚动预览' and chinese['<C-b>'] == '向上滚动预览', vim.inspect(chinese))
    assert(chinese.e == '切换自动扩展窗口宽度')
    assert(chinese['<C-r>'] == (state.name == 'document_symbols'
      and '不可用（清空 NeoTree 文件剪贴板）' or '清空 NeoTree 文件剪贴板'))
    if state.name == 'document_symbols' then
      assert(chinese['<cr>'] == '跳转到符号' and chinese['/'] == '即时筛选符号')
    elseif state.name == 'git_status' then
      assert(chinese.gU == '撤销最近一次提交（保留暂存更改）')
    end
  end
  set_language('en')
  assert(vim.deep_equal(labels(buf), english) and last_title == english_title, 'English roundtrip lost original labels/title')
  assert(vim.deep_equal(state.window.mappings, bindings), 'source bindings/config mutated')
  for key, mapping in pairs(state.resolved_mappings) do assert(mapping.handler == handlers[key], 'handler changed') end
  local count = vim.tbl_count(english)
  total = total + count
  checked[#checked + 1] = state.name .. (prefix and '/sort' or '') .. ':' .. count
  close_help(win)
end
local ok, err = xpcall(function()
  for _, name in ipairs(sources) do
    local state = manager.get_state(name)
    renderer.acquire_window(state) -- real pinned default-mapping resolution
    states[#states + 1] = state
    help_roundtrip(state, '?')
    local binding = state.window.mappings.o
    if type(binding) == 'table' and binding.config and binding.config.prefix_key == 'o' then
      help_roundtrip(state, 'o', 'o')
    end
    renderer.close(state)
  end
  -- Config direction takes precedence over physical key; explicit user text and
  -- function labels which resemble command IDs are retained. Resolve in plugin.
  local state = states[1]
  state.window.mappings['<C-f>'] = { 'scroll_preview', config = { direction = 10 } }
  state.window.mappings['<C-b>'] = { 'scroll_preview', config = { direction = -10 } }
  state.window.mappings.X = { 'scroll_preview', config = { direction = 2 }, desc = 'My Preview / 用户自定义' }
  state.window.mappings.Y = { function() error('custom action must not execute') end, desc = 'clear_clipboard' }
  renderer.acquire_window(state)
  set_language('zh')
  state.resolved_mappings['?'].handler()
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local custom = labels(buf)
  assert(custom['<C-f>'] == '向上滚动预览' and custom['<C-b>'] == '向下滚动预览')
  assert(custom.X == 'My Preview / 用户自定义' and custom.Y == 'clear_clipboard', 'user description translated')
  set_language('en')
  assert(labels(buf).X == custom.X and labels(buf).Y == custom.Y)
  close_help(win)
  renderer.close(state)
  -- Per-popup listener cleanup: closed help must retain no language callbacks.
  local before = #vim.api.nvim_get_autocmds({ event = 'User', pattern = 'GlowLanguageChanged' })
  assert(before == 0, 'closed help leaked language listeners: ' .. before)
  print('PASS: real NeoTree help en→zh→en in the same window; ' .. table.concat(checked, ', ') .. '; total ' .. total
    .. ' rows; signed preview direction/custom descriptions/handlers/cleanup preserved')
end, debug.traceback)
vim.fn.delete(work, 'rf')
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') end
vim.cmd('qa!')
