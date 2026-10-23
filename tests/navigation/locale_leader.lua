-- Reproduce early glass -> locale load with a pre-LazyVim leader, then the final leader.
-- Uses the actual WhichKey mode tree, node visibility and rendered leaf label.
local config=assert(vim.env.GLOW_TEST_CONFIG)
local wk=vim.env.GLOW_TEST_WHICH_KEY or vim.fn.expand('~/.local/share/nvim/lazy/which-key.nvim')
vim.opt.rtp={config,vim.env.VIMRUNTIME,wk}
local std=vim.fn.stdpath
local work=vim.fn.tempname()
vim.fn.stdpath=function(n) return n=='state' and work or n=='config' and (work..'/config') or std(n) end
vim.g.mapleader='\\'
vim.g.neovide=true
local ok,err=xpcall(function()
  require('config.platform.glass').setup()
  local locale=require('config.platform.locale')
  -- This is where LazyVim config/options.lua defines the real leader.
  vim.g.mapleader=' '
  local spec=dofile(config..'/lua/plugins/editor/which_key.lua')
  require('which-key').setup(spec.opts(nil,{}))
  vim.api.nvim_exec_autocmds('VimEnter',{})
  assert(vim.wait(500,function() return require('which-key.config').loaded end),'WhichKey startup did not settle')
  local Buf=require('which-key.buf')
  local before=assert(Buf.get({mode='n',update=true}))
  assert(not before.tree:find(' <C-l>'),'the early-load fixture did not reproduce the old missing leaf')
  -- The explicit post-LazyVim init.lua setup must correct the concrete prefix.
  locale.setup()
  local mode=assert(Buf.get({mode='n',update=true}))
  local leaf=assert(mode.tree:find(' <C-l>'),'WhichKey tree still lacks Space Ctrl-L')
  assert(not leaf.hidden and not leaf:is_group(),'language item must be a visible action leaf')
  assert(not mode.tree:find('\\<C-l>'),'stale default-leader binding was retained')
  local view=require('which-key.view')
  locale.set_lang('en',{save=false,silent=true})
  local english=view.item(leaf,{parent=leaf.parent})
  assert(english.desc=='Toggle Language' and not english.group)
  locale.set_lang('zh',{save=false,silent=true})
  local chinese=view.item(leaf,{parent=leaf.parent})
  assert(chinese.desc=='切换界面语言' and not chinese.group)
  local found=0
  mode.tree:walk(function(node) if node.keymap and node.keymap.desc=='Toggle Language' then found=found+1 end end)
  assert(found==1,'language action is duplicated in the WhichKey tree')
  print('PASS GUI early locale load: one actual WhichKey Space Ctrl-L leaf, English/Chinese renderer, old-prefix cleanup')
end,debug.traceback)
vim.fn.stdpath=std
vim.fn.delete(work,'rf')
if not ok then error(err) end
