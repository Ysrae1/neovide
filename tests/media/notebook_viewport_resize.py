#!/usr/bin/env python3
"""Real multigrid resize/tab interleaving; model the latest-win_pos host policy.

This is a protocol regression, not a Rust/Neovide GUI test. Actual allocations
come only from grid_resize. A logical win_pos must never resize text storage.
"""
import json

import msgpack
import pynvim


def handle(value):
    if hasattr(value, 'data'):
        return msgpack.unpackb(value.data)
    return getattr(value, 'handle', value)


editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
try:
    editor.ui_attach(160, 32, rgb=True, ext_multigrid=True)
    editor.exec_lua("vim.o.showtabline=2;vim.o.laststatus=0;vim.wo.wrap=true;vim.o.swapfile=false")
    source = ['# %%', 'value = ' + '1234567890' * 28, '# %% [markdown]', '# ' + 'wrapped notebook text ' * 15]
    editor.current.buffer[:] = source
    editor.current.buffer.options['modified'] = False
    book, book_window = editor.current.buffer.number, editor.current.window.handle
    changedtick = editor.api.buf_get_changedtick(book)
    editor.command('tabnew')
    editor.current.buffer[:] = ['ordinary tab']
    editor.command('tabprevious')

    actual, logical, owners, visible = {}, {}, {}, set()
    events = {'grid_resize': 0, 'win_pos': 0, 'grid_line': 0}
    differences = []

    def drain():
        editor.command('redraw!')
        editor.eval('1')
        while editor._session._pending_messages:
            message = editor._session._pending_messages.popleft()
            if message[0] != 'notification' or message[1] != 'redraw':
                continue
            for event in message[2]:
                name = event[0]
                for values in event[1:]:
                    if name == 'grid_resize':
                        grid, width, height = values
                        actual[grid] = (width, height)
                        events[name] += 1
                    elif name == 'win_pos':
                        grid, window, _row, _column, width, height = values
                        owners[grid] = handle(window)
                        logical[grid] = (width, height)
                        visible.add(grid)
                        events[name] += 1
                        if grid in actual and actual[grid] != logical[grid]:
                            differences.append({'grid': grid, 'actual': actual[grid], 'logical': logical[grid]})
                    elif name == 'win_viewport':
                        owners[values[0]] = handle(values[1])
                    elif name == 'win_hide':
                        visible.discard(values[0])
                    elif name == 'grid_destroy':
                        grid = values[0]
                        actual.pop(grid, None)
                        logical.pop(grid, None)
                        owners.pop(grid, None)
                        visible.discard(grid)
                    elif name == 'grid_line':
                        grid, row, column, cells = values[:4]
                        assert grid in actual, ('text before allocation', values)
                        width, height = actual[grid]
                        end = column + sum(cell[2] if len(cell) >= 3 else 1 for cell in cells)
                        assert 0 <= row < height and 0 <= column <= end <= width, (values, actual[grid])
                        events[name] += 1

    def book_grid():
        return next(grid for grid, owner in owners.items() if owner == book_window and grid in visible)

    sent = {}
    requests = []

    def apply_viewport(active, stale_snapshot_width=None):
        """Latest win_pos wins over an older Notebook notification's width."""
        grid = book_grid()
        host = logical[grid][0]
        target = max(1, host - 2) if active else host
        height = actual[grid][1]
        if actual[grid] != (target, height):
            # A real layout change invalidates a previous sent target. Feedback
            # grid_resize alone must neither replace host nor create a retry.
            token = (grid, host, target, height)
            if sent.get(grid) != token:
                sent[grid] = token
                requests.append({'host': host, 'target': target, 'stale_snapshot': stale_snapshot_width})
                editor.api.ui_try_resize_grid(grid, target, height)
        drain()
        assert logical[grid][0] == host, 'text-grid feedback changed logical host'
        assert actual[grid][0] == target, (active, host, actual[grid], target)
        assert editor.api.win_get_width(book_window) == host
        return host, grid

    drain()
    first_host, grid = apply_viewport(True)
    assert first_host == 160 and actual[grid][0] == 158
    assert logical[grid][0] != actual[grid][0], 'real actual and logical dimensions must differ'
    stages = []
    for target in (81, 160, 81, 160, 81):
        old_host = logical[grid][0]
        old_height = actual[grid][1]
        away = 160 if target == 81 else 81
        # Queue without barriers: an old text-grid request can arrive between
        # real layout resize events and tab hide/show notifications.
        editor.request('nvim_ui_try_resize', away, 32, async_=True)
        editor.request('nvim_ui_try_resize_grid', grid, old_host - 2, old_height, async_=True)
        editor.request('nvim_command', 'tabnext', async_=True)
        editor.request('nvim_ui_try_resize', target, 32, async_=True)
        editor.request('nvim_command', 'tabprevious', async_=True)
        drain()
        host, grid = apply_viewport(True, stale_snapshot_width=old_host)
        assert host == target
        stages.append({'logical': host, 'actual': actual[grid][0]})

    latest_host = logical[grid][0]
    assert latest_host == 81 and latest_host != first_host
    restored_host, grid = apply_viewport(False, stale_snapshot_width=first_host)
    assert restored_host == 81 and actual[grid][0] == 81, 'clearing must restore newest host, never initial 160'
    assert differences and events['grid_line'] > 0
    assert editor.api.buf_get_lines(book, 0, -1, False) == source
    assert editor.api.buf_get_changedtick(book) == changedtick
    assert editor.api.buf_line_count(book) == len(source) and not editor.api.buf_get_option(book, 'modified')
    print(json.dumps({'events': events, 'actual_logical_differences': len(differences), 'stages': stages,
                      'restore_latest_width': actual[grid][0], 'stale_initial_width': first_host,
                      'source_unchanged': True, 'grid_lines_within_actual_allocation': True, 'resize_requests': len(requests)}))
finally:
    try:
        editor.command('qa!')
    except (EOFError, OSError):
        pass
