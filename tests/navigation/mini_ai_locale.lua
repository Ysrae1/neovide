-- Real installed MiniAi + LazyVim metadata + WhichKey renderer, no GUI/kernel.
-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE -n -l tests/navigation/mini_ai_locale.lua
-- Sources: MiniAi bfb26d9, LazyVim 28db03f (coding.lua/util/mini.lua), WhichKey 3aab2147.
local config = assert(vim.env.GLOW_TEST_CONFIG)
local plugins = vim.env.GLOW_TEST_PLUGIN_ROOT or vim.fn.expand('~/.local/share/nvim/lazy')
vim.opt.rtp = { config, plugins .. '/mini.ai', plugins .. '/LazyVim', plugins .. '/which-key.nvim', vim.env.VIMRUNTIME }
local stdpath, work = vim.fn.stdpath, vim.fn.tempname()
vim.fn.stdpath = function(name)
  return name == 'state' and work or name == 'config' and work .. '/config' or stdpath(name)
end
vim.g.mapleader, vim.g.glow_ui_language = ' ', 'en'
vim.o.columns, vim.o.lines, vim.o.swapfile = 240, 80, false
local ok, err = xpcall(function()
  local mini = require('lazyvim.util.mini')
  _G.LazyVim = { mini = mini }
  local ai, options = require('mini.ai')
  for _, plugin in ipairs(dofile(plugins .. '/LazyVim/lua/lazyvim/plugins/coding.lua')) do
    if plugin[1] == 'nvim-mini/mini.ai' then options = plugin.opts(); break end
  end
  assert(options, 'Actual pinned LazyVim MiniAi options are unavailable')
  ai.setup(options)
  local locale = require('config.platform.locale')
  require('which-key').setup(locale.setup_which_key({ delay = 0, triggers = {}, notify = false,
    icons = { mappings = false }, show_help = false,
    win = { no_overlap = false, width = 230, height = 65, row = 1, col = 1 },
    plugins = { marks = false, registers = false, presets = { operators = true, motions = false,
      text_objects = true, windows = false, nav = false, z = false, g = false } } }))
  mini.ai_whichkey(options) -- Unmodified real provider registration, not copied labels.
  assert(vim.wait(1000, function() return require('which-key.config').loaded end))
  local api, view, buf = vim.api, require('which-key.view'), vim.api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, { '  (  foo  )  ', '', 'last line' })
  api.nvim_win_set_cursor(0, { 1, 6 })
  local source = api.nvim_buf_get_lines(buf, 0, -1, false)
  local before = { x = api.nvim_get_keymap('x'), o = api.nvim_get_keymap('o') }
  local menus, object_count = 0, 0
  local function render(mode, prefix, language)
    locale.set_lang(language, { save = false, silent = true })
    local registered = require('which-key.buf').get({ mode = mode, buf = buf, update = true })
    local node = assert(registered.tree:find(prefix, { expand = true }))
    require('which-key.state').state = { mode = registered, node = node,
      filter = { mode = mode, keys = prefix }, show = true, started = vim.uv.hrtime() / 1e6 }
    view.show()
    local rows, originals = {}, {}
    local body = table.concat(api.nvim_buf_get_lines(view.view.buf, 0, -1, false), '\n')
    for _, child in ipairs(node:children()) do
      local item = view.item(child)
      rows[child.key], originals[child.key] = item.desc, child.desc
      if language == 'zh' and child.mapping then
        assert(item.desc ~= child.desc, 'MiniAi label remained English: ' .. child.keys .. ': ' .. child.desc)
        assert(body:find(item.desc, 1, true), 'Translated label was not actually drawn: ' .. child.keys)
      end
    end
    return rows, originals
  end
  for _, mode in ipairs({ 'x', 'o' }) do
    for _, prefix in ipairs({ 'a', 'i', 'an', 'in', 'al', 'il' }) do
      local en, original = render(mode, prefix, 'en')
      local zh = render(mode, prefix, 'zh')
      local restored = render(mode, prefix, 'en')
      assert(vim.deep_equal(en, restored), 'MiniAi English roundtrip changed: ' .. mode .. '/' .. prefix)
      for key, text in pairs(original) do
        local marker = (key == 'n' or key == 'l') and '+' or ''
        assert(en[key] == marker .. text, 'Original English object description changed')
      end
      if prefix:sub(1, 1) == 'i' then
        assert(zh['"'] == '双引号内文本' and zh["'"] == '单引号内文本' and zh['`'] == '反引号内文本')
        assert(zh['('] == '圆括号内文本（不含边缘空白）' and zh[')'] == '圆括号内文本（含边缘空白）')
        assert(zh.g == '全文（不含首尾空行）' and zh.f == '函数体')
      else
        assert(zh['"'] == '双引号字符串（含引号）' and zh['('] == '圆括号块（含括号）')
        assert(zh.g == '全文（含首尾空行）' and zh.f == '完整函数定义')
      end
      menus, object_count = menus + 1, object_count + vim.tbl_count(original)
    end
  end
  view.hide()
  require('which-key.state').state = nil
  -- Check advertised whitespace/quote semantics against MiniAi's actual regions.
  local function region(kind, id) return assert(ai.find_textobject(kind, id)) end
  assert(region('i', '(').from.col == 6 and region('i', '(').to.col == 8)
  assert(region('i', ')').from.col == 4 and region('i', ')').to.col == 10)
  assert(region('a', '(').from.col == 3 and region('a', '(').to.col == 11)
  assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), source), 'Renderer changed source text')
  assert(vim.deep_equal(api.nvim_get_keymap('x'), before.x) and vim.deep_equal(api.nvim_get_keymap('o'), before.o),
    'Language changed actual MiniAi mappings')
  -- Generic user descriptions and explicit child keymaps remain user text.
  vim.keymap.set('x', 'i"', function() end, { desc = '" string' })
  require('which-key.buf').clear({ buf = buf })
  local registered = require('which-key.buf').get({ mode = 'x', buf = buf, update = true })
  locale.set_lang('zh', { save = false, silent = true })
  assert(view.item(registered.tree:find('i"')).desc == '" string', 'User child override was relabeled')
  assert(locale.t('function') == 'function' and locale.t('class') == 'class', 'Generic user labels entered the global catalog')
  print(('PASS real MiniAi/LazyVim/WhichKey: %d x/o menus, %d rendered entries en/zh/en; inner/around/edge whitespace, exact English, raw mappings/source, user overrides'):format(menus, object_count))
end, debug.traceback)
vim.fn.stdpath = stdpath
vim.fn.delete(work, 'rf')
if not ok then error(err) end
