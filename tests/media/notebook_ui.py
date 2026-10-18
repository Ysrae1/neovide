"""One isolated Neovim UI check for native Notebook frame geometry.
Run with the bundled Notebook environment's Python (pynvim required).
"""
from pathlib import Path
import sys
from types import SimpleNamespace
import pynvim
import msgpack

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path.home() / '.local/share/nvim/lazy/molten-nvim/rplugin/python3'))
from molten.outputbuffer import OutputBuffer
from molten.outputchunks import Output, OutputStatus, TextOutputChunk

nvim = pynvim.attach('child', argv=['nvim', '--embed', '-u', 'NONE', '-n'])
try:
    nvim.ui_attach(96, 32, rgb=True)
    nvim.exec_lua("vim.opt.rtp:prepend(...)", str(ROOT / 'portable/payload/nvim'))
    nvim.exec_lua("""
        vim.g.neovide_native_notebook=true; vim.g.neovide_channel_id=77
        _G.frames={}; vim.rpcnotify=function(_,method,frames,...)
          assert(method=='neovide.notebook.frames'); assert(select('#',...)==0,'legacy binary receives one snapshot argument')
          _G.frames=vim.deepcopy(frames); return true
        end
        vim.wo.number=true
    """)
    source = ['# ---', '# jupyter:', '#   jupytext: text_representation', '# ---', '',
              '# %%', 'print(42)', '', '# %%', 'print("next")', '',
              '# %% [markdown]', '# Documentation']
    nvim.current.buffer[:] = source
    nvim.current.buffer.options['modified'] = False
    nvim.current.buffer.options['filetype'] = 'python'
    nvim.exec_lua("""
        _G.ns=vim.api.nvim_create_namespace('molten-extmarks')
        _G.out=vim.api.nvim_buf_set_extmark(0,ns,6,0,{virt_lines={{{'Out[1]: Done','Normal'}},{{'42','Normal'}}}})
        local edit=require('config.media.notebook_edit')
        -- This isolated source buffer has no kernel/session; reuse the real
        -- formatter while providing its cell list without starting a kernel.
        edit.cell_labels=function(buf)
          local labels={}
          for index,cell in ipairs(edit.cells(buf)) do
            labels[#labels+1]={index=index,cell=cell,chunks=edit.label_chunks(cell.kind,'python',false)}
          end
          return labels
        end
        vim.api.nvim_set_hl(0,'GlowNotebookCell',{bg=0xaa7733})
        _G.ui=require('config.media.notebook_ui'); ui.attach(vim.api.nvim_get_current_buf()); ui.refresh()
    """)
    nvim.command('redraw')
    frames = nvim.exec_lua('return ui.refresh()')
    inputs = [f for f in frames if f['kind'] == 'input']
    outputs = [f for f in frames if f['kind'] == 'output']
    assert len(inputs) == 3 and len(outputs) == 1, 'cell output joins its input section'
    assert inputs[0]['join'] == 'top' and outputs[0]['join'] == 'bottom'
    assert 'join' not in inputs[1] and 'join' not in inputs[2], 'cells without output retain complete round frames'
    assert inputs[0]['active'], 'hidden metadata must not leave the current cell/cursor behind'
    assert nvim.current.buffer[:] == source, 'presentation must not edit source text'
    assert nvim.current.buffer.options['modified'] is False, 'presentation must not dirty notebook'
    raw = nvim.exec_lua('return vim.api.nvim_buf_get_extmark_by_id(0,ns,out,{details=true})')
    assert len(raw[2]['virt_lines']) == 2, 'Molten owns its exact virtual-line height'
    assert raw[2]['virt_lines'][0][0][0].startswith('Out[1]')
    assert raw[2]['virt_lines'][1][0][0] == '42', 'Molten output text unchanged'
    first_row = nvim.exec_lua('return vim.fn.screenpos(0,7,1).row-1')
    last_row = nvim.exec_lua('return vim.fn.screenpos(0,7,1).row-1')
    assert abs(inputs[0]['rect']['row'] - (first_row - .5)) < .01, (inputs, first_row)
    assert inputs[0]['color'] == 0xaa7733, 'border uses the capsule theme accent exactly'
    assert outputs[0]['color'] == nvim.exec_lua("return require('config.media.notebook_edit').output_accent()"), 'lower section uses vibrant_green'
    for frame in inputs + outputs:
        assert frame['rect']['col'] + frame['rect']['width'] <= frame['clip']['col'] + frame['clip']['width'] - 1, 'cell right edge has one-column inset'
    gaps = inputs[0]['label_gaps']
    assert len(gaps) == 2, 'type and run capsules each cut only their own top segment'
    assert gaps[1]['col'] - gaps[0]['col'] - gaps[0]['width'] >= 2, 'visible stroke connects the two capsules'
    labels = nvim.exec_lua("""local result={};local ns=vim.api.nvim_get_namespaces()['glow.notebook.layout']
      for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})) do
        if mark[4].virt_lines_above then result[#result+1]=mark end end;return result""")
    assert len(labels) == 3 and all(len(mark[3]['virt_lines']) == 1 for mark in labels), 'labels reuse one existing virtual row per cell'
    label_text = ''.join(chunk[0] for chunk in labels[0][3]['virt_lines'][0])
    assert 'python' not in label_text and 'Markdown' not in label_text and '󰼛' in label_text
    lower = outputs[0]['rect']
    assert abs(lower['row'] - (last_row + 1.5)) < .01, 'seam is centered in its own blank virtual row'
    assert abs(inputs[0]['rect']['row'] + inputs[0]['rect']['height'] - lower['row']) < .01, 'upper and lower sections share the identical seam'
    assert inputs[0]['active'] == outputs[0]['active'], 'joined sides keep matching stroke width'
    outer_bottom = lower['row'] + lower['height']
    assert abs(outer_bottom - (last_row + 2 + 2 + .2)) < .01, 'output follows the independent separator row'
    assert inputs[0]['rect']['row'] < lower['row'] < outer_bottom, 'shared seam stays inside the compound frame'
    # Inspect actual rendered lines, not only API geometry.
    screen = nvim.exec_lua("""local rows={};for r=1,15 do local text='';for c=1,40 do
      text=text..vim.fn.screenstring(r,c) end;rows[#rows+1]=text end;return rows""")
    assert not any('jupyter:' in line for line in screen), screen
    assert not any('# %%' in line for line in screen), 'cell markers are hidden without removing source'
    assert any('print(42)' in line for line in screen), screen
    def separator_snapshot():
        snapshot = nvim.exec_lua("""local a=vim.api;local rows={}
          for r=1,a.nvim_win_get_height(0) do local text='';for c=1,96 do
            text=text..vim.fn.screenstring(r,c) end;rows[r]=text end
          local ns=a.nvim_get_namespaces()['glow.notebook.separator']
          return {source=vim.fn.screenpos(0,7,1).row-1,rows=rows,
            marks=a.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})}""")
        source_row = snapshot['source']
        assert snapshot['rows'][source_row + 1].strip() == '', 'separator must occupy a genuinely empty screen row'
        assert snapshot['rows'][source_row + 2].lstrip().startswith('Out['), 'Molten header must start in the following row'
        assert len(snapshot['marks']) == 1
        assert snapshot['marks'][0][3]['right_gravity'] is False
        assert len(snapshot['marks'][0][3]['virt_lines']) == 1
        return source_row, snapshot['marks']
    separator_snapshot()
    # Multiple output marks belong to their source cell, independently of their
    # identity and proximity to the next cell. Keep one lower section each.
    nvim.exec_lua("""extra=vim.api.nvim_buf_set_extmark(0,ns,7,0,{virt_lines={
      {{'Out[2]: Done','Normal'}},{{'second','Normal'}},{{'third','Normal'}}}})
      other=vim.api.nvim_buf_set_extmark(0,ns,9,0,{virt_lines={
      {{'Out[3]: Done','Normal'}},{{'neighbor','Normal'}}}});ui.refresh()""")
    multiple = nvim.exec_lua('return ui.refresh()')
    multiple_outer = [f for f in multiple if f['kind'] == 'input']
    multiple_lower = [f for f in multiple if f['kind'] == 'output']
    assert len(multiple_outer) == 3 and len(multiple_lower) == 2
    assert [f['cell'] for f in multiple_lower] == [1, 2], 'cross-cell outputs never share a lower section'
    nvim.command('redraw')
    last_output_anchor = nvim.exec_lua('return vim.fn.screenpos(0,8,1).row-1')
    first_bottom = multiple_lower[0]['rect']['row'] + multiple_lower[0]['rect']['height']
    assert abs(first_bottom - (last_output_anchor + 1 + 3 + .2)) < .01, 'outer ends at last mark envelope in its own cell'
    assert first_bottom < multiple_outer[1]['rect']['row'], 'neighbor cell output must not stretch the preceding outer'
    nvim.exec_lua('vim.api.nvim_buf_del_extmark(0,ns,extra);vim.api.nvim_buf_del_extmark(0,ns,other);ui.refresh()')
    # Jupytext may reload this same buffer after session restoration. Replacing
    # identical text still relocates extmarks; metadata shape alone is not a
    # sufficient cache key for its conceal positions.
    # Keep the old output mark: a whole-buffer replacement moves it to EOF,
    # where the UI must leave it untouched and simply omit it until valid again.
    nvim.exec_lua("""vim.api.nvim_buf_set_lines(0,0,-1,false,...);vim.bo.modified=false""", source)
    reload_tick = nvim.api.buf_get_changedtick(0)
    reloaded = nvim.exec_lua('return ui.refresh()')
    stale_output = nvim.exec_lua('return vim.api.nvim_buf_get_extmark_by_id(0,ns,out,{details=true})')
    assert stale_output[0] >= len(source), 'regression retains a genuinely out-of-range old output mark'
    assert not any(f['kind'] == 'output' for f in reloaded), 'stale mark must not enter text-height geometry'
    concealed = nvim.exec_lua("""local ns=vim.api.nvim_get_namespaces()['glow.notebook.metadata']
      return vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})""")
    assert [mark[1] for mark in concealed] == [0, 1, 2, 3], 'same-shape reload must restore metadata marks to its actual prefix'
    assert nvim.current.buffer[:] == source and nvim.api.buf_get_changedtick(0) == reload_tick
    assert nvim.current.buffer.options['modified'] is False, 'conceal repair must not dirty the reloaded source'
    leading_blank = ['', '  '] + source
    nvim.current.buffer[:] = leading_blank
    nvim.current.buffer.options['modified'] = False
    nvim.exec_lua('ui.refresh()')
    nvim.command('redraw')
    prefixed_marks = nvim.exec_lua("""return vim.api.nvim_buf_get_extmarks(0,
      vim.api.nvim_get_namespaces()['glow.notebook.metadata'],0,-1,{details=true})""")
    assert [mark[1] for mark in prefixed_marks] == list(range(6)), 'leading blank lines must not expose serialization metadata'
    assert nvim.current.buffer[:] == leading_blank and not nvim.current.buffer.options['modified']
    nvim.current.buffer[:] = source
    nvim.current.buffer.options['modified'] = False
    nvim.exec_lua('ui.refresh()')
    restored = nvim.exec_lua("""vim.api.nvim_buf_set_extmark(0,ns,6,0,
      {id=out,virt_lines={{{'Out[1]: Done','Normal'}},{{'42','Normal'}}}});return ui.refresh()""")
    assert any(f['kind'] == 'output' and f.get('join') == 'bottom' for f in restored), 'same mark reappears when its source position becomes valid'
    nvim.exec_lua('ui.toggle_metadata(); ui.refresh()')
    nvim.command('redraw')
    assert nvim.exec_lua('return vim.fn.screenpos(0,2,1).row') > 0, 'metadata can be revealed without changing source'
    nvim.exec_lua('ui.toggle_metadata(); ui.refresh()')
    # Exercise the installed Molten implementation itself, including its real
    # delete/recreate behavior, header generation and output chunk rendering.
    # A canvas is the only stub: this text output does not contain images.
    nvim.api.buf_del_extmark(0, nvim.exec_lua('return ns'), nvim.exec_lua('return out'))
    live = OutputBuffer.__new__(OutputBuffer)
    live.nvim, live.canvas = nvim, SimpleNamespace(present=lambda: None)
    live.extmark_namespace = nvim.exec_lua('return ns')
    live.virt_hidden, live.virt_text_id = False, None
    live.displayed_status, live.output = OutputStatus.NEW, Output(1)
    live.options = SimpleNamespace(cover_empty_lines=False, virt_lines_off_by_1=False,
        virt_text_max_lines=100, output_show_exec_time=False, image_provider='none',
        limit_output_chars=0, wrap_output=True, hl=SimpleNamespace(virtual_text='Normal'))
    anchor = SimpleNamespace(bufno=nvim.current.buffer.number, lineno=6)
    for status in [OutputStatus.NEW, OutputStatus.RUNNING]:
        live.output.status = status
        previous_geometry, previous_separator, ids = None, None, set()
        for turn in range(6):
            live.output.chunks = [] if status == OutputStatus.NEW else [TextOutputChunk(str(42 + turn))]
            live.show_virtual_output(anchor)
            ids.add(live.virt_text_id)
            nvim.command('redraw')
            before = nvim.api.buf_get_extmark_by_id(0, live.extmark_namespace, live.virt_text_id, {'details': True})
            current = nvim.exec_lua('return ui.refresh()')
            after = nvim.api.buf_get_extmark_by_id(0, live.extmark_namespace, live.virt_text_id, {'details': True})
            assert before == after, 'Notebook UI must never rewrite Molten output marks'
            assert len(after[2]['virt_lines']) == (1 if status == OutputStatus.NEW else 2)
            nvim.command('redraw')
            separator = separator_snapshot()
            lower = next(f for f in current if f['kind'] == 'output')['rect']
            assert abs(lower['row'] - (separator[0] + 1.5)) < .01, 'seam leaves half a blank row above and below'
            geometry = [(f['rect'], f['anchor']) for f in current]
            if previous_geometry is not None:
                assert geometry == previous_geometry, 'same-height real Molten ticks must keep geometry and epoch'
                assert separator == previous_separator, 'recreated Molten marks must not move or rewrite the independent spacer'
            previous_geometry, previous_separator = geometry, separator
        assert len(ids) == 6, 'test must cover actual Molten mark replacement'
    old_epoch = current[0]['anchor']['epoch']
    live.output.chunks = [TextOutputChunk('42\n43')]
    live.show_virtual_output(anchor)
    grown = nvim.exec_lua('return ui.refresh()')
    assert grown[0]['anchor']['epoch'] != old_epoch, 'actual output height changes still update layout'
    # Actual source edits move marks/cells; frames must recompute, never retain old range.
    nvim.current.buffer.append(['', '# %%', 'print("added")', '', '# %%', ''])
    nvim.exec_lua('ui.refresh()')
    nvim.command('redraw')
    assert len([f for f in nvim.exec_lua('return ui.refresh()') if f['kind'] == 'input']) == 5
    nvim.current.window.cursor = (len(nvim.current.buffer), 0)
    nvim.command('redraw')
    assert nvim.exec_lua('return vim.fn.screenpos(0,vim.api.nvim_buf_line_count(0),1).row') > 0, 'empty cell keeps an editable visible source line'
    # Wheel scrolling must reuse one document-layout epoch, including cells
    # initially outside the viewport. Native animation owns the movement.
    nvim.exec_lua('vim.api.nvim_buf_clear_namespace(0,ns,0,-1)')
    long_source = []
    for index in range(20):
        long_source.extend(['# %%', f'print({index})', ''])
    nvim.current.buffer[:] = long_source
    nvim.exec_lua('ui.refresh()')
    nvim.command('redraw')
    model = nvim.exec_lua('return ui.refresh()')
    assert len([f for f in model if f['kind'] == 'input']) == 20, 'cache includes offscreen cells'
    geometry = [(f['rect'], f['anchor']) for f in model]
    for keys in ['\x05' * 8, '\x19' * 3, '\x05' * 5, '\x19' * 7]:
        nvim.exec_lua('vim.cmd.normal({args={...},bang=true})', keys)
        nvim.command('redraw')
        current = nvim.exec_lua('return ui.refresh()')
        assert [(f['rect'], f['anchor']) for f in current] == geometry, 'scroll must not chase screen positions or rebind epoch'
    assert nvim.current.buffer[:] == long_source, 'scroll keeps true source unchanged'
    epoch = model[0]['anchor']['epoch']
    nvim.current.buffer.append(['# %%', 'print("layout change")'])
    nvim.exec_lua('ui.refresh()')
    nvim.command('redraw')
    assert nvim.exec_lua('return ui.refresh()[1].anchor.epoch') != epoch, 'actual layout edits create a fresh baseline'
    nvim.command('tabnew')
    nvim.exec_lua('ui.refresh()')
    assert nvim.exec_lua('return _G.frames') == [], 'leaving notebook tab clears all native frames'
    nvim.command('tabprevious')
    returned = nvim.exec_lua('return ui.refresh()')
    assert returned[0]['anchor']['epoch'] != epoch, 'returning to a hidden tab remeasures its current viewport'
    print('PASS: seam centered on a real independent blank row; Molten header starts in next row; 12 real NEW/RUNNING ticks preserve raw marks/spacer/epoch; joined geometry/multiple marks/reload/scroll remain stable')
finally:
    try:
        nvim.command('qa!')
    except (OSError, EOFError, Exception):
        pass

# Actual multigrid UI-side resize: Neovim retains the split's logical width
# while wrapping its text grid two columns earlier. The UI client is Python in
# this fixture; production sends the same RPC through its ordered async worker.
margin = pynvim.attach('child', argv=['nvim', '--embed', '-u', 'NONE', '-n'])
try:
    margin.ui_attach(96, 34, rgb=True, ext_multigrid=True)
    margin.exec_lua("vim.opt.rtp:prepend(...)", str(ROOT / 'portable/payload/nvim'))
    margin.exec_lua("""
      vim.g.neovide_native_notebook=true;vim.g.neovide_native_notebook_viewport=true;vim.g.neovide_channel_id=77
      _margin_frames={};_margin_viewports={};vim.rpcnotify=function(_,method,frames,viewports)
        assert(method=='neovide.notebook.frames');_margin_frames=frames;_margin_viewports=viewports or {};return true end
      vim.wo.number=true;vim.wo.wrap=true;vim.wo.linebreak=false;vim.wo.cursorline=true
    """)
    mixed = ['# %% [markdown]', '# ' + 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' * 3,
             '# ' + '中文混排abc123' * 10, '# ' + 'word\t中文\t12345 ' * 6]
    margin.current.buffer[:] = mixed
    margin.current.buffer.options['modified'] = False
    book_buf, book_win = margin.current.buffer.number, margin.current.window.handle
    margin.command('botright vnew')
    neighbor = margin.current.window.handle
    margin.current.buffer[:] = ['neighbor stays here']
    margin.api.set_current_win(book_win)
    margin.api.win_set_option(book_win, 'winbar', ' Notebook')
    margin.api.win_set_cursor(book_win, [2, 8])
    margin.exec_lua("ui=require('config.media.notebook_ui');ui.attach(...);ui.refresh()", book_buf)
    sizes, owners = {}, {}
    def drain_grids():
        margin.eval('1')
        for message in margin._session._pending_messages:
            if message[0] == 'notification' and message[1] == 'redraw':
                for event in message[2]:
                    if event[0] == 'grid_resize':
                        for grid, width, height in event[1:]: sizes[grid] = (width, height)
                    if event[0] in ['win_pos', 'win_viewport']:
                        for value in event[1:]: owners[msgpack.unpackb(value[1].data)] = value[0]
        margin._session._pending_messages.clear()
    def apply_margin():
        drain_grids()
        viewports = margin.exec_lua('return _margin_viewports')
        assert len(viewports) == 1 and viewports[0]['window'] == book_win
        host = viewports[0]['width']
        grid = owners[book_win]
        margin.api.ui_try_resize_grid(grid, host - 2, sizes[grid][1])
        margin.command('redraw')
        margin.exec_lua('ui.refresh()')
        margin.command('redraw')
        drain_grids()
        return host, grid
    def neighbor_layout():
        info = margin.funcs.getwininfo(neighbor)[0]
        return (margin.api.win_get_width(neighbor), info['width'], margin.api.win_get_position(neighbor))
    neighbor_before = neighbor_layout()
    cursor = margin.api.win_get_cursor(book_win)
    host, grid = apply_margin()
    info = margin.funcs.getwininfo(book_win)[0]
    assert margin.api.win_get_width(book_win) == host and info['width'] == host - 2
    assert neighbor_layout() == neighbor_before, 'text-grid resize must not resize or move the adjacent split'
    assert margin.exec_lua('return _margin_frames[1].clip.width') == host, 'outer frame retains logical host width'
    position = margin.api.win_get_position(book_win)
    visible_rows = set()
    for line, text in enumerate(mixed[1:], start=2):
        byte = 1
        for character in text:
            pos = margin.funcs.screenpos(book_win, line, byte)
            assert pos['row'] > 0, 'every long-line source character must remain displayed'
            # screenpos reports a tab's unwrapped expansion end even when its
            # cells continue on the next screen row. Verify tab rows with the
            # actual screen cells below; ordinary/wide glyphs fit directly.
            edge = pos['col'] if character == '\t' else pos['endcol']
            assert edge <= position[1] + host - 2, 'ASCII/CJK/tab positions must stay in the narrow text grid'
            visible_rows.add(pos['row'])
            byte += len(character.encode())
    for row in visible_rows:
        assert margin.funcs.screenstring(row, position[1] + host - 1).strip() == ''
        assert margin.funcs.screenstring(row, position[1] + host).strip() == '', 'last two host columns contain real blank space'
    assert margin.api.win_get_cursor(book_win) == cursor and margin.api.win_get_option(book_win, 'cursorline')
    assert margin.api.buf_get_lines(book_buf, 0, -1, False) == mixed and not margin.api.buf_get_option(book_buf, 'modified')
    # Explicit split changes still use the newest logical width and leave its
    # neighbor unchanged by the subsequent text-only request.
    margin.api.win_set_width(book_win, host - 5)
    margin.exec_lua('ui.refresh()')
    resized_neighbor = neighbor_layout()
    latest_host, grid = apply_margin()
    assert latest_host == host - 5 and neighbor_layout() == resized_neighbor
    margin.command('enew')
    margin.exec_lua('ui.refresh()')
    assert margin.exec_lua('return _margin_viewports') == [], 'leaving the Notebook requests full-width restoration'
    margin.api.ui_try_resize_grid(grid, latest_host, sizes[grid][1])
    margin.command('redraw')
    assert margin.funcs.getwininfo(book_win)[0]['width'] == latest_host
    assert neighbor_layout() == resized_neighbor
    print('PASS: real multigrid ASCII/CJK/tab wrapping; two blank host columns; outer width/neighbor layout/cursorline/source unchanged; resized split and full-width restoration')
finally:
    try: margin.command('qa!')
    except (OSError, EOFError, Exception): pass
