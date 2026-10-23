-- Real XeLaTeX/SyncTeX CLI + Neovim RPC routing, with no native GUI launch.
-- GLOW_TEST_CONFIG, GLOW_TEST_VIMTEX and a fresh GLOW_TEST_WORKROOT are required.
-- Optional GLOW_TEST_XELATEX/GLOW_TEST_SYNCTEX override commands. Fixture only.
local config = assert(vim.env.GLOW_TEST_CONFIG)
local work = assert(vim.env.GLOW_TEST_WORKROOT)
local vimtex = assert(vim.env.GLOW_TEST_VIMTEX)
vim.opt.rtp = { config, vimtex, vim.env.VIMRUNTIME }
vim.o.swapfile = false
local receipt = { state = 'started', config = config, nvim = vim.version(), gui_verified = false }
local function save()
  vim.fn.writefile({ vim.json.encode(receipt) }, work .. '/receipt.json')
end
local function wait_for(check, label)
  assert(vim.wait(12000, check, 20), label .. ': ' .. vim.inspect(_G.notices))
end
local ok, err = xpcall(function()
  assert(vim.fn.isdirectory(work) == 0, 'Use a fresh work root')
  vim.fn.mkdir(work .. '/build output', 'p')
  local main = work .. "/main document's.tex"
  local source = work .. "/chapter source's 中文.tex"
  local pdf = work .. "/build output/main document's.pdf"
  vim.fn.writefile({ '\\documentclass{article}', '\\begin{document}',
    "\\input{chapter source's 中文.tex}", '\\newpage', 'Second page.', '\\end{document}' }, main)
  vim.fn.writefile({ 'First paragraph.', '', 'The exact synchronization target is this sentence.', '', 'Last paragraph.' }, source)
  local xelatex = vim.env.GLOW_TEST_XELATEX or vim.fn.exepath('xelatex')
  assert(xelatex ~= '', 'XeLaTeX is required')
  local compile = vim.system({ xelatex, '-interaction=nonstopmode', '-halt-on-error', '-synctex=1',
    '-output-directory=build output', vim.fs.basename(main) }, { cwd = work, text = true, timeout = 45000 }):wait()
  vim.fn.writefile(vim.split(compile.stdout or '', '\n', { plain = true }), work .. '/compile.stdout')
  assert(compile.code == 0, 'XeLaTeX failed: ' .. (compile.stderr or ''))
  assert(vim.fn.filereadable(pdf) == 1, 'PDF missing')
  receipt.compile = { code = compile.code, pdf = pdf, synctex = pdf:gsub('%.pdf$', '.synctex.gz') }
  vim.g.glow_synctex_executable = vim.env.GLOW_TEST_SYNCTEX
  vim.g.vimtex_compiler_latexmk = { out_dir = 'build output' }
  vim.g.vimtex_view_method = 'skim_async'
  vim.g.neovide_native_preview = true
  vim.g.neovide_native_pdf_synctex = true -- isolated protocol peer, not native capability proof
  vim.g.neovide_channel_id = 77
  _G.calls, _G.notices = {}, {}
  vim.rpcnotify = function(_, method, ...) _G.calls[#_G.calls + 1] = { method, ... }; return true end
  vim.notify = function(message) _G.notices[#_G.notices + 1] = message end
  require('config.media.preview').setup()
  vim.cmd('filetype plugin on')
  vim.cmd.cd(work)
  vim.cmd.edit(main)
  vim.cmd.edit(source)
  local sourcewin = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(sourcewin, { 3, 7 })
  local synctex = require('config.media.synctex')
  assert(synctex.forward(), 'forward refused')
  local point
  wait_for(function()
    for _, c in ipairs(_G.calls) do if c[1] == 'neovide.preview.pdf_sync' then point = c[3]; return true end end
  end, 'forward RPC')
  assert(point.page == 1 and point.width > 0 and point.height > 0, vim.inspect(point))
  assert(vim.api.nvim_get_current_win() == sourcewin, 'source focus changed')
  receipt.forward_rpc = point
  local query = vim.system({ vim.g.glow_synctex_executable or vim.fn.exepath('synctex'), 'edit', '-o',
    ('%d:%.8f:%.8f:%s'):format(point.page, point.x, point.y, pdf) },
    { cwd = vim.fs.dirname(pdf), text = true, timeout = 10000, env = { SYNCTEX_VIEWER = '', SYNCTEX_EDITOR = '' } }):wait()
  vim.fn.writefile(vim.split(query.stdout or '', '\n', { plain = true }), work .. '/inverse.stdout')
  assert(query.code == 0, 'inverse CLI failed')
  local parsed = assert(synctex.parse(query.stdout, 'edit'))
  receipt.inverse_cli = parsed
  assert(parsed.line == 3, vim.inspect(parsed))
  local dirty = work .. '/unsaved buffer.txt'
  vim.cmd.edit(dirty)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'User draft must survive inverse search.' })
  local dirtybuf = vim.api.nvim_get_current_buf()
  vim.o.hidden = false
  assert(synctex.inverse(pdf, point, { win = sourcewin }), 'inverse refused')
  wait_for(function() return #_G.notices > 0 end, 'unsaved buffer refusal')
  assert(vim.api.nvim_get_current_buf() == dirtybuf and vim.bo.modified, 'unsaved current buffer lost')
  assert(vim.api.nvim_buf_get_lines(dirtybuf, 0, -1, false)[1] == 'User draft must survive inverse search.', 'unsaved draft altered')
  receipt.unsaved_buffer_preserved = true
  vim.o.hidden = true
  _G.notices = {}
  assert(synctex.inverse(pdf, point, { win = sourcewin }), 'second inverse refused')
  wait_for(function() return vim.api.nvim_get_current_buf() ~= dirtybuf end, 'inverse source open')
  assert(vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == vim.fs.normalize(vim.uv.fs_realpath(source)), 'incorrect source path: ' .. vim.api.nvim_buf_get_name(0))
  assert(vim.api.nvim_win_get_cursor(0)[1] == 3, 'incorrect source line')
  assert(vim.bo[dirtybuf].modified, 'hidden unsaved buffer lost')
  receipt.inverse_source = vim.api.nvim_buf_get_name(0)
  receipt.inverse_line = vim.api.nvim_win_get_cursor(0)[1]
  vim.g.neovide_native_pdf_synctex = false
  assert(not synctex.forward(), 'unsupported native backend should refuse coordinate search')
  receipt.unsupported_backend_rejected = true
  receipt.state = 'passed'
end, debug.traceback)
if not ok then receipt.state = 'failed'; receipt.error = err end
save()
if not ok then error(err) end
print('PASS real XeLaTeX/SyncTeX source/PDF RPC, absolute source paths, separate output, Unicode/spaces/apostrophe, unsaved-buffer protection; native GUI not tested')
vim.cmd('qa!')
