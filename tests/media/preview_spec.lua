-- nvim --headless -u NONE -l tests/media/preview_spec.lua
vim.opt.rtp:prepend(vim.fn.getcwd()..'/portable/payload/nvim')
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
p.close()
vim.g.neovide_native_preview=false
vim.notify=function() end
assert(not p.open('/tmp/a.mp3'))
print('preview lifecycle/bounds/late status/zoom: PASS')
vim.cmd.qa()
