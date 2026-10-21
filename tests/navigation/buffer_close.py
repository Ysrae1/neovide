#!/usr/bin/env python3
"""Real pinned NvChad close handler and Neovim confirmation; no user GUI/data.

GLOW_TEST_CONFIG=/path/to/nvim python tests/navigation/buffer_close.py
Requires pynvim and the existing ui plugin in GLOW_TEST_DATA/lazy/ui (defaults
to ~/.local/share/nvim); never installs or edits plugins.
"""
import json
import os
from pathlib import Path
import tempfile

import pynvim


FIXTURE = r'''
local config, plugin, path, case = ...
vim.opt.rtp = {config, plugin, vim.env.VIMRUNTIME}
vim.o.hidden = true
local api = vim.api
local tabs = require('nvchad.tabufline')
local compat = require('config.navigation.buffer_close')
compat.setup()
local first = tabs.close_buffer
compat.setup()
assert(tabs.close_buffer == first, 'setup must be idempotent')
local target = api.nvim_get_current_buf()
api.nvim_buf_set_name(target, path)
api.nvim_buf_set_lines(target, 0, -1, false, {'first line', 'unsaved contents', 'last line'})
vim.bo[target].modified = true
api.nvim_win_set_cursor(0, {2, 3})
local before = {lines=api.nvim_buf_get_lines(target, 0, -1, false), tick=vim.b.changedtick,
  view=vim.fn.winsaveview(), current=target}
local neighbor = api.nvim_create_buf(true, false)
api.nvim_buf_set_name(neighbor, path .. '.neighbor')
local tail = api.nvim_create_buf(true, false)
api.nvim_buf_set_name(tail, path .. '.tail')
vim.t.bufs = {target, neighbor, tail}
local answer
local close = function() return tabs.close_buffer(target) end
if case == 'wipe' or case == 'delete' or case == 'clean' then
  vim.bo[target].modified = false
  if case ~= 'clean' then vim.bo[target].bufhidden = case end
elseif case == 'cancel' or case == 'last_cancel' then
  answer = 'c'
  if case == 'last_cancel' then
    api.nvim_buf_delete(neighbor, {})
    api.nvim_buf_delete(tail, {})
    vim.t.bufs = {target}
  end
elseif case == 'escape' then answer = '\27'
elseif case == 'save' or case == 'write_failure' then answer = 'y\r'
elseif case == 'discard' then answer = 'n'
elseif case == 'silent_writer' then
  api.nvim_create_autocmd('BufWriteCmd', {buffer=target, callback=function() end})
  answer = 'y\r'
elseif case == 'notebook_cancel' then
  local dirty = require('config.media.notebook_dirty')
  dirty.attach(target); dirty.changed(target)
  answer = 'c'
elseif case == 'batch_cancel' or case == 'direction_cancel' then
  api.nvim_set_current_buf(neighbor)
  before.current, before.view = neighbor, vim.fn.winsaveview()
  vim.t.bufs = {neighbor, target, tail}
  close = case == 'batch_cancel' and function() return tabs.closeAllBufs(false) end
    or function() return tabs.closeBufs_at_direction('right') end
  answer = 'c'
elseif case == 'delete_failure' then
  vim.bo[target].modified = false
  api.nvim_create_autocmd('BufDelete', {buffer=target, callback=function() error('delete-fixture-failure') end})
else error('unknown fixture') end
local listed_before = vim.fn.getbufinfo({buflisted=1})
if answer then api.nvim_feedkeys(answer, 'nt', false) end
local ok, result = pcall(close)
if case == 'write_failure' or case == 'delete_failure' then
  assert(not ok, 'genuine errors must not be swallowed')
  assert(tostring(result):find(case == 'write_failure' and 'E212' or 'delete%-fixture%-failure'), result)
else
  assert(ok, tostring(result))
end
local valid = api.nvim_buf_is_valid(target)
local closed = not valid or (not api.nvim_buf_is_loaded(target) and not vim.bo[target].buflisted)
if case == 'wipe' or case == 'delete' or case == 'clean' or case == 'save' or case == 'discard' then
  assert(closed, 'successful close must unload and unlist')
  if case == 'wipe' then
    assert(tabs.close_buffer(target) == true, 'queued stale click must be harmless')
  end
elseif case ~= 'delete_failure' then
  assert(not closed and vim.bo[target].modified, 'retain all unsaved state')
  assert(vim.deep_equal(api.nvim_buf_get_lines(target, 0, -1, false), before.lines), 'source changed')
  assert(api.nvim_buf_get_changedtick(target) == before.tick, 'source changedtick changed')
  if case ~= 'write_failure' then
    assert(result == false, 'aborted close must not report success')
    assert(api.nvim_get_current_buf() == before.current, 'restore original active file')
    assert(vim.deep_equal(vim.fn.winsaveview(), before.view), 'restore cursor and scroll')
  end
  if case == 'last_cancel' then
    assert(#vim.fn.getbufinfo({buflisted=1}) == #listed_before, 'do not leave an extra empty tab')
  end
  if case == 'batch_cancel' or case == 'direction_cancel' then
    assert(api.nvim_buf_is_loaded(tail) and vim.bo[tail].buflisted, 'stop batch at first aborted close')
  end
  if case == 'notebook_cancel' then
    assert(vim.b[target].glow_notebook_output_dirty and require('config.media.notebook_dirty').status(target).dirty,
      'retain unsaved Notebook output protection')
  end
end
return {case=case, closed=closed, error=ok and '' or tostring(result),
  messages=api.nvim_exec2('messages', {output=true}).output}
'''


def main():
    config = Path(os.environ['GLOW_TEST_CONFIG']).expanduser().resolve()
    data = Path(os.environ.get('GLOW_TEST_DATA', Path.home() / '.local/share/nvim'))
    plugin = data / 'lazy/ui'
    assert (plugin / 'lua/nvchad/tabufline/init.lua').is_file(), plugin
    cases = ['wipe', 'delete', 'clean', 'cancel', 'escape', 'last_cancel', 'save', 'discard',
             'write_failure', 'silent_writer', 'notebook_cancel', 'batch_cancel', 'direction_cancel', 'delete_failure']
    results = []
    with tempfile.TemporaryDirectory(prefix='glow-buffer-close-') as temporary:
        for case in cases:
            editor = pynvim.attach('child', argv=[os.environ.get('GLOW_NVIM', 'nvim'), '--clean', '--embed', '--headless', '-n'])
            editor.ui_attach(90, 30, rgb=True, ext_linegrid=True)
            path = Path(temporary) / ('missing/failed.txt' if case == 'write_failure' else case + '.txt')
            try:
                result = editor.exec_lua(FIXTURE, str(config), str(plugin), str(path), case)
                assert path.exists() == (case == 'save'), (case, 'unexpected file write')
                if case == 'save':
                    assert path.read_text() == 'first line\nunsaved contents\nlast line\n'
                results.append(result)
            finally:
                try:
                    editor.command('qa!')
                except (EOFError, OSError):
                    pass
                editor.close()
    print(json.dumps({'config': str(config), 'passed': len(results), 'results': results}, ensure_ascii=False))


if __name__ == '__main__':
    main()
