#!/usr/bin/env python3
"""Saved Matplotlib PNG through real Molten's writer; no kernel/user code runs."""
from pathlib import Path
from types import SimpleNamespace
import importlib.util
import math
import sys
import tempfile
import time

import pynvim
from matplotlib.figure import Figure

ROOT = Path(__file__).resolve().parents[2]
CELL_METRICS = (ROOT / 'lua/cell_metrics.lua').read_text()
MOLTEN = Path.home() / '.local/share/nvim/lazy/molten-nvim/rplugin/python3'
sys.path.insert(0, str(MOLTEN))
sys.argv.append(str(MOLTEN / 'molten'))
from molten.images import NoCanvas
from molten.outputbuffer import OutputBuffer
from molten.outputchunks import ImageOutputChunk, Output, OutputStatus

spec = importlib.util.spec_from_file_location('glow_output_adapter_test', ROOT / 'portable/payload/nvim/lua/config/media/runtime/glow_molten_output.py')
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
assert adapter._info['active'], adapter._info

with tempfile.TemporaryDirectory(prefix='glow-inline-image-') as directory:
    png = Path(directory) / "saved plot's 图.png"
    figure = Figure(figsize=(5.47, 4.34), dpi=100)
    figure.subplots().plot([0, 1, 2], [0, 1, 0])
    figure.savefig(png)
    editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
    try:
        editor.ui_attach(120, 45, rgb=True)
        cell_width, cell_height = 12.75, 37.5
        editor.exec_lua(CELL_METRICS, cell_width, cell_height)
        assert editor.exec_lua("return package.loaded['config.media.molten_images']==nil and vim.g.neovide_cell_width==12.75 and vim.g.neovide_cell_height==37.5"), 'publish physical metrics before module setup'
        editor.exec_lua('vim.opt.rtp:prepend(...)', str(ROOT / 'portable/payload/nvim'))
        editor.exec_lua("""
          vim.g.neovide=true;vim.g.neovide_native_notebook=true
          vim.g.neovide_native_image=true;vim.g.neovide_native_image_anchor=true;vim.g.neovide_channel_id=77
          vim.o.laststatus=0;vim.o.showmode=false;vim.o.hidden=true
          _calls={};vim.rpcnotify=function(_,method,...) _calls[#_calls+1]={method,...};return true end
          _block_images=true;local pumvisible=vim.fn.pumvisible
          vim.fn.pumvisible=function()return _block_images and 1 or pumvisible()end
          require('config.media.molten_images').setup()
        """)
        source = ['# %%', 'plot_user_source_must_not_execute()', '', '# %%', '42'] + [''] * 60
        editor.current.buffer[:] = source
        editor.current.buffer.options['modified'] = False
        editor.current.buffer.options['filetype'] = 'python'
        editor.exec_lua("""
          vim.b.glow_notebook_edit=true
          _ui=require('config.media.notebook_ui');_ui.attach(vim.api.nvim_get_current_buf());_ui.refresh()
        """)
        buf = editor.current.buffer.number
        namespace = editor.api.create_namespace('molten-extmarks')
        live = OutputBuffer.__new__(OutputBuffer)
        live.nvim, live.canvas = editor, NoCanvas()
        live.extmark_namespace = namespace
        live.virt_hidden, live.virt_text_id, live.displayed_status = False, None, None
        live.output = Output(7)
        live.output.status = OutputStatus.DONE
        live.output.chunks = [ImageOutputChunk(str(png))]
        live.options = SimpleNamespace(cover_empty_lines=False, virt_lines_off_by_1=False,
            virt_text_max_lines=16, output_show_exec_time=False, image_provider='image.nvim',
            image_location='float', limit_output_chars=0, wrap_output=True,
            hl=SimpleNamespace(virtual_text='MoltenVirtualText'))
        anchor = SimpleNamespace(bufno=buf, lineno=1)
        live.show_virtual_output(anchor)

        def wait(predicate, label):
            deadline = time.monotonic() + 4
            while time.monotonic() < deadline:
                if predicate(): return
                time.sleep(.02)
            raise AssertionError(label + ': ' + editor.command_output('messages'))

        def shows():
            return [call for call in editor.exec_lua('return _calls') if call[0] == 'neovide.image.show']

        # Metrics published before setup are consumed without an approximate box.
        editor.exec_lua("require('config.media.molten_images').refresh()")
        assert not shows()
        revision = editor.exec_lua("return require('config.media.molten_images').inline_revision(...)", buf)
        editor.exec_lua(CELL_METRICS, cell_width, cell_height)
        editor.exec_lua("require('config.media.molten_images').refresh()")
        assert editor.exec_lua("return require('config.media.molten_images').inline_revision(...)", buf) == revision, 'duplicate metrics must not rewrite image padding'
        padding = editor.exec_lua("return require('config.media.molten_images').inline_output_marks(...)", buf)
        baseline = editor.exec_lua("local buf,ns,id=...;return _ui.virtual_output_geometry(vim.api.nvim_get_current_win(),buf,ns,id)",
                                   buf, padding[0]['namespace'], padding[0]['id'])
        old_view = editor.exec_lua('return vim.fn.winsaveview()')
        editor.command('normal! 2' + chr(5))  # Real Ctrl-E, including virtual-line topfill.
        scrolled_view = editor.exec_lua('return vim.fn.winsaveview()')
        assert old_view != scrolled_view, 'drift regression must actually scroll the Neovim grid'
        delayed = editor.exec_lua("local buf,ns,id=...;return _ui.virtual_output_geometry(vim.api.nvim_get_current_win(),buf,ns,id)",
                                  buf, padding[0]['namespace'], padding[0]['id'])
        assert delayed == baseline, 'delayed first image must use its frame epoch geometry, not current screenpos'
        editor.exec_lua("_block_images=false;require('config.media.molten_images').refresh()")
        wait(lambda: bool(shows()), 'inline native show')
        show = shows()[-1]
        identifier, view = show[1:]
        assert view['overlay'] is False and view['anchor']['scroll'] is True and view['anchor']['window'] == editor.current.window.handle
        assert view['height'] > 5 and view['width'] > 10
        assert view['row'] == baseline['row'] and view['anchor'] == baseline['anchor']
        assert abs(view['width'] * cell_width - 547) < .001
        assert abs(view['height'] * cell_height - 434) < .001
        assert any(call[0] == 'neovide.image.load' and call[2] == str(png) for call in editor.exec_lua('return _calls'))
        raw = editor.api.buf_get_extmark_by_id(buf, namespace, live.virt_text_id, {'details': True})
        text = [''.join(chunk[0] for chunk in row) for row in raw[2]['virt_lines']]
        assert len(text) == 1 and text[0].startswith('Out[7]: ✓ Done'), text
        padding = editor.exec_lua("return require('config.media.molten_images').inline_output_marks(...)", buf)
        assert len(padding) == 1 and padding[0]['lines'] == math.ceil(view['height']) == 12
        frame = next(frame for frame in editor.exec_lua('return _ui.refresh()') if frame['kind'] == 'output')
        assert view['anchor'] == frame['anchor']
        assert view['row'] >= frame['rect']['row'] and view['row'] + view['height'] <= frame['rect']['row'] + frame['rect']['height'], (view, frame, raw, padding, editor.exec_lua("local r={};for _,m in ipairs(vim.api.nvim_buf_get_extmarks(0,-1,0,-1,{details=true})) do if m[4].virt_lines then r[#r+1]={m[1],m[2],m[4].ns_id,#m[4].virt_lines,m[4].priority} end end;return r"))
        editor.exec_lua(r"""
          vim.cmd.redraw();_header_row=0
          for row=1,45 do local text='';for col=1,120 do text=text..vim.fn.screenstring(row,col) end
            if text:find('Out[7]',1,true) then _header_row=row;break end end
        """)
        header_row = editor.exec_lua('return _header_row')
        # Header may have scrolled above the viewport; its native frame and image
        # deliberately retain their shared original document-local baseline.
        epoch = view['anchor']['epoch']
        editor.command('normal! 2' + chr(5))
        editor.exec_lua("require('config.media.molten_images').refresh()")
        if shows()[-1][2]['anchor']['epoch'] == epoch:
            assert shows()[-1][2]['row'] == view['row'], 'scroll must use native anchor, not chase absolute rows'
        editor.exec_lua(CELL_METRICS, cell_width * 2, cell_height * 2)
        editor.exec_lua("require('config.media.molten_images').refresh()")
        wait(lambda: shows()[-1][2]['anchor']['epoch'] != epoch, 'font zoom geometry generation')
        zoomed = shows()[-1][2]
        assert abs(zoomed['width'] * cell_width * 2 - 547) < .001
        assert abs(zoomed['height'] * cell_height * 2 - 434) < .001
        assert editor.exec_lua("return require('config.media.molten_images').inline_output_marks(...)[1].lines", buf) == 6
        editor.ui_try_resize(24, 10)
        editor.exec_lua("require('config.media.molten_images').refresh()")
        wait(lambda: shows()[-1][2]['anchor']['epoch'] != zoomed['anchor']['epoch'], 'small viewport reflow')
        small = shows()[-1][2]
        assert small['width'] * cell_width * 2 < 547 and small['height'] * cell_height * 2 < 434
        editor.ui_try_resize(86, 40)
        editor.exec_lua("require('config.media.molten_images').refresh()")
        wait(lambda: shows()[-1][2]['anchor']['epoch'] != epoch, 'resize geometry generation')
        # Existing popup adapter still uses absolute overlay geometry.
        popup = editor.exec_lua("""
          local buf=vim.api.nvim_create_buf(false,true)
          vim.api.nvim_buf_set_lines(buf,0,-1,false,{'Out[7]: Done',' '})
          local win=vim.api.nvim_open_win(buf,false,{relative='editor',row=2,col=2,width=70,height=12})
          local api=require('config.media.molten_images').image_api
          api.from_file(...,{id='popup-test',buffer=buf,window=win,x=0,y=1});api.render('popup-test')
          return win
        """, str(png))
        wait(lambda: any(call[2].get('overlay') for call in shows()), 'existing image popup')
        editor.api.win_close(popup, True)
        editor.exec_lua("require('config.media.molten_images').refresh()")
        editor.command('tabnew')
        wait(lambda: any(call[0] == 'neovide.image.close' and call[1] == identifier for call in editor.exec_lua('return _calls')), 'leaving tab closes inline pixels')
        editor.command('tabprevious')
        editor.exec_lua("require('config.media.molten_images').refresh()")
        live.clear_virt_output(buf)
        assert not editor.exec_lua("return require('config.media.molten_images').inline_output_marks(...)", buf)
        assert editor.api.buf_get_extmark_by_id(buf, namespace, live.virt_text_id or 999999, {}) == []
        assert editor.current.buffer[:] == source and not editor.current.buffer.options['modified']
        assert editor.eval("exists(':MoltenInit')") == 0
        print('PASS: 547x434 intrinsic pixel size/ceil padding; physical font zoom/viewport shrink; delayed-first-image scroll shares cached frame epoch; original source/status/popup/tab/clear preserved')
    finally:
        try: editor.command('qa!')
        except Exception: pass
