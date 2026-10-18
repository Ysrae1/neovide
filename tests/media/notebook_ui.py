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
    assert len(inputs) == 3 and len(outputs) == 1, frames
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
    gaps = inputs[0]['label_gaps']
    assert len(gaps) == 2, 'type and run capsules each cut only their own top segment'
    assert gaps[1]['col'] - gaps[0]['col'] - gaps[0]['width'] >= 2, 'visible stroke connects the two capsules'
    labels = nvim.exec_lua("""local result={};local ns=vim.api.nvim_get_namespaces()['glow.notebook.layout']
      for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})) do
        if mark[4].virt_lines_above then result[#result+1]=mark end end;return result""")
    assert len(labels) == 3 and all(len(mark[3]['virt_lines']) == 1 for mark in labels), 'labels reuse one existing virtual row per cell'
    label_text = ''.join(chunk[0] for chunk in labels[0][3]['virt_lines'][0])
    assert 'python' not in label_text and 'Markdown' not in label_text and '▷' in label_text
    out_rect = outputs[0]['rect']
    assert abs(out_rect['row'] - (last_row + 1.05)) < .01, (out_rect, last_row)
    assert out_rect['row'] > inputs[0]['rect']['row'] + inputs[0]['rect']['height'], 'input and output boxes are separate'
    # Inspect actual rendered lines, not only API geometry.
    screen = nvim.exec_lua("""local rows={};for r=1,15 do local text='';for c=1,40 do
      text=text..vim.fn.screenstring(r,c) end;rows[#rows+1]=text end;return rows""")
    assert not any('jupyter:' in line for line in screen), screen
    assert not any('# %%' in line for line in screen), 'cell markers are hidden without removing source'
    assert any('print(42)' in line for line in screen), screen
    # Jupytext may reload this same buffer after session restoration. Replacing
    # identical text still relocates extmarks; metadata shape alone is not a
    # sufficient cache key for its conceal positions.
    # Remove the synthetic output first: it has no Molten owner to move it back.
    nvim.exec_lua("""vim.api.nvim_buf_del_extmark(0,ns,out)
      vim.api.nvim_buf_set_lines(0,0,-1,false,...);vim.bo.modified=false""", source)
    reload_tick = nvim.api.buf_get_changedtick(0)
    nvim.exec_lua('ui.refresh()')
    concealed = nvim.exec_lua("""local ns=vim.api.nvim_get_namespaces()['glow.notebook.metadata']
      return vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})""")
    assert [mark[1] for mark in concealed] == [0, 1, 2, 3], 'same-shape reload must restore metadata marks to its actual prefix'
    assert nvim.current.buffer[:] == source and nvim.api.buf_get_changedtick(0) == reload_tick
    assert nvim.current.buffer.options['modified'] is False, 'conceal repair must not dirty the reloaded source'
    nvim.exec_lua("""out=vim.api.nvim_buf_set_extmark(0,ns,6,0,
      {virt_lines={{{'Out[1]: Done','Normal'}},{{'42','Normal'}}}});ui.refresh()""")
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
        previous_geometry, ids = None, set()
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
            geometry = [(f['rect'], f['anchor']) for f in current]
            if previous_geometry is not None:
                assert geometry == previous_geometry, 'same-height real Molten ticks must keep geometry and epoch'
            previous_geometry = geometry
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
    print('PASS: real Molten NEW/RUNNING mark replacement keeps raw height and frame epoch; real output growth relayout; hidden markers/metadata; editable empty cell; preserved source; forward/reverse native scrolling; Tab lifecycle')
finally:
    try:
        nvim.command('qa!')
    except (OSError, EOFError, Exception):
        pass
