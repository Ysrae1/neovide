#!/usr/bin/env python3
"""Native screen rendering and edit reveal in an isolated real Neovim UI.

Run with ~/.local/share/nvim/glow-notebook-venv/bin/python. Uses the pinned
render-markdown plugin and installed Python/Markdown Treesitter parsers.
"""
from pathlib import Path
import sys
import time

import pynvim
import jupytext

ROOT = Path(__file__).resolve().parents[2]
DATA = Path.home() / '.local/share/nvim/lazy'
source = [
    '# %%', 'answer = 42',
    '# %% [markdown]', '# # Native heading',
    '# Plain **bold** and *italic*, `code`, [link](https://example.com).',
    '# - list item', '# ```python', '# print("inside fence")', '# ```',
    '# %% [markdown]', '# ## Other heading', '# Other **bold** cell',
    '# %%', 'print(answer)',
]
nvim = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
try:
    nvim.ui_attach(110, 35, rgb=True, ext_linegrid=True)
    nvim.exec_lua('vim.opt.rtp:prepend(...)', str(ROOT / 'portable/payload/nvim'))
    for plugin in ['render-markdown.nvim', 'nvim-treesitter']:
        nvim.exec_lua('vim.opt.rtp:append(...)', str(DATA / plugin))
    nvim.exec_lua("""
      vim.o.termguicolors=true;vim.o.showmode=false;vim.o.laststatus=0;vim.o.ruler=false
      vim.api.nvim_set_hl(0,'Normal',{fg=0xd8dee9,bg=0x242933})
      vim.api.nvim_set_hl(0,'Comment',{fg=0x667080,italic=true})
      vim.api.nvim_set_hl(0,'Title',{fg=0x88c0d0,bold=true})
      _md=require('config.media.notebook_markdown')
      require('render-markdown').setup(_md.options({file_types={'markdown','Avante'}}))
      _ui_refreshes=0
      package.loaded['config.media.notebook_ui']={refresh=function()_ui_refreshes=_ui_refreshes+1 end}
    """)
    buf = nvim.current.buffer.number
    nvim.current.buffer[:] = source
    nvim.current.buffer.options['filetype'] = 'python'
    nvim.current.buffer.options['modified'] = False
    original_options = {name: nvim.current.buffer.options[name] for name in ('comments', 'formatoptions')}
    nvim.exec_lua("""
      vim.b.glow_notebook_edit=true
      vim.treesitter.start(0,'python')
      _output_ns=vim.api.nvim_create_namespace('test-molten-output')
      vim.api.nvim_buf_set_extmark(0,_output_ns,1,0,{virt_lines={{{'Out[1]: Done','Normal'}},{{'42','Normal'}}}})
      _output=vim.api.nvim_buf_get_extmarks(0,_output_ns,0,-1,{details=true})
      assert(_md.attach(vim.api.nvim_get_current_buf()))
    """)
    # The run key submits Markdown to its renderer, without entering kernel setup.
    nvim.exec_lua("""
      local original_refresh,original_notify=_md.refresh,vim.notify
      local cursor=vim.api.nvim_win_get_cursor(0)
      local calls=0
      _md.refresh=function(buf) assert(buf==vim.api.nvim_get_current_buf());calls=calls+1 end
      vim.notify=function(message) error('unexpected Markdown run notification: '..message) end
      vim.api.nvim_win_set_cursor(0,{4,2})
      local ok,err=pcall(require('config.media.notebook_edit').run)
      _md.refresh,vim.notify=original_refresh,original_notify
      vim.api.nvim_win_set_cursor(0,cursor)
      assert(ok,err);assert(calls==1,'Markdown run must call its renderer exactly once')
      assert(vim.fn.exists(':MoltenInit')==0 and not vim.g.loaded_python3_provider,'Markdown run started a host/kernel')
    """)
    assert nvim.current.buffer[:] == source and not nvim.current.buffer.options['modified']
    if '--run-callback-only' in sys.argv:
        print('PASS: Markdown run renders once without notification, host, kernel, or source changes')
        raise SystemExit(0)

    def wait(predicate, label):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.02)
        raise AssertionError(label + ': ' + nvim.command_output('messages'))

    def screen():
        return nvim.exec_lua(r"""
          vim.cmd.redraw()
          local rows={}
          for r=1,30 do local line='';for c=1,110 do line=line..vim.fn.screenstring(r,c) end;rows[#rows+1]=line end
          return table.concat(rows,'\n')
        """)

    if '--delete-keys-only' in sys.argv:
        nvim.options['backspace'] = 'indent,eol,start'
        fixture = ['# %% [markdown]', '# alpha', '# beta', '# %%', 'answer = 42']

        def delete_at(lines, row, column, key, expected, label):
            nvim.input('\x1b')
            wait(lambda: nvim.funcs.mode() == 'n', label + ' normal')
            nvim.current.buffer[:] = lines
            nvim.current.window.cursor = (row, 0)
            nvim.input('i')
            wait(lambda: nvim.funcs.mode() == 'i', label + ' Insert')
            nvim.current.window.cursor = (row, column)
            nvim.input(key)
            wait(lambda: nvim.current.buffer[:] == expected, label + ': ' + repr(nvim.current.buffer[:]))
            nvim.input('\x1b')
            wait(lambda: nvim.funcs.mode() == 'n', label + ' exit')

        delete_at(fixture, 3, 4, '<BS>',
                  ['# %% [markdown]', '# alpha', '# bta', '# %%', 'answer = 42'], 'ordinary content BS')
        joined = ['# %% [markdown]', '# alphabeta', '# %%', 'answer = 42']
        delete_at(fixture, 3, 2, '<BS>', joined, 'content-start wrapper BS join')
        converted = jupytext.reads('\n'.join(nvim.current.buffer[:]), fmt='py:percent')
        reloaded = jupytext.reads(jupytext.writes(converted, fmt='ipynb'), fmt='ipynb')
        assert reloaded.cells[0].source == 'alphabeta' and reloaded.cells[1].source == 'answer = 42'
        assert '#' not in reloaded.cells[0].source, 'joined Markdown leaked its storage wrapper'
        delete_at(fixture, 3, 0, '<BS>', joined, 'inside concealed prefix BS join')
        for wrapper in ['# ', '#']:
            blank = ['# %% [markdown]', '# alpha', wrapper, '# %%', 'answer = 42']
            delete_at(blank, 3, len(wrapper), '<BS>',
                      ['# %% [markdown]', '# alpha', '# %%', 'answer = 42'], 'empty wrapper BS ' + repr(wrapper))
        for column in [0, 1, 2]:
            delete_at(fixture, 2, column, '<BS>', fixture, 'first Markdown row protection ' + str(column))
        delete_at(fixture, 2, len('# alpha'), '<Del>', joined, 'EOL Del wrapper join')
        delete_at(fixture, 2, 3, '<Del>',
                  ['# %% [markdown]', '# apha', '# beta', '# %%', 'answer = 42'], 'ordinary content Del')
        delete_at(fixture, 3, len('# beta'), '<Del>', fixture, 'last Markdown row marker protection')
        delete_at(fixture, 5, len('answer = 42'), '<BS>',
                  ['# %% [markdown]', '# alpha', '# beta', '# %%', 'answer = 4'], 'code cell native BS')
        nvim.exec_lua('vim.b.glow_notebook_edit=false')
        delete_at(['abc'], 1, 2, '<BS>', ['ac'], 'non-Notebook native BS')
        assert nvim.funcs.exists(':MoltenInit') == 0
        print('PASS: real Insert BS/Del removes hidden Markdown wrappers once; empty/bare/content joins; cell-marker protection; code/non-Notebook fallback; ipynb roundtrip without #')
        raise SystemExit(0)

    wait(lambda: nvim.exec_lua('return _md.presentation_revision(...)', buf) > 0, 'first render')
    rendered = screen()
    assert 'Native heading' in rendered and '# # Native heading' not in rendered, rendered
    assert 'Plain bold and italic, code, link.' in rendered, rendered
    assert '• list item' in rendered and 'https://example.com' not in rendered, rendered
    assert 'print("inside fence")' in rendered and '```' not in rendered, rendered
    nvim.exec_lua("""
      local ns=vim.api.nvim_get_namespaces()['render-markdown.nvim']
      local groups={}
      for _,m in ipairs(vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})) do
        assert((m[2]>=3 and m[2]<=8) or (m[2]>=10 and m[2]<=11),'decoration outside Markdown source')
        if m[4].hl_group then groups[m[4].hl_group]=true end
      end
      for _,name in ipairs({'Heading1','Heading2','Bold','Italic','Code','Link','Bullet','Text'}) do
        assert(groups['GlowNotebookMD'..name],'missing style '..name)
        assert(not vim.api.nvim_get_hl(0,{name='GlowNotebookMD'..name}).bg,'opaque style '..name)
      end
      assert(vim.api.nvim_get_hl(0,{name='GlowNotebookMDText'}).fg==0xd8dee9)
      assert(vim.api.nvim_get_hl(0,{name='GlowNotebookMDBold'}).bold)
      assert(vim.api.nvim_get_hl(0,{name='GlowNotebookMDItalic'}).italic)
    """)
    revision = nvim.exec_lua('return _md.presentation_revision(...)', buf)
    nvim.exec_lua('for _=1,3 do _md.refresh(...) end', buf)
    time.sleep(.05)
    assert nvim.exec_lua('return _md.presentation_revision(...)', buf) == revision

    nvim.current.window.cursor = (5, 2)
    nvim.input('i')
    wait(lambda: nvim.funcs.mode() == 'i' and nvim.exec_lua('return _md.presentation_revision(...)', buf) > revision, 'insert reveal')
    editing = screen()
    assert '# Native heading' in editing and '# # Native heading' not in editing, editing
    assert 'Plain **bold** and *italic*' in editing and '# Plain' not in editing and 'https://example.com' in editing, editing
    assert nvim.current.buffer.options['comments'] == 'b:#' and 'r' in nvim.current.buffer.options['formatoptions']
    assert 'Other heading' in editing and '# ## Other heading' not in editing and 'Other bold cell' in editing, editing
    nvim.input('\x1b')
    wait(lambda: nvim.funcs.mode() == 'n' and '**bold**' not in screen(), 'normal rerender')
    nvim.input('v')
    wait(lambda: nvim.funcs.mode() == 'v' and '**bold**' in screen(), 'visual reveal')
    assert '# # Native heading' not in screen() and '# Plain' not in screen(), 'Visual exposes Markdown without its storage wrapper'
    nvim.input('\x1b')
    wait(lambda: nvim.funcs.mode() == 'n' and '**bold**' not in screen(), 'visual exit rerender')
    assert nvim.current.buffer[:] == source and not nvim.current.buffer.options['modified']
    assert all(nvim.current.buffer.options[name] == value for name, value in original_options.items())
    nvim.exec_lua("""
      assert(vim.deep_equal(_output,vim.api.nvim_buf_get_extmarks(0,_output_ns,0,-1,{details=true})),
        'Markdown rendering changed output marks')
      assert(_ui_refreshes==_md.presentation_revision(vim.api.nvim_get_current_buf()),'UI invalidation count')
    """)
    # Exercise the real frame cache as conceal changes a wrapped source line.
    nvim.ui_try_resize(60, 35)
    nvim.exec_lua("""
      package.loaded['config.media.notebook_ui']=nil
      vim.g.neovide_native_notebook=true;vim.g.neovide_channel_id=77
      _frames={};vim.rpcnotify=function(_,method,frames)
        assert(method=='neovide.notebook.frames');_frames=vim.deepcopy(frames);return true end
      _ui=require('config.media.notebook_ui');assert(_ui.attach(vim.api.nvim_get_current_buf()))
      _md.refresh(vim.api.nvim_get_current_buf());_ui.refresh()
    """)

    def markdown_frame():
        return nvim.exec_lua("for _,f in ipairs(_ui.refresh()) do if f.kind=='input' and f.cell==2 then return f end end")

    wait(lambda: bool(markdown_frame()), 'native Markdown frame')
    normal = markdown_frame()
    normal_position = nvim.exec_lua("return {first=vim.fn.screenpos(0,4,1).row,last=vim.fn.screenpos(0,9,1).row}")
    revision = nvim.exec_lua('return _md.presentation_revision(...)', buf)
    nvim.exec_lua('_md.refresh(...)', buf)
    time.sleep(.04)
    assert markdown_frame()['anchor']['epoch'] == normal['anchor']['epoch'], 'unchanged render invalidated frame'
    nvim.input('i')
    wait(lambda: nvim.funcs.mode() == 'i' and nvim.exec_lua('return _md.presentation_revision(...)', buf) > revision,
         'wrapped source reveal revision')
    revealed = markdown_frame()
    revealed_position = nvim.exec_lua("return {first=vim.fn.screenpos(0,4,1).row,last=vim.fn.screenpos(0,9,1).row}")
    assert revealed['anchor']['epoch'] != normal['anchor']['epoch'], (normal, revealed)
    measured_delta = (revealed_position['last'] - revealed_position['first']) - (normal_position['last'] - normal_position['first'])
    assert abs(revealed['rect']['height'] - normal['rect']['height'] - measured_delta) < .01, (normal, revealed, normal_position, revealed_position)
    nvim.input('\x1b')
    wait(lambda: nvim.funcs.mode() == 'n' and markdown_frame()['rect']['height'] == normal['rect']['height'],
         'concealed Markdown frame restores measured height')
    assert nvim.current.buffer[:] == source and not nvim.current.buffer.options['modified']
    # Native comment continuation is scoped to the active Markdown Insert mode.
    # Empty '# ' and Jupytext's bare '#' both retain a hidden storage wrapper.
    nvim.command('enew')
    continuation = nvim.current.buffer.number
    nvim.current.buffer[:] = ['# %% [markdown]', '# first', '# ', '#', '# %%', 'code_value = 42']
    nvim.current.buffer.options['filetype'] = 'python'
    continuation_options = {name: nvim.current.buffer.options[name] for name in original_options}
    nvim.exec_lua('vim.b.glow_notebook_edit=true;assert(_md.attach(vim.api.nvim_get_current_buf()))')
    nvim.current.window.cursor = (2, 2)
    nvim.input('A')
    wait(lambda: nvim.funcs.mode() == 'i', 'Markdown continuation Insert')
    nvim.input('\r')
    wait(lambda: nvim.current.window.cursor == (3, 2), 'first Markdown CR cursor')
    assert nvim.current.buffer[2] == '# '
    nvim.input('\r')
    wait(lambda: nvim.current.window.cursor == (4, 2), 'empty Markdown CR cursor')
    assert nvim.current.buffer[3] == '# '
    nvim.input('\x1b')
    wait(lambda: nvim.funcs.mode() == 'n', 'continuation exit')
    bare_row = nvim.current.buffer[:].index('#') + 1
    nvim.current.window.cursor = (bare_row, 0)
    nvim.input('A\r')
    wait(lambda: nvim.funcs.mode() == 'i' and nvim.current.window.cursor[0] == bare_row + 1, 'bare wrapper CR')
    assert nvim.current.buffer[bare_row] == '#'
    nvim.input('bare')
    wait(lambda: nvim.current.buffer[bare_row] == '#bare', 'typing after hidden bare wrapper')
    wait(lambda: 'bare' in screen() and '#bare' not in screen(), 'typed Markdown wrapper concealed')
    nvim.input('\x1b')
    wait(lambda: nvim.funcs.mode() == 'n', 'bare continuation exit')
    assert all(nvim.current.buffer.options[name] == value for name, value in continuation_options.items())
    converted = jupytext.reads('\n'.join(nvim.current.buffer[:]), fmt='py:percent')
    assert converted.cells[0].cell_type == 'markdown' and 'first' in converted.cells[0].source and 'bare' in converted.cells[0].source
    assert '#bare' not in converted.cells[0].source, 'saved Markdown must omit its storage wrapper'
    code_row = nvim.current.buffer[:].index('code_value = 42') + 1
    nvim.current.window.cursor = (code_row, 0)
    nvim.input('A\r')
    wait(lambda: nvim.funcs.mode() == 'i' and nvim.current.window.cursor[0] == code_row + 1, 'ordinary code CR')
    assert nvim.current.buffer[code_row] == '' and nvim.current.window.cursor[1] == 0
    assert all(nvim.current.buffer.options[name] == value for name, value in continuation_options.items())
    nvim.input('\x1b')
    wait(lambda: nvim.funcs.mode() == 'n', 'code continuation exit')
    nvim.command('enew')
    nvim.current.buffer[:] = source
    nvim.current.buffer.options['filetype'] = 'python'
    assert not nvim.exec_lua('return _md.attach(vim.api.nvim_get_current_buf())')
    assert all(nvim.current.buffer.options[name] == value for name, value in continuation_options.items())
    nvim.exec_lua("""
      local ns=vim.api.nvim_get_namespaces()['render-markdown.nvim']
      assert(#vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{})==0)
      assert(_md.presentation_revision(vim.api.nvim_get_current_buf())==0)
    """)
    print('PASS: native Markdown styles/edit reveal with hidden storage wrapper; CR continuation/cursor/Jupytext roundtrip; restored code/ordinary-Python options; stable frame/source/output')
finally:
    try:
        nvim.command('qa!')
    except Exception:
        pass
