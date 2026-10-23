-- GLOW_TEST_CONFIG=/path/to/config GLOW_TEST_VIMTEX=/path/to/vimtex
-- nvim --headless --noplugin -u NONE -i NONE -l tests/media/latex_build_cache.lua
-- Real frozen VimTeX init/start/command construction; exec is captured, not launched.
local config=assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp={config,assert(vim.env.GLOW_TEST_VIMTEX),vim.env.VIMRUNTIME}
local root=vim.fn.tempname()..'-latex-cache'
vim.fn.mkdir(root,'p')
local receipt={state='started',config=config,actual_compiler=false,cases={}}
local has=vim.fn.has
local ok,err=xpcall(function()
  dofile(config..'/lua/plugins/languages/vimtex.lua').init()
  assert(package.loaded['config.latex.build_cache']==nil,'Mac imported Windows-only cache module')
  local viewer=vim.g.vimtex_view_method
  for _,event in ipairs(vim.api.nvim_get_autocmds({event='User'})) do
    assert(event.group_name~='GlowLatexBuildCache','non-Windows registered a new compilation event')
  end
  vim.g.vimtex_view_enabled=0
  vim.g.vimtex_cache_persistent=0
  vim.g.vimtex_compiler_silent=1
  vim.g.vimtex_quickfix_mode=0
  local base=vim.deepcopy(vim.g.vimtex_compiler_latexmk)
  base.executable=vim.v.progpath -- requirement check only; exec below never launches
  base.continuous=0
  base.callback=0
  vim.g.glow_cache_commands={}
  vim.cmd([[
    function! GlowCacheCapture(cmd) dict abort
      call add(g:glow_cache_commands, self.cmd)
    endfunction
  ]])
  vim.cmd('filetype plugin on')
  local function options() return vim.fn.eval('copy(b:vimtex.compiler.options)') end
  local function has_g(command) return command:match('%s%-g%s')~=nil end
  local function project(label,pwd,manual,out_dir)
    local directory=root..'/'..label
    vim.fn.mkdir(directory..'/build','p')
    local source=directory..'/main.tex'
    local text={'\\documentclass{article}','\\begin{document}','Cache fixture.','\\end{document}'}
    vim.fn.writefile(text,source)
    local fls=directory..(out_dir and '/build' or '')..'/main.fls'
    local recorded=pwd=='same' and assert(vim.uv.fs_realpath(directory)) or pwd
    if recorded then vim.fn.writefile({'PWD '..recorded,'INPUT main.tex'},fls) end
    local settings=vim.deepcopy(base)
    settings.out_dir=out_dir and 'build' or ''
    if manual then settings.options[#settings.options+1]='-g' end
    vim.g.vimtex_compiler_latexmk=settings
    local before=#vim.g.glow_cache_commands
    vim.cmd.edit(source)
    assert(vim.fn.eval('b:vimtex.compiler.name')=='latexmk','real VimTeX compiler missing')
    assert(#vim.g.glow_cache_commands==before,'initialization started compilation')
    vim.cmd("let b:vimtex.compiler.exec = function('GlowCacheCapture')")
    return {source=source,text=text,fls=fls,recorded=recorded,before=before}
  end
  local function compile()
    vim.cmd('VimtexCompileSS')
    return vim.g.glow_cache_commands[#vim.g.glow_cache_commands]
  end
  local function success() vim.cmd('call vimtex#compiler#callback(2)') end
  project('unchanged-mac-old-root','/Users/old-machine/project')
  assert(not vim.tbl_contains(options(),'-g'),'Mac compile options changed')
  assert(not has_g(compile()),'Mac copied cache changed the compile command')
  success()
  assert(vim.g.vimtex_view_method==viewer,'Mac viewer configuration changed')
  receipt.cases[#receipt.cases+1]={label='actual Mac, old root, no new events',incremental=true,viewer_unchanged=true}
  -- Only the Lua platform gate is modeled as Windows below. Frozen VimTeX
  -- initialization and command construction remain real, and no job is launched.
  vim.fn.has=function(name)
    if name=='win32' then return 1 end
    if name=='macunix' then return 0 end
    return has(name)
  end
  require('config.latex.build_cache').setup()
  local moved=project('moved-mac','/Users/old-machine/project',false,true)
  assert(vim.tbl_contains(options(),'-g'),'relocated cache not armed')
  assert(has_g(compile()),'real VimTeX command missing -g')
  vim.api.nvim_exec_autocmds('User',{pattern='VimtexEventCompileFailed',modeline=false})
  assert(vim.tbl_contains(options(),'-g'),'failure dropped pending forced build')
  vim.fn.writefile({'PWD '..vim.uv.fs_realpath(root..'/moved-mac'),'INPUT main.tex'},moved.fls)
  success()
  assert(not vim.tbl_contains(options(),'-g'),'success kept module-owned -g')
  assert(not has_g(compile()),'second compilation was not incremental')
  vim.api.nvim_exec_autocmds('User',{pattern='VimtexEventInitPost',modeline=false})
  assert(not vim.tbl_contains(options(),'-g'),'new recorder cache was treated as relocated')
  assert(vim.deep_equal(vim.fn.readfile(moved.source),moved.text),'source changed')
  receipt.cases[#receipt.cases+1]={label='relocated Mac root, output directory, failure then success',forced_once=true}
  local windows=project('moved-windows','C:\\Users\\OldMachine\\project')
  assert(has_g(compile()),'foreign Windows root not detected on current platform')
  success()
  assert(not vim.tbl_contains(options(),'-g'))
  assert(vim.fn.filereadable(windows.fls)==1,'recorder was deleted')
  receipt.cases[#receipt.cases+1]={label='foreign Windows absolute root',forced_once=true}
  for _,case in ipairs({{'new',nil},{'same-root','same'},{'relative-evidence','relative/project'}}) do
    project(case[1],case[2])
    assert(not vim.tbl_contains(options(),'-g'),case[1]..': forced ordinary project')
    assert(not has_g(compile()),case[1]..': command has unexpected -g')
    receipt.cases[#receipt.cases+1]={label=case[1],incremental=true}
  end
  project('manual-g','/old/project',true)
  assert(has_g(compile()))
  success()
  assert(vim.tbl_contains(options(),'-g'),'manual -g removed')
  assert(has_g(compile()),'manual -g not passed to next command')
  receipt.cases[#receipt.cases+1]={label='pre-existing manual -g',preserved=true}
  receipt.compilation_calls=#vim.g.glow_cache_commands
  receipt.commands=vim.deepcopy(vim.g.glow_cache_commands)
  assert(vim.g.vimtex_view_method==viewer,'migration module changed viewer')
  receipt.windows_gate_modeled=true
  receipt.state='passed'
end,debug.traceback)
vim.fn.has=has
vim.fn.delete(root,'rf')
if not ok then receipt.state='failed';receipt.error=err end
if vim.env.GLOW_TEST_RECEIPT then vim.fn.writefile({vim.json.encode(receipt)},vim.env.GLOW_TEST_RECEIPT) end
assert(ok,err)
print('PASS real VimTeX: actual Mac old-root command/viewer/events unchanged; modeled Windows migration forces once, success restores incremental, new/same-root untouched, manual -g preserved; compiler not launched')
vim.cmd('qa!')
