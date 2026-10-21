-- nvim --headless -u NONE -l tests/media/preview_spec.lua
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or (vim.fn.getcwd()..'/portable/payload/nvim'))
require("config.platform.locale").set_lang("en", { save = false, silent = true })
vim.g.neovide_native_preview=true
vim.g.neovide_channel_id=77
local sent={}
vim.rpcnotify=function(channel,method,...) assert(channel==77); sent[#sent+1]={method=method,args={...}}; return true end
local p=require('config.media.preview')
local function last(method)
  for i=#sent,1,-1 do if sent[i].method=='neovide.preview.'..method then return sent[i] end end
end
assert(p.kind('x.MP4')=='video' and p.kind('x.flac')=='audio' and p.kind('x.html')=='web')
local disposed=0
assert(p.open('/tmp/media with space.mp4',{kind='video',on_close=function() disposed=disposed+1 end}))
local win=vim.api.nvim_get_current_win()
local id=last('open').args[1]
local rect=last('show').args[2]
assert(rect.height>0 and rect.col>=0 and rect.row>0,'viewport excludes winbar')
p.on_status(id,vim.json.encode({state='paused',position=12,duration=30,volume=.4}))
p.seek(-100); assert(last('action').args[3]==0)
p.seek(100); assert(last('action').args[3]==30)
p.volume(100); assert(last('action').args[3]==1)
vim.cmd.tabnew(); vim.wait(30); assert(last('close').args[1]==id)
p.on_status(id,vim.json.encode({state='playing',position=20,duration=30})) -- ignored late response
vim.cmd.tabprevious(); vim.wait(30)
local reopened=last('open').args[1]; assert(reopened~=id)
p.on_status(reopened,vim.json.encode({state='paused',position=0,duration=30,volume=1}))
assert(last('action').args[2]=='seek' and last('action').args[3]==12,'return restores last saved position')
assert(disposed==0,'tab leave must preserve descriptor')
p.close(); assert(disposed==1,'close disposes once')
assert(not vim.api.nvim_win_is_valid(win),'split closed')
assert(p.open('/tmp/index.html',{kind='web'})); local webid=last('open').args[1]
p.zoom(100); assert(last('action').args[3]==5)
p.zoom(.0001); assert(last('action').args[3]==.25)
p.refresh_source('/tmp/index.html'); vim.wait(30); assert(last('open').args[1]~=webid)
local shown
vim.notify=function(message) shown=message end
local current_web=last('open').args[1]
p.on_status(current_web,vim.json.encode({state='ready',url='file:///tmp/index.html',read_root='/private/tmp'}))
assert(p.info():find('/private/tmp',1,true) and shown:find('including subfolders',1,true),'local read scope is visible on request')
p.on_status(current_web,vim.json.encode({state='ready',url='https://example.invalid',read_root=''}))
assert(p.info():find('No local folder access has been granted.',1,true),'remote preview never inherits an implied directory grant')
p.close()
-- Pure title uses the real shared capsule formatter; no PDF file is read.
local pdf={kind='pdf',title='duplicate-name.pdf',status={state='ready',page=2,pages=2,zoom=.7}}
local function rendered(view,width)
  return vim.api.nvim_eval_statusline(p.render_title(view,width),{winid=vim.api.nvim_get_current_win(),use_winbar=true,maxwidth=width,highlights=true})
end
local wide=rendered(pdf,130)
assert(wide.str:find('PDF  2/2 · 70%',1,true) and wide.str:find('PAGE  [p ]p',1,true))
assert(wide.str:find('ZOOM  + − · 0',1,true) and wide.str:find('FOCUS  i',1,true) and wide.str:find('CLOSE  q',1,true))
assert(not wide.str:find('duplicate%-name') and not wide.str:find('已就绪',1,true))
assert(not wide.str:find(' ',1,true) and not wide.str:find(' ',1,true),'caps touch their values')
for _,width in ipairs({80,64,40,24,12,1}) do
  local small=rendered(pdf,width)
  assert(small.width<=width and not small.str:find('<',1,true),'title budget at '..width)
  assert(small.str:find('q',1,true),'close remains visible at '..width)
end
local failure=rendered({kind='pdf',status={state='error',page=2,pages=2,zoom=.7}},130)
assert(failure.str:find('ERROR',1,true) and failure.str:find('RETRY  r',1,true))
assert(p.open('/tmp/title-only.pdf',{kind='pdf'}))
local pdfid=last('open').args[1]
p.on_status(pdfid,vim.json.encode(pdf.status))
assert(vim.wo.winbar==p.render_title({kind='pdf',status=pdf.status},vim.api.nvim_win_get_width(0)))
assert(p.status().page==2 and p.status().pages==2 and p.status().zoom==.7)
for _,background in ipairs({'dark','light'}) do
  vim.o.background=background;vim.api.nvim_exec_autocmds('ColorScheme',{pattern='preview-title-test'})
  local cap=vim.api.nvim_get_hl(0,{name='GlowMediaInfoCap',link=false})
  local body=vim.api.nvim_get_hl(0,{name='GlowMediaInfo',link=false})
  assert(not cap.bg and cap.fg==body.bg,'shared capsule colors update with theme')
end
p.close()
-- Native PDF focus does not necessarily change Neovim's current source window.
-- A status callback must close only the owner identified by that preview id.
local source_win=vim.api.nvim_get_current_win()
local source_buf=vim.api.nvim_get_current_buf()
local source_q=vim.fn.maparg('q','n',false,true)
assert(p.open('/tmp/close-owner.pdf',{kind='pdf'}))
local owner_win=vim.api.nvim_get_current_win()
local owner_id=last('open').args[1]
vim.api.nvim_set_current_win(source_win)
p.close(owner_id+1000)
assert(vim.api.nvim_win_is_valid(owner_win),'unknown/late close id cannot close another preview')
p.on_status(owner_id,vim.json.encode({kind='pdf',state='ready',close_requested=true}))
assert(not vim.api.nvim_win_is_valid(owner_win) and vim.api.nvim_win_is_valid(source_win),'native request closes PDF owner only')
assert(vim.api.nvim_get_current_win()==source_win and vim.api.nvim_win_get_buf(source_win)==source_buf)
assert(last('close').args[1]==owner_id,'existing native close notification')
assert(vim.deep_equal(source_q,vim.fn.maparg('q','n',false,true)),'source macro q mapping unchanged')
p.on_status(owner_id,vim.json.encode({close_requested=true})) -- ignored late callback
vim.g.neovide_native_preview=false
vim.notify=function() end
assert(not p.open('/tmp/a.mp3'))
print('preview lifecycle/title; PDF native close targets owner and preserves source macro q: PASS')
vim.cmd.qa()
