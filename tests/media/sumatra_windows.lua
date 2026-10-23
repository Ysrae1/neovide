-- Windows only: actual VimTeX dispatch and minimal inverse client, no GUI.
-- Use fixture from synctex_cross_platform.lua; GLOW_TEST_CONFIG/VIMTEX/WORKROOT.
local config, work = assert(vim.env.GLOW_TEST_CONFIG), assert(vim.env.GLOW_TEST_WORKROOT)
vim.opt.rtp = { config, assert(vim.env.GLOW_TEST_VIMTEX), vim.env.VIMRUNTIME }
local receipt = { state = 'started', gui_verified = false }
local function save() vim.fn.writefile({ vim.json.encode(receipt) }, work .. '/sumatra-rpc-receipt.json') end
local ok, err = xpcall(function()
  assert(vim.fn.has('win32') == 1, 'Windows native process required')
  local main, source = work .. "/main document's.tex", work .. "/chapter source's 中文.tex"
  local pdf = work .. "/build output/main document's.pdf"
  assert(vim.fn.filereadable(pdf) == 1, 'Compile fixture first')
  local spec = dofile(config .. '/lua/plugins/languages/vimtex.lua'); spec.init()
  assert(vim.g.vimtex_view_method == 'sumatra_async')
  local compiler = vim.g.vimtex_compiler_latexmk
  compiler.out_dir = 'build output'; vim.g.vimtex_compiler_latexmk = compiler
  vim.g.neovide_native_pdf_synctex = false
  vim.g.neovide_native_preview = true
  vim.g.neovide_channel_id = 77
  local notices = {}
  vim.notify = function(text) notices[#notices + 1] = text end
  vim.cmd('filetype plugin on')
  vim.cmd.cd(work); vim.cmd.edit(main); vim.cmd.edit(source)
  vim.api.nvim_win_set_cursor(0, { 3, 7 })
  local sumatra = require('config.latex.sumatra')
  assert(sumatra.executable(), 'Sumatra not detected')
  receipt.viewer = sumatra.executable()
  local launches, system = {}, vim.system
  vim.system = function(argv, opts) launches[#launches + 1] = argv; return { pid = 0 } end
  vim.cmd('VimtexView')
  require('config.media.synctex').setup(); vim.cmd('GlowTexForward')
  vim.system = system
  assert(#launches == 2, 'VimtexView/GlowTexForward did not dispatch: ' .. vim.inspect(notices))
  local args = launches[1]
  assert(args[1] == sumatra.executable() and args[5] == '-inverse-search' and args[7] == '-forward-search', vim.inspect(args))
  assert(args[8] == vim.api.nvim_buf_get_name(0) and args[9] == '3' and args[10]:gsub('\\', '/') == pdf:gsub('\\', '/'), vim.inspect(args))
  assert(args[6]:find(vim.v.servername, 1, true) and args[6]:find('"%f" %l %c', 1, true), args[6])
  receipt.forward_argv, receipt.forward_entrypoints = args, { 'VimtexView', 'GlowTexForward' }
  local server = '\\\\.\\pipe\\glow-sumatra-unrelated-' .. vim.fn.getpid()
  local other = vim.system({ vim.v.progpath, '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '--listen', server,
    '-c', 'lua _G.glow_foreign_hits=0' }, { text = true })
  receipt.other_pid = other.pid
  local channel
  assert(vim.wait(5000, function() local yes, c = pcall(vim.fn.sockconnect, 'pipe', server, { rpc = true }); if yes and c > 0 then channel = c; return true end end, 30), 'other instance unavailable')
  local dirt = work .. '/unsaved rpc draft.txt'
  vim.cmd.edit(dirt); vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'Keep this user draft.' })
  local dirtybuf = vim.api.nvim_get_current_buf(); vim.o.hidden = false
  local client = config .. '/lua/config/latex/sumatra_inverse.lua'
  local done
  vim.system({ vim.v.progpath, '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '-l', client,
    vim.v.servername, source, '3', '5' }, { text = true, timeout = 10000 }, function(result) done = result end)
  assert(vim.wait(12000, function() return done ~= nil end, 20), 'inverse client did not finish')
  assert(done.code == 0, vim.inspect(done))
  assert(vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == vim.fs.normalize(vim.uv.fs_realpath(source)) and vim.api.nvim_win_get_cursor(0)[1] == 3, 'inverse cursor did not return')
  assert(vim.bo[dirtybuf].modified and vim.api.nvim_buf_get_lines(dirtybuf, 0, -1, false)[1] == 'Keep this user draft.', 'draft was lost')
  assert(vim.rpcrequest(channel, 'nvim_exec_lua', 'return _G.glow_foreign_hits', {}) == 0, 'unrelated instance touched')
  receipt.inverse = { code = done.code, source = vim.api.nvim_buf_get_name(0), line = vim.api.nvim_win_get_cursor(0)[1],
    column = vim.api.nvim_win_get_cursor(0)[2] + 1, unsaved_buffer_preserved = true, unrelated_instance_untouched = true }
  pcall(vim.rpcnotify, channel, 'nvim_command', 'qa!'); pcall(vim.fn.chanclose, channel)
  local stopped = other:wait(3000); if stopped.code == 124 then pcall(other.kill, other, 9) end
  receipt.other_exit_code = stopped.code
  assert(stopped.code == 0, 'other instance did not stop')
  receipt.state = 'passed'
end, debug.traceback)
if not ok then receipt.state = 'failed'; receipt.error = err end
save()
if not ok then error(err) end
print('PASS actual VimTeX/GlowTexForward argv, native ARM64 viewer detection, real inverse RPC to originating instance, Unicode/space/apostrophe path, unsaved draft and unrelated instance protected; GUI not tested')
vim.cmd('qa!')
