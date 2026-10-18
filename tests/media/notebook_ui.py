"""One isolated Neovim UI check for native Notebook frame geometry.
Run with the bundled Notebook environment's Python (pynvim required).
"""
from pathlib import Path
import sys
from types import SimpleNamespace
import pynvim

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
        _G.frames={}; vim.rpcnotify=function(_,method,frames)
          assert(method=='neovide.notebook.frames'); _G.frames=vim.deepcopy(frames); return true
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
