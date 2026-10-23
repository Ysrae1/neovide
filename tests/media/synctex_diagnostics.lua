-- GLOW_TEST_CONFIG=/path/to/config nvim --headless --noplugin -u NONE -i NONE
--   -l tests/media/synctex_diagnostics.lua
-- Isolated CLI-response regression; no compiler, viewer, or user file is opened.
local config=assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp={config,vim.env.VIMRUNTIME}
local root=vim.fn.tempname()..'-synctex-diagnostics'
vim.fn.mkdir(root,'p')
local source,pdf=root..'/tool.tex',root..'/tool.pdf'
vim.fn.writefile({'Diagnostic fixture.'},source)
vim.fn.writefile({'%PDF-fixture'},pdf)
vim.fn.writefile({'Input:1:/Users/example/Desktop/tex.tool/tool.tex'},root..'/tool.synctex')
local system,notify,has=vim.system,vim.notify,vim.fn.has
local notices,requests,points={},{},{}
local response
local receipt={state='started',config=config,actual_cli=false,cases={}}
local ok,err=xpcall(function()
  vim.fn.has=function(name) if name=='win32' then return 1 end return has(name) end
  vim.cmd.edit(source)
  vim.g.glow_synctex_executable=vim.v.progpath -- executable check only; never launched
  vim.g.neovide_native_preview=true
  vim.g.neovide_native_pdf_synctex=true
  vim.g.neovide_channel_id=77
  vim.notify=function(message) notices[#notices+1]=message end
  vim.system=function(argv,opts,callback)
    requests[#requests+1]={argv=argv,opts=opts}
    local task={kill=function() error('No concurrent query expected') end}
    vim.schedule(function() callback(response) end)
    return task
  end
  package.loaded['config.media.preview']={pdf_sync=function(_,point) points[#points+1]=point end}
  local locale=require('config.platform.locale')
  local synctex=require('config.media.synctex')
  local no_tag='This is SyncTeX command line utility, version 1.5\nSyncTeX Warning: No tag for C:/Users/example/Desktop/tex.tool/tool.tex\n'
  local hint='The source path recorded in the SyncTeX file does not match the current file. Force a full recompilation on this computer.'
  local function fail_case(label,language,value,expected)
    vim.g.glow_ui_language=language
    response=value
    local count=#notices
    assert(synctex.forward(pdf))
    assert(vim.wait(1000,function() return #notices>count end,5),label..': no diagnostic')
    local message=notices[#notices]
    for _,text in ipairs(expected) do assert(message:find(text,1,true),label..': '..message) end
    assert(#points==(label:find('non-Windows',1,true) and 1 or 0),label..': unexpected viewer request')
    receipt.cases[#receipt.cases+1]={label=label,message=message}
  end
  fail_case('No tag with empty stderr, English','en',{code=0,stdout=no_tag,stderr=''},
    {hint,'SyncTeX Warning: No tag for C:/Users/example/Desktop/tex.tool/tool.tex'})
  assert(locale.known(hint),'new hint missing from locale catalog')
  fail_case('No tag with empty stderr, Chinese','zh',{code=0,stdout=no_tag,stderr=''},
    {'同步文件记录的源路径与当前文件不匹配，请在本机强制重新编译。','SyncTeX Warning: No tag for C:/Users/example/Desktop/tex.tool/tool.tex'})
  fail_case('ordinary failure preserves both output streams','en',
    {code=1,stdout='stdout diagnostic',stderr='stderr diagnostic'},
    {'SyncTeX view mapping not found: ','stdout diagnostic','stderr diagnostic'})
  assert(notices[#notices]:find(hint,1,true)==nil,'ordinary failure incorrectly diagnosed as path mismatch')
  response={code=0,stdout='SyncTeX result begin\nPage:1\nh:12\nv:34\nW:56\nH:7\nSyncTeX result end\n',stderr=''}
  local count=#notices
  assert(synctex.forward(pdf))
  assert(vim.wait(1000,function() return #points==1 end,5),'valid mapping was not forwarded')
  assert(#notices==count and points[1].page==1 and points[1].x==12 and points[1].y==34)
  assert(#requests==4,'diagnosis retried or launched additional commands')
  -- A Windows-specific diagnostic must not alter the existing Mac/Linux flow.
  vim.fn.has=function(name) if name=='win32' then return 0 end return has(name) end
  fail_case('non-Windows keeps original empty-stderr behavior','en',{code=0,stdout=no_tag,stderr=''},
    {'SyncTeX view mapping not found: '})
  assert(notices[#notices]=='SyncTeX view mapping not found: ','non-Windows diagnostic changed')
  assert(#requests==5,'unexpected non-Windows extra query')
  for _,request in ipairs(requests) do
    assert(request.argv[2]=='view' and request.opts.env.SYNCTEX_VIEWER=='' and request.opts.env.SYNCTEX_EDITOR=='')
  end
  receipt.valid_mapping_preserved=true
  receipt.automatic_compilation=false
  receipt.state='passed'
end,debug.traceback)
vim.system,vim.notify,vim.fn.has=system,notify,has
vim.fn.delete(root,'rf')
if not ok then receipt.state='failed';receipt.error=err end
if vim.env.GLOW_TEST_RECEIPT then vim.fn.writefile({vim.json.encode(receipt)},vim.env.GLOW_TEST_RECEIPT) end
assert(ok,err)
print('PASS Windows SyncTeX diagnostics: empty stderr, No tag path hint in English/Chinese, both output streams, valid mapping; non-Windows errors unchanged; no real CLI/GUI')
vim.cmd('qa!')
