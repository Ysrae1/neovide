"""Isolated real-grid Notebook footer checks; requires the Notebook pynvim venv.

GLOW_TEST_CONFIG selects the actual local or portable configuration root.
No kernel starts and no installed editor session is attached.
"""
from pathlib import Path
import os
import pynvim

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get("GLOW_TEST_CONFIG", ROOT / "portable/payload/nvim"))
nvim = pynvim.attach("child", argv=["nvim", "--embed", "-u", "NONE", "-n"])
try:
    nvim.ui_attach(96, 36, rgb=True)
    nvim.exec_lua("vim.opt.rtp:prepend(...)", str(CONFIG))
    nvim.current.buffer[:] = ["# %%", "print('first')", "# %%", "print('last')"]
    nvim.current.buffer.options["modified"] = False
    nvim.exec_lua("""
      local a=vim.api
      vim.g.neovide_native_notebook=true; vim.g.neovide_channel_id=77
      vim.g.neovide_native_notebook_footer=true
      vim.rpcnotify=function() return true end
      vim.wo.number=true
      _G.ns=a.nvim_create_namespace('molten-extmarks')
      local edit=require('config.media.notebook_edit')
      edit.cell_labels=function(buf)
        local result={}
        for index,cell in ipairs(edit.cells(buf)) do
          result[#result+1]={index=index,chunks=edit.label_chunks(cell.kind,'python',false)}
        end
        return result
      end
      a.nvim_set_hl(0,'Normal',{fg=0xdddddd,bg=0x101010})
      edit.refresh_title_colors()
      require('config.media.notebook_highlights').setup()
      _G.ui=require('config.media.notebook_ui'); ui.attach(a.nvim_get_current_buf())
      _G.set_output=function(row, lines)
        if _G.out then a.nvim_buf_del_extmark(0,ns,out) end
        local virt={}
        for _,text in ipairs(lines) do virt[#virt+1]={{text,'Normal'}} end
        _G.out=a.nvim_buf_set_extmark(0,ns,row,0,{virt_lines=virt})
        local before=a.nvim_buf_get_extmark_by_id(0,ns,out,{details=true})
        local frames=ui.refresh(); vim.cmd.redraw()
        assert(vim.deep_equal(before,a.nvim_buf_get_extmark_by_id(0,ns,out,{details=true})),
          'footer must never rewrite Molten output')
        return frames
      end
      _G.footers=function()
        return a.nvim_buf_get_extmarks(0,a.nvim_get_namespaces()['glow.notebook.footer'],0,-1,{details=true})
      end
      _G.screen=function()
        vim.cmd.redraw(); local rows={}
        for row=1,30 do local line='';for col=1,96 do line=line..vim.fn.screenstring(row,col) end
          rows[#rows+1]=line end
        return rows
      end
    """)
    source = nvim.current.buffer[:]
    nvim.exec_lua("set_output(1, {'Out[1]: Done', '42'})")
    assert not nvim.exec_lua("return footers()"), "short output has no footer"
    nvim.exec_lua("set_output(1, {'Out[1]: Done', '1', '󰁅 40 More lines '})")
    footers = nvim.exec_lua("return footers()")
    assert len(footers) == 1
    chunks = footers[0][3]["virt_lines"][0]
    assert [chunk[1] for chunk in chunks[1:]] == [
        "GlowNotebookExpandCap", "GlowNotebookExpand", "GlowNotebookExpandValue", "GlowNotebookExpandValueCap"]
    assert "󰕏 " == chunks[2][0] and " ␣jo" == chunks[3][0]
    rows = nvim.exec_lua("return screen()")
    output_row = next(i for i, line in enumerate(rows) if "40 More lines" in line)
    footer_row = next(i for i, line in enumerate(rows) if "␣jo" in line)
    assert footer_row == output_row + 1, "footer is directly below output before the hidden next-cell marker"
    nvim.exec_lua("""
      local a=vim.api;local layout=a.nvim_get_namespaces()['glow.notebook.layout']
      local labels=a.nvim_buf_get_extmarks(0,layout,0,-1,{details=true})
      local top
      for _,mark in ipairs(labels) do
        if mark[4].virt_lines_above then top=mark[4].virt_lines[1];break end
      end
      local function width(chunks) local text='';for _,chunk in ipairs(chunks) do text=text..chunk[1] end
        return vim.fn.strdisplaywidth(text) end
      assert(width(top)==width(footers()[1][4].virt_lines[1]),'footer and top label have the same right endpoint')
      assert(a.nvim_get_hl(0,{name='GlowNotebookExpand',link=false}).bg,
        'arrow segment has a solid themed background')
      assert(a.nvim_get_hl(0,{name='GlowNotebookExpand',link=false}).bg==require('config.media.notebook_edit').output_accent(),
        'arrow segment and output border use the exact same RGB')
    """)
    current = nvim.exec_lua("return ui.output_frame_geometry(vim.api.nvim_get_current_win(),vim.api.nvim_get_current_buf(),1)")
    footer_row_screen = next(i for i, line in enumerate(rows) if "␣jo" in line)
    assert abs(current["rect"]["row"] + current["rect"]["height"] - footer_row_screen - .5) < .01, "new native footer sits on the bottom border line"
    native_frame = next(f for f in nvim.exec_lua("return ui.refresh()") if f["kind"] == "output")
    assert len(native_frame["footer_gaps"]) == 1
    fallback = nvim.exec_lua("vim.g.neovide_native_notebook_footer=false;return ui.refresh()")
    fallback_frame = next(f for f in fallback if f["kind"] == "output")
    assert "footer_gaps" not in fallback_frame
    assert abs(fallback_frame["rect"]["height"] - native_frame["rect"]["height"] - .7) < .01, "old GUI keeps the hint safely inside its frame"
    nvim.exec_lua("vim.g.neovide_native_notebook_footer=true;ui.refresh();vim.cmd.redraw()")
    model = nvim.exec_lua("return ui.refresh()")
    for index in range(5):
        nvim.exec_lua("set_output(1, {'Out[1]: Running', ..., '󰁅 40 More lines '})", str(index))
        assert [(f["rect"], f["anchor"]) for f in nvim.exec_lua("return ui.refresh()")] == [
            (f["rect"], f["anchor"]) for f in model], "equal-height stream keeps geometry stable"
    nvim.exec_lua("set_output(3, {'Out[2]: Done', '↑ 30 More lines', 'tail'})")
    rows = nvim.exec_lua("return screen()")
    assert next(i for i, line in enumerate(rows) if "␣jo" in line) == next(
        i for i, line in enumerate(rows) if "tail" in line) + 1, "footer also follows output at EOF"
    nvim.exec_lua("set_output(3, {'Out[2]: Done', string.rep('x', 120)})")
    assert len(nvim.exec_lua("return footers()")) == 1, "clipped long line has an expansion hint"
    nvim.exec_lua("set_output(3, {'Out[2]: Done', string.rep('x', 65)})")
    assert not nvim.exec_lua("return footers()")
    nvim.ui_try_resize(55, 36)
    nvim.exec_lua("ui.refresh()")
    assert len(nvim.exec_lua("return footers()")) == 1, "resize recalculates actual clipping"
    nvim.ui_try_resize(96, 36)
    nvim.exec_lua("ui.refresh()")
    assert not nvim.exec_lua("return footers()"), "wider view removes unnecessary footer"
    nvim.exec_lua("set_output(3, {'Out[2]: Done', '42', '󰁅 20 More lines '})")
    nvim.exec_lua("vim.cmd.enew();ui.refresh();vim.cmd.buffer(1);ui.refresh()")
    assert len(nvim.exec_lua("return footers()")) == 1, "hidden/restored Notebook retains hint"
    nvim.exec_lua("vim.o.background='light';vim.api.nvim_exec_autocmds('ColorScheme',{});ui.refresh()")
    assert len(nvim.exec_lua("return footers()")) == 1
    nvim.exec_lua("vim.api.nvim_buf_clear_namespace(0,ns,0,-1);ui.refresh()")
    assert not nvim.exec_lua("return footers()"), "clearing output removes the independent footer"
    assert nvim.current.buffer[:] == source and not nvim.current.buffer.options["modified"]
    nvim.current.buffer[:] = ["# %%", ""]
    for index in range(5):
        nvim.exec_lua("set_output(1, {'Out[3]: Done', '42', '󰁅 20 More lines '})")
        rows = nvim.exec_lua("return screen()")
        assert next(i for i, line in enumerate(rows) if "␣jo" in line) == next(
            i for i, line in enumerate(rows) if "20 More lines" in line) + 1, "empty anchors keep footer after recreated Molten marks"
    long_source = [line for index in range(20) for line in ("# %%", f"print({index})")]
    nvim.exec_lua("vim.api.nvim_buf_clear_namespace(0,ns,0,-1)")
    nvim.current.buffer[:] = long_source
    nvim.exec_lua("set_output(1, {'Out[4]: Done', '42', '󰁅 20 More lines '})")
    first = nvim.exec_lua("return ui.output_frame_geometry(vim.api.nvim_get_current_win(),vim.api.nvim_get_current_buf(),1)")
    first_reference = nvim.exec_lua("return vim.fn.screenpos(0,10,1).row")
    nvim.exec_lua("vim.cmd.normal({args={string.rep(string.char(5),4)},bang=true});vim.cmd.redraw()")
    shifted = nvim.exec_lua("return ui.output_frame_geometry(vim.api.nvim_get_current_win(),vim.api.nvim_get_current_buf(),1)")
    reference_shift = nvim.exec_lua("return vim.fn.screenpos(0,10,1).row") - first_reference
    assert reference_shift < 0 and shifted["rect"]["row"] == first["rect"]["row"] + reference_shift, "read-only output geometry follows actual grid scrolling, including virtual and concealed rows"
    assert (shifted["rect"]["col"], shifted["rect"]["width"]) == (first["rect"]["col"], first["rect"]["width"])
    nvim.exec_lua("""
      local a=vim.api;local buf=a.nvim_create_buf(false,true)
      vim.bo[buf].filetype='molten_output'
      local win=a.nvim_open_win(buf,false,{relative='editor',row=8,col=10,width=40,height=10,border='none'})
      vim.w[win].glow_notebook_output_frame={row=.3,col=.5,width=39.2,height=9.4}
      local found, connector
      for _,frame in ipairs(ui.refresh()) do
        if frame.overlay and frame.kind=='output' then
          assert(vim.deep_equal(frame.rect,vim.w[win].glow_notebook_output_frame),'expanded frame preserves fractional source edges')
          assert(frame.join=='bottom','expanded output keeps the input/output seam straight')
          found=true
        elseif frame.overlay and frame.kind=='input' then
          assert(frame.join=='top' and frame.rect.row==-1.7 and frame.rect.height==2,
            'input connector is clipped to the top padding, with its top edge outside the popup')
          assert(frame.rect.col==.5 and frame.rect.width==39.2,
            'input connector uses the same fractional side edges')
          connector=true
        end
      end
      assert(found and connector);a.nvim_win_close(win,true);a.nvim_buf_delete(buf,{force=true})
    """)
    # Real mouse events use screen coordinates. Virtual rows report neighboring
    # source anchors, so exercise two outputs and a scrolled viewport.
    nvim.exec_lua("""
      local a=vim.api;vim.o.mouse='a';vim.g.mapleader=' '
      a.nvim_buf_clear_namespace(0,ns,0,-1)
      for index,row in ipairs({1,3}) do
        a.nvim_buf_set_extmark(0,ns,row,0,{virt_lines={{{'Out['..index..']: Done','Normal'}},
          {{'result '..index,'Normal'}},{{'󰁅 20 More lines ','Normal'}}}})
      end
      _G.mouse_opened={}
      vim.keymap.set('n','<leader>jo',function()
        local row=a.nvim_win_get_cursor(0)[1]
        for index,cell in ipairs(require('config.media.notebook_edit').cells(0)) do
          if row>=cell.first and row<=cell.last then mouse_opened[#mouse_opened+1]=index;return end
        end
      end,{buffer=true})
      vim.cmd.normal({args={'gg'},bang=true});ui.refresh();vim.cmd.redraw()
    """)

    def click_output(cell):
        geometry = nvim.exec_lua("return ui.output_frame_geometry(vim.api.nvim_get_current_win(),vim.api.nvim_get_current_buf(),...)", cell)
        row = int(max(geometry["rect"]["row"], geometry["clip"]["row"]) + 1)
        col = int(geometry["rect"]["col"] + 3)
        nvim.api.input_mouse("left", "press", "", 0, row, col)
        nvim.api.input_mouse("left", "release", "", 0, row, col)
        assert nvim.exec_lua("local target=...;return vim.wait(1000,function() return vim.api.nvim_win_get_cursor(0)[1]==target end,5)", cell * 2)

    click_output(2)
    assert not nvim.exec_lua("return mouse_opened"), "click selects output without expanding it"
    nvim.input(" jo")
    assert nvim.exec_lua("return vim.wait(1000,function() return #mouse_opened==1 end,5)")
    assert nvim.exec_lua("return mouse_opened[1]") == 2
    click_output(1)
    nvim.input(" jo")
    assert nvim.exec_lua("return vim.wait(1000,function() return #mouse_opened==2 end,5)")
    assert nvim.exec_lua("return mouse_opened[2]") == 1
    nvim.exec_lua("vim.cmd.normal({args={string.rep(string.char(5),2)},bang=true});vim.cmd.redraw()")
    click_output(2)
    nvim.input(" jo")
    assert nvim.exec_lua("return vim.wait(1000,function() return #mouse_opened==3 end,5)")
    assert nvim.exec_lua("return mouse_opened[3]") == 2, "scroll does not confuse output ownership"
    ordinary = nvim.exec_lua("return vim.fn.screenpos(0,10,1)")
    nvim.api.input_mouse("left", "press", "", 0, ordinary["row"] - 1, ordinary["col"] - 1)
    nvim.api.input_mouse("left", "release", "", 0, ordinary["row"] - 1, ordinary["col"] - 1)
    assert nvim.exec_lua("return vim.wait(1000,function() return vim.api.nvim_win_get_cursor(0)[1]==10 end,5)"), "ordinary source clicks retain native behavior"
    ordinary_end = nvim.exec_lua("return vim.fn.screenpos(0,12,1)")
    nvim.api.input_mouse("left", "press", "", 0, ordinary["row"] - 1, ordinary["col"] - 1)
    nvim.api.input_mouse("left", "drag", "", 0, ordinary_end["row"] - 1, ordinary_end["col"] + 3)
    nvim.api.input_mouse("left", "release", "", 0, ordinary_end["row"] - 1, ordinary_end["col"] + 3)
    assert nvim.exec_lua("return vim.wait(1000,function() return vim.fn.mode():find('[vV]')~=nil end,5)"), "ordinary source dragging still selects text"
    nvim.input("\x1b")
    popup = nvim.exec_lua("""local a=vim.api;local buf=a.nvim_create_buf(false,true)
      vim.bo[buf].filetype='molten_output';a.nvim_buf_set_lines(buf,0,-1,false,{'copyable popup text','second line'})
      local win=a.nvim_open_win(buf,false,{relative='editor',row=6,col=10,width=35,height=8,border='none'})
      return {win=win,buf=buf,source=a.nvim_get_current_win()}""")
    nvim.api.input_mouse("left", "press", "", 0, 7, 15)
    nvim.api.input_mouse("left", "release", "", 0, 7, 15)
    assert nvim.exec_lua("local target=...;return vim.wait(1000,function() return vim.api.nvim_get_current_win()==target end,5)", popup["win"]), "popup click never passes through to an inline output below it"
    nvim.exec_lua("vim.api.nvim_win_close(...,true)", popup["win"])
    print(f"Notebook footer: all isolated grid checks passed ({CONFIG})")
finally:
    try:
        nvim.command("qa!")
    except (EOFError, OSError):
        pass

# A real secondary/source grid with a winbar exercises the same coordinate
# space as Neovide, including mode transitions that grid-0 tests cannot prove.
nvim = pynvim.attach("child", argv=["nvim", "--embed", "-u", "NONE", "-n"])
try:
    nvim.ui_attach(100, 37, rgb=True, ext_multigrid=True, ext_linegrid=True)
    nvim.exec_lua("vim.opt.rtp:prepend(...)", str(CONFIG))
    nvim.current.buffer[:] = ["# %%", "print('upper')", "# %%", "print('lower')"]
    nvim.current.buffer.options["modified"] = False
    nvim.exec_lua("""
      local a=vim.api;vim.o.mouse='a';vim.g.mapleader=' '
      vim.wo.winbar='Notebook title';vim.g.neovide_native_notebook=true
      vim.g.neovide_native_notebook_footer=true;vim.g.neovide_channel_id=77
      vim.rpcnotify=function() return true end
      local edit=require('config.media.notebook_edit')
      edit.cell_labels=function() return {} end
      _G.ui=require('config.media.notebook_ui');ui.attach(a.nvim_get_current_buf())
      local ns=a.nvim_create_namespace('molten-extmarks')
      for index,row in ipairs({1,3}) do
        a.nvim_buf_set_extmark(0,ns,row,0,{virt_lines={{{'Out['..index..']: Done','Normal'}},
          {{'value '..index,'Normal'}},{{'󰁅 20 More lines ','Normal'}}}})
      end
      _G.opened={}
      vim.keymap.set('n','<leader>jo',function()
        local row=a.nvim_win_get_cursor(0)[1]
        opened[#opened+1]=row==2 and 1 or row==4 and 2 or 0
      end,{buffer=true})
      ui.refresh();vim.cmd.redraw()
    """)
    nvim.command("redraw!")
    nvim.eval("1")
    source_win = nvim.current.window.handle
    source_grid = None
    origin = None
    for message in nvim._session._pending_messages:
        if message[0] != "notification" or message[1] != "redraw":
            continue
        for event in message[2]:
            if event[0] != "win_pos":
                continue
            for value in event[1:]:
                win = value[1].handle if hasattr(value[1], "handle") else int.from_bytes(value[1].data[1:], "big")
                if win == source_win:
                    source_grid, origin = value[0], value[2:4]
    assert source_grid and source_grid != 1 and origin is not None, "mouse regression must use a real non-root grid"
    original = nvim.current.buffer[:]
    tick = nvim.api.buf_get_changedtick(0)
    for mode, cell in [("n", 2), ("i", 1), ("x", 2)]:
        nvim.input("\x1b")
        assert nvim.exec_lua("return vim.wait(1000,function() return vim.fn.mode()=='n' end,5)")
        if mode != "n":
            nvim.input("i" if mode == "i" else "v")
            assert nvim.exec_lua("local expected=...;return vim.wait(1000,function() return vim.fn.mode():sub(1,1)==expected end,5)", "i" if mode == "i" else "v")
        geometry = nvim.exec_lua("return ui.output_frame_geometry(vim.api.nvim_get_current_win(),vim.api.nvim_get_current_buf(),...)", cell)
        row = int(max(geometry["rect"]["row"], geometry["clip"]["row"]) + 1) - origin[0]
        col = int(geometry["rect"]["col"] + 3) - origin[1]
        nvim.api.input_mouse("left", "press", "", source_grid, row, col)
        nvim.api.input_mouse("left", "release", "", source_grid, row, col)
        assert nvim.exec_lua("local target=...;return vim.wait(1000,function() return vim.fn.mode()=='n' and vim.api.nvim_win_get_cursor(0)[1]==target end,5)", cell * 2), f"{mode} output click must enter normal mode and choose its source cell"
        mouse = nvim.funcs.getmousepos()
        assert mouse["winid"] == source_win and mouse["screenrow"] == row + origin[0] + 1
        count = len(nvim.exec_lua("return opened"))
        nvim.input(" jo")
        assert nvim.exec_lua("local count=...;return vim.wait(1000,function() return #opened==count+1 end,5)", count)
        assert nvim.exec_lua("return opened[#opened]") == cell
        assert nvim.current.buffer[:] == original and nvim.api.buf_get_changedtick(0) == tick, "mode-aware output click must not insert leader keys into source"
    nvim.input("i")
    assert nvim.exec_lua("return vim.wait(1000,function() return vim.fn.mode():sub(1,1)=='i' end,5)")
    point = nvim.exec_lua("return vim.fn.screenpos(0,2,1)")
    nvim.api.input_mouse("left", "press", "", source_grid, point["row"] - origin[0] - 1, point["col"] - origin[1] - 1)
    nvim.api.input_mouse("left", "release", "", source_grid, point["row"] - origin[0] - 1, point["col"] - origin[1] - 1)
    assert nvim.exec_lua("return vim.wait(1000,function() return vim.fn.mode():sub(1,1)=='i' end,5)"), "ordinary source click must keep insert mode"
    assert nvim.current.buffer[:] == original and nvim.api.buf_get_changedtick(0) == tick
    print(f"Notebook mouse: real multigrid {source_grid}, winbar, n/i/Visual selection and leader behavior passed ({CONFIG})")
finally:
    try:
        nvim.command("qa!")
    except (EOFError, OSError):
        pass
