"""Actual multigrid winbar height contract and global-statusline boundary."""
import json
import msgpack
import pynvim

nvim = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
try:
    nvim.ui_attach(81, 39, rgb=True, ext_multigrid=True)
    nvim.exec_lua("vim.o.showtabline=2;vim.o.laststatus=3;vim.o.cmdheight=0;vim.o.statusline='GLOBAL STATUSLINE'")
    source = ['# %%', 'print(42)', '']
    nvim.current.buffer[:] = source
    buf, win = nvim.current.buffer.number, nvim.current.window.handle
    nvim.command('topleft 27vnew')
    nvim.api.set_current_win(win)
    nvim.exec_lua("vim.wo.winbar='Notebook'")
    tick = nvim.api.buf_get_changedtick(buf)
    actual, hosts, margins, owners, root_rows = {}, {}, {}, {}, {}

    def drain():
        nvim.command('redraw!')
        nvim.eval('1')
        while nvim._session._pending_messages:
            message = nvim._session._pending_messages.popleft()
            if message[0] != 'notification' or message[1] != 'redraw':
                continue
            for event in message[2]:
                for values in event[1:]:
                    if event[0] == 'grid_resize':
                        actual[values[0]] = tuple(values[1:])
                    elif event[0] == 'win_pos':
                        grid, window, row, col, width, height = values
                        owners[grid] = msgpack.unpackb(window.data) if hasattr(window, 'data') else window
                        hosts[grid] = (row, col, width, height)
                    elif event[0] == 'win_viewport_margins':
                        margins[values[0]] = values[2]
                    elif event[0] == 'grid_line' and values[0] == 1:
                        _, row, col, cells = values[:4]
                        line = root_rows.setdefault(row, [' '] * 200)
                        for cell in cells:
                            for _ in range(cell[2] if len(cell) > 2 else 1):
                                line[col] = cell[0]
                                col += 1

    drain()
    grid = next(grid for grid, owner in owners.items() if owner == win)
    row, col, width, height = hosts[grid]
    assert margins[grid] == 1 and actual[grid][1] == height
    assert row + height == 38 and ''.join(root_rows[38]).startswith('GLOBAL STATUSLINE')
    # Reproduce the old bug: the API takes inner text height and adds winbar.
    nvim.api.ui_try_resize_grid(grid, width - 2, height)
    drain()
    assert actual[grid][1] == height + 1 and row + actual[grid][1] > 38
    nvim.api.ui_try_resize_grid(grid, width - 2, height - margins[grid])
    drain()
    assert actual[grid] == (width - 2, height) and row + actual[grid][1] == 38
    # Switch away from Notebook layout, then land an old request after a root resize.
    nvim.exec_lua("vim.wo.winbar=''")
    nvim.api.ui_try_resize(134, 35)
    drain()
    row, col, width, height = hosts[grid]
    nvim.api.ui_try_resize_grid(grid, width, height)
    drain()
    assert actual[grid] == (width, height) and margins[grid] == 0
    nvim.api.ui_try_resize_grid(grid, 120, 37)  # Late old request, as in real .py screenshot.
    drain()
    assert actual[grid] == (120, 37) and row + actual[grid][1] > 34
    nvim.api.ui_try_resize_grid(grid, width, height - margins[grid])
    drain()
    assert actual[grid] == (width, height) and row + actual[grid][1] == 34
    assert ''.join(root_rows[34]).startswith('GLOBAL STATUSLINE')
    assert nvim.api.buf_get_lines(buf, 0, -1, False) == source
    assert nvim.api.buf_get_changedtick(buf) == tick
    print(json.dumps({'winbar_inner_height_offset': 1, 'notebook_bottom': 38,
                      'ordinary_bottom': 34, 'global_statusline_preserved': True,
                      'late_oversize_feedback_repaired': True, 'source_unchanged': True}))
finally:
    try:
        nvim.command('qa!')
    except (OSError, EOFError):
        pass
