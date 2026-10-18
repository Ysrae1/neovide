-- Run with a previously prepared isolated builder argv in GLOW_BOOK_BUILDER_JSON.
vim.opt.rtp:append(vim.fs.joinpath(vim.uv.cwd(), 'portable/payload/nvim'))
local views, refreshes = {}, {}
package.loaded['config.media.preview'] = {
  open = function(path,opts) views[#views+1] = {path=path,opts=opts}; return true end,
  refresh_source = function(path) refreshes[#refreshes+1] = path end,
}
local messages = {}
vim.notify=function(message) messages[#messages+1]=message end
local book=require('config.media.book')
local root=vim.fs.joinpath(vim.uv.os_tmpdir(),'glow-real-jupyter-book-'..vim.uv.os_getpid())
vim.fn.mkdir(root,'p')
for _,name in ipairs({'_config.yml','_toc.yml','index.md'}) do
 vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath('tests/media/book-fixture',name)),vim.fs.joinpath(root,name))
end
local builder_json=assert(vim.env.GLOW_BOOK_BUILDER_JSON,'builder missing')
local opts={builder=vim.json.decode(builder_json)}
local function build(expected)
 assert(book.open(root,opts),'builder did not start')
 assert(vim.wait(90000,function() return not book.status(root).running end,50),'build timed out')
 if book.status(root).status ~= expected then book.log(root); error(table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\n')) end
end
build('ready')
assert(#views==1 and vim.fn.filereadable(views[1].path)==1,'successful native preview source missing')
local index=vim.fs.joinpath(root,'index.md')
local lines=vim.fn.readfile(index);lines[#lines+1]='';lines[#lines+1]='Official builder refreshed content 2026.';vim.fn.writefile(lines,index)
build('ready')
assert(#views==1 and #refreshes==1,'rebuild did not refresh existing preview')
assert(table.concat(vim.fn.readfile(views[1].path),'\n'):find('Official builder refreshed content 2026.',1,true),'rebuilt page lacks new content')
vim.fn.writefile({'format: [invalid syntax'},vim.fs.joinpath(root,'_toc.yml'))
build('failed')
assert(#refreshes==1,'failed build refreshed stale product')
vim.fn.writefile(vim.fn.readfile('tests/media/book-fixture/_toc.yml'),vim.fs.joinpath(root,'_toc.yml'))
print('Official Jupyter Book 1.0.4.post1: build, changed-content refresh, syntax-error failure passed')
print('Retained QA output: '..root)
vim.cmd.qa()
