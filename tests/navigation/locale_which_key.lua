local root = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = {root, vim.env.VIMRUNTIME, vim.fn.expand('~/.local/share/nvim/lazy/snacks.nvim'), vim.fn.expand('~/.local/share/nvim/lazy/which-key.nvim'),vim.fn.expand('~/.local/share/nvim/lazy/LazyVim')}
local temp = vim.fn.tempname()
local std = vim.fn.stdpath
vim.fn.stdpath=function(n) return n=='state' and temp or n=='config' and (temp..'/config') or std(n) end
vim.g.mapleader=' '
local locale=require('config.platform.locale')
_G.Snacks=require('snacks')
_G.LazyVim={safe_keymap_set=function(m,l,r,o) o=vim.tbl_extend("force",{},o or {});o.ft=nil;vim.keymap.set(m,l,r,o) end,format={snacks_toggle=function(buffer)
 return Snacks.toggle({name=buffer and 'Auto Format (Buffer)' or 'Auto Format (Global)',get=function() return false end,set=function()end})
end}}
require('lazyvim.config.keymaps')
local spec=dofile(root..'/lua/plugins/editor/which_key.lua')
local opts=spec.opts(nil,{spec={{'<leader>f',group='file/find'}}})
require('which-key').setup(opts)
local view=require('which-key.view')
locale.set_lang('zh',{save=false,silent=true})
assert(view.replace('desc','Find File')=='查找文件')
locale.set_lang('en',{save=false,silent=true})
assert(view.replace('desc','Find File')=='Find File')
print('REAL_MAP_AUDIT='..vim.json.encode(locale.audit()))
print('PASS actual which-key renderer and registered LazyVim keymap descriptions')
vim.fn.stdpath=std
vim.fn.delete(temp,'rf')
