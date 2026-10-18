"""Check the installed complete config; no running application is contacted."""
import json
import signal

import pynvim

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError('Glow keymap check')))
signal.alarm(40)
nvim = pynvim.attach('child', argv=[
    'nvim', '--embed', '--headless', '-i', 'NONE', '-n',
    '--cmd', 'let g:neovide = v:true',
])
try:
    nvim.ui_attach(100, 30, rgb=True)
    result = nvim.exec_lua('''
      local function mapping(key) return vim.fn.maparg(key,'n',false,true) end
      assert(vim.wait(10000,function()
        return mapping('<leader>uB').desc=='Toggle Glow 柔光'
      end,10),'complete startup did not register Glow: '..vim.inspect(mapping('<leader>uB'))
        ..' messages: '..vim.api.nvim_exec2('messages',{output=true}).output)
      local first=mapping('<leader>uB')
      assert(type(first.callback)=='function','Glow needs an executable callback')
      -- Git Signs registers uG from its opts, which may run after VeryLazy.
      -- Load both it and which-key through the real lazy loader.
      require('lazy').load({plugins={'gitsigns.nvim','which-key.nvim'}})
      vim.wait(100,function() return false end,10)
      local final=mapping('<leader>uB')
      local git=mapping('<leader>uG')
      assert(final.desc=='Toggle Glow 柔光' and final.callback==first.callback,
        'lazy plugin registration overwrote Glow')
      assert(git.desc=='Toggle Git Signs','uG must retain Git Signs')
      local signs=require('gitsigns.config').config.signcolumn
      vim.g.neovide_bloom=true
      final.callback()
      assert(vim.g.neovide_bloom==false,'uB did not disable bloom')
      final.callback()
      assert(vim.g.neovide_bloom==true,'uB did not enable bloom')
      assert(signs==require('gitsigns.config').config.signcolumn,'Glow changed Git Signs')
      local toggle=Snacks.toggle.get('glow')
      assert(toggle and toggle.opts.name=='Glow 柔光' and toggle.opts.which_key,
        'which-key must describe the same Glow toggle')
      return {leader=vim.g.mapleader,glow=final.desc,git=git.desc,
        actual_bloom_toggle=true,lazy_registration_preserved=true,which_key=true}
    ''')
    print(json.dumps(result, ensure_ascii=False))
finally:
    signal.alarm(0)
    try:
        nvim.command('qa!')
    except (EOFError, OSError):
        pass
