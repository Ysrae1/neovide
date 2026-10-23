-- GLOW_TEST_CONFIG=/path/to/config GLOW_TEST_VIMTEX=/path/to/vimtex
-- nvim --headless --noplugin -u NONE -i NONE -l tests/media/native_pdf_viewer_route.lua
-- Exercises real VimTeX commands against an isolated route peer. No compiler,
-- viewer process, native PDF renderer, or physical input is exercised.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, assert(vim.env.GLOW_TEST_VIMTEX), vim.env.VIMRUNTIME }
local root = vim.fn.tempname() .. "-native-pdf-route's"
vim.fn.mkdir(root, 'p')
local has, system, state = vim.fn.has, vim.system, vim.env.XDG_STATE_HOME
local forwarded, opened, launches, notices = {}, {}, {}, {}
local synctex, preview
local original_forward, original_open
local receipt = { state = 'started', gui_verified = false, native_renderer_verified = false, routes = {} }
local ok, err = xpcall(function()
  vim.env.XDG_STATE_HOME = root .. '/state'
  -- Model the Windows capability policy while running the same route test on
  -- the developer Mac. Actual VimTeX initialization and commands stay real.
  vim.fn.has = function(name)
    if name == 'win32' then return 1 end
    if name == 'macunix' then return 0 end
    return has(name)
  end
  dofile(config .. '/lua/plugins/languages/vimtex.lua').init()
  assert(vim.g.vimtex_view_method == 'sumatra_async')
  vim.g.neovide_native_preview, vim.g.neovide_channel_id = true, 77
  vim.notify = function(message) notices[#notices + 1] = message end
  vim.system = function(argv)
    launches[#launches + 1] = argv
    return { pid = 0 }
  end
  synctex = require('config.media.synctex')
  preview = require('config.media.preview')
  original_forward, original_open = synctex.forward, preview.open
  synctex.forward = function(pdf, opts)
    forwarded[#forwarded + 1] = { pdf = pdf, opts = opts }
    return true
  end
  preview.open = function(pdf, opts)
    opened[#opened + 1] = { pdf = pdf, opts = opts }
    return true
  end
  local source, pdf = root .. '/main document.tex', root .. '/main document.pdf'
  vim.fn.writefile({ '\\documentclass{article}', '\\begin{document}', 'Route fixture.', '\\end{document}' }, source)
  vim.fn.writefile({ '%PDF-route-fixture' }, pdf)
  vim.fn.writefile({ 'route-fixture' }, root .. '/main document.synctex')
  vim.cmd('filetype plugin on')
  vim.cmd.cd(root); vim.cmd.edit(source)
  synctex.setup()
  local function check(label, capability, viewer, native, available)
    vim.g.neovide_native_pdf_synctex, vim.g.glow_tex_viewer = capability, viewer
    vim.g.glow_sumatra_executable = available and vim.v.progpath or root .. '/missing-viewer.exe'
    assert(synctex.native_enabled() == native, label .. ': incorrect capability/override')
    local before_native, before_external = #forwarded, #launches
    vim.cmd('VimtexView'); vim.cmd('GlowTexForward')
    assert(#forwarded - before_native == (native and 2 or 0), label .. ': wrong embedded route')
    assert(#launches - before_external == (native and 0 or 2), label .. ': wrong external route ' .. vim.inspect(notices))
    receipt.routes[#receipt.routes + 1] = { label = label, native = native, commands = 2 }
  end
  check('new frontend defaults to embedded without external viewer', true, nil, true, false)
  check('explicit Sumatra overrides native capability', true, 'sumatra', false, true)
  check('older frontend with capability=false uses external fallback', false, nil, false, true)
  check('older Windows frontend without capability uses external fallback', nil, nil, false, true)
  check('return from explicit Sumatra restores embedded default', true, nil, true, false)
  assert(require('config.latex.sumatra').view(pdf, false))
  assert(#opened == 1 and opened[1].opts.kind == 'pdf', 'plain embedded preview launched external viewer')
  assert(#notices == 0, vim.inspect(notices))
  receipt.plain_pdf_embedded = true
  receipt.state = 'passed'
end, debug.traceback)
vim.fn.has, vim.system, vim.env.XDG_STATE_HOME = has, system, state
if synctex then synctex.forward = original_forward end
if preview then preview.open = original_open end
vim.fn.delete(root, 'rf')
if not ok then receipt.state = 'failed'; receipt.error = err end
if vim.env.GLOW_TEST_RECEIPT then vim.fn.writefile({ vim.json.encode(receipt) }, vim.env.GLOW_TEST_RECEIPT) end
assert(ok, err)
print('PASS real VimTeX/GlowTexForward: native default, explicit Sumatra, old-Windows fallback, plain PDF routing; renderer/clicks not tested')
vim.cmd('qa!')
