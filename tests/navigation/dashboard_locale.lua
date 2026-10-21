-- Real Snacks renderer with isolated files and controlled startup-stat fixtures.
-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE -l tests/navigation/dashboard_locale.lua
-- Dependencies: existing Snacks checkout. No terminal, GUI app, kernel or user file is opened.
local config = assert(vim.env.GLOW_TEST_CONFIG)
local snacks = vim.env.GLOW_TEST_SNACKS or vim.fn.expand('~/.local/share/nvim/lazy/snacks.nvim')
vim.opt.rtp = {config, vim.env.VIMRUNTIME, snacks}
local original_stdpath, lang, lc = vim.fn.stdpath, vim.env.LANG, vim.env.LC_ALL
local work = vim.fn.tempname()
vim.fn.mkdir(work, 'p')
vim.fn.stdpath = function(name)
  return name == 'state' and (work .. '/state') or name == 'config' and (work .. '/config') or original_stdpath(name)
end
vim.g.mapleader = ' '
vim.o.lines, vim.o.columns = 70, 160
local ok, err = xpcall(function()
  local locale = require('config.platform.locale')
  _G.Snacks = require('snacks')
  Snacks.setup({dashboard={enabled=false},notifier={enabled=false}})
  local dashboard = require('snacks.dashboard')
  local definition = dofile(config .. '/lua/plugins/appearance/snacks.lua')[1].opts.dashboard
  local opts = vim.deepcopy(definition)
  for _, key in ipairs(opts.preset.keys) do if key.desc == "Lazy" then key.enabled = true end end
  local path = work .. '/file-unchanged.py'
  vim.fn.writefile({'# own fixture only'}, path)
  local oldfiles = dashboard.oldfiles
  dashboard.oldfiles = function()
    local done = false
    return function() if not done then done = true; return path end end
  end
  opts.win, opts.buf = 0, vim.api.nvim_create_buf(false, true)
  opts.sections = {
    {section='keys', title='Keymaps', indent=2, padding=1},
    {section='recent_files', title='Recent Files', limit=1, indent=2, padding=1},
    {section='projects', title='Projects', dirs={work}, limit=1, indent=2, padding=1},
    definition.sections[#definition.sections],
  }
  dashboard.lazy_stats = {loaded=34,count=69,startuptime=191.27}
  local original_section = dashboard.sections.startup()
  local section = require('config.appearance.dashboard_locale').startup
  local rendered = dashboard.open(opts)
  local function sample(language)
    locale.set_lang(language,{save=false,silent=true})
    local text = table.concat(vim.api.nvim_buf_get_lines(rendered.buf,0,-1,false),'\n')
    return text
  end
  local en = sample('en')
  local zh = sample('zh')
  local en_again = sample('en')
  assert(en == en_again, 'Dashboard text did not restore after en/zh/en')
  assert(en:find('Keymaps',1,true) and zh:find('快捷功能',1,true))
  assert(zh:find('文件',1,true) and zh:find('目录',1,true), 'recent/project type labels were not localized')
  assert(en:find('file',1,true) and en:find('directory',1,true))
  assert(zh:find('插件管理',1,true) and zh:find('文件管理',1,true))
  assert(zh:find('Neovim 已加载 34/69 个插件，耗时 191.27 毫秒',1,true), 'Chinese startup statistics were incomplete')
  assert(en:find('Neovim loaded 34/69 plugins in 191.27ms',1,true))
  locale.set_lang('en',{save=false,silent=true})
  assert(vim.deep_equal(section(),original_section), 'English startup spans/highlights changed')
  dashboard.lazy_stats = {loaded=57,count=90,startuptime=123.456}
  local changed = sample('zh')
  assert(changed:find('Neovim 已加载 57/90 个插件，耗时 123.46 毫秒',1,true), 'startup numbers were frozen')
  local original_file = definition.formats.file({file=path},{width=1000})
  assert(original_file[#original_file][1] == 'file-unchanged.py', 'the filename was translated')
  dashboard.oldfiles = oldfiles
  print('PASS real Snacks Dashboard en/zh/en: quick functions, file/directory prefixes, Lazy/Yazi, live startup counts/time, unchanged paths/highlights')
end,debug.traceback)
vim.fn.stdpath = original_stdpath
vim.env.LANG,vim.env.LC_ALL = lang,lc
vim.fn.delete(work,'rf')
if not ok then error(err) end
