#!/usr/bin/env python3
"""Exercise image maintenance through a real, isolated Neovide window.

Requires pynvim, Pillow, Neovim, Yazi and the existing plenary.nvim/yazi.nvim
plugins. Example (run with the project's existing notebook venv Python):
  gui_maintenance.py --binary target/aarch64-apple-darwin/release/neovide \
    --work-dir /tmp/glow-gui-qa --keep-open

No installed application, user session, configuration or kernel is changed.
RPC/status observers always call the real implementations. Native decode
callbacks, not injected status results, drive every assertion. A visible window
and callbacks establish GUI integration; a human must separately inspect pixels.
In keep-open mode, state.json supplies the socket for screenshots/theme changes;
create the named stop file to finish cleanly, or wait for --hold-seconds.
"""

import argparse
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
from pathlib import Path

import pynvim
from PIL import Image, ImageDraw


OBSERVERS = r"""
_qa = {calls={}, statuses={}}
local notify = vim.rpcnotify
vim.rpcnotify = function(channel, method, ...)
  if method:match('^neovide%.image%.') then
    _qa.calls[#_qa.calls+1] = {method=method, args={...}}
  end
  return notify(channel, method, ...)
end
for _, owner in ipairs({'image', 'molten_images', 'yazi'}) do
  local receiver = require('config.media.'..owner)
  local original = receiver.on_status
  receiver.on_status = function(id, width, height, err)
    _qa.statuses[#_qa.statuses+1] = {owner=owner,id=id,width=width,height=height,
      error=(err and err~=vim.NIL and tostring(err)~='') and tostring(err) or false}
    return original(id, width, height, err)
  end
end
require('config.media.image').setup()
require('config.media.molten_images').setup()
"""


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--work-dir', type=Path)
    parser.add_argument('--config', type=Path, default=Path.home() / '.config/nvim')
    parser.add_argument('--nvim', default=shutil.which('nvim'))
    parser.add_argument('--plugin-root', type=Path,
                        default=Path.home() / '.local/share/nvim/lazy')
    parser.add_argument('--keep-open', action='store_true')
    parser.add_argument('--hold-seconds', type=float, default=600)
    parser.add_argument('--timeout', type=float, default=25)
    return parser.parse_args()


def main():
    args = parse_args()
    binary = args.binary.expanduser().resolve(strict=True)
    installed = [Path('/Applications/Neovide.app'), Path.home() / '.cargo/bin/neovide']
    if any(binary == item or item in binary.parents for item in installed):
        raise SystemExit('--binary must identify a development build, not an installed application')
    if not args.nvim:
        raise SystemExit('Neovim is required')
    for plugin in ('plenary.nvim', 'yazi.nvim'):
        if not (args.plugin_root / plugin).is_dir():
            raise SystemExit('Missing existing plugin: ' + plugin)
    if not shutil.which('yazi'):
        raise SystemExit('Existing Yazi executable is required')
    if args.timeout <= 0 or args.hold_seconds < 0:
        raise SystemExit('timeouts must be positive (hold time may be zero)')
    work = args.work_dir or Path(tempfile.mkdtemp(prefix='glow-gui-'))
    work = work.expanduser().absolute()
    work.mkdir(parents=True, exist_ok=True)
    if (work / 'state.json').exists():
        raise SystemExit('Use a fresh --work-dir; an existing state file may own a live GUI')
    socket = work / 'nvim.sock'
    if len(os.fsencode(socket)) > 100:
        raise SystemExit('--work-dir is too long for a portable Unix socket address')
    stop_file = work / 'stop'
    logs, processes, editor = [], [], None
    finished = threading.Event()
    state = {'phase': 'starting', 'work_dir': str(work), 'socket': str(socket),
             'binary': str(binary), 'config': str(args.config.resolve()),
             'stop_file': str(stop_file), 'results': {}}

    def save_state():
        (work / 'state.json').write_text(json.dumps(state, ensure_ascii=False, indent=2))

    def stop_owned():
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
        for process in reversed(processes):
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)

    def watchdog():
        # Also bounds RPC calls if a regression wedges Neovim's main loop.
        if not finished.wait(180 + (args.hold_seconds if args.keep_open else 0)):
            state['watchdog_timeout'] = True
            stop_owned()

    threading.Thread(target=watchdog, daemon=True).start()
    save_state()
    try:
        for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            (work / kind.lower()).mkdir(exist_ok=True)
        files = work / 'fixtures'
        files.mkdir()
        png = files / "native picture's 图.png"
        picture = Image.new('RGB', (960, 640), '#142737')
        draw = ImageDraw.Draw(picture)
        colors = ('#54bfce', '#ffbd69', '#dd7fa8', '#91c788')
        for index, color in enumerate(colors):
            x, y = index % 2 * 480, index // 2 * 320
            draw.rectangle((x + 12, y + 12, x + 468, y + 308), fill=color)
            draw.line((x + 12, y + 12, x + 468, y + 308), fill='white', width=5)
            draw.text((x + 35, y + 35), f'QUADRANT {index + 1}', fill='#142737')
        picture.save(png)
        broken = files / 'broken.png'
        broken.write_bytes(b'\x89PNG\r\n\x1a\ntruncated')
        fifo = files / 'pipe.png'
        os.mkfifo(fifo, 0o600)
        yazi_home = work / 'yazi'
        yazi_home.mkdir()
        (yazi_home / 'yazi.toml').write_text('[mgr]\nratio=[1,4,3]\n[preview]\nimage_delay=0\n')
        init = work / 'init.lua'
        init.write_text('\n'.join([
            'vim.opt.rtp:prepend(' + json.dumps(str(args.config.resolve())) + ')',
            *['vim.opt.rtp:append(' + json.dumps(str(args.plugin_root / plugin)) + ')'
              for plugin in ('plenary.nvim', 'yazi.nvim')],
            "vim.o.termguicolors=true;vim.o.swapfile=false;vim.o.hidden=true",
            "vim.o.showmode=false;vim.o.laststatus=2;vim.o.showtabline=2",
            "vim.o.title=true;vim.o.titlestring='Neovide Glow isolated GUI maintenance'",
            "vim.o.guifont='FiraCode Nerd Font Mono:h14'",
            "vim.o.background='dark';vim.cmd('colorscheme default')",
            "vim.g.neovide_remember_window_size=false;vim.g.neovide_scale_factor=1.0",
            "vim.g.neovide_bloom=true;vim.g.neovide_bloom_strength=0.20",
        ]))
        neovide_config = work / 'neovide.toml'
        neovide_config.write_text('')
        env = os.environ.copy()
        for key in tuple(env):
            if key.startswith('NEOVIDE_') or key in ('NVIM', 'NVIM_LISTEN_ADDRESS'):
                env.pop(key)
        for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            env[f'XDG_{kind}_HOME'] = str(work / kind.lower())
        env['NEOVIDE_CONFIG'] = str(neovide_config)
        env['TERM'] = 'xterm-256color'
        env['COLORTERM'] = 'truecolor'
        env.pop('NO_COLOR', None)
        for name, command in (
            ('nvim', [args.nvim, '--headless', '--listen', str(socket), '--noplugin',
                      '-u', str(init), '-i', 'NONE', '-n']),
            ('neovide', [str(binary), '--no-fork', '--no-startup-message-capture',
                         '--neovim-bin', args.nvim, '--server', str(socket), '--grid', '110x34']),
        ):
            if name == 'neovide':
                deadline = time.monotonic() + args.timeout
                while not socket.exists():
                    if processes[0].poll() is not None or time.monotonic() > deadline:
                        raise AssertionError('Isolated Neovim socket did not become ready')
                    time.sleep(.05)
            log = (work / (name + '.log')).open('w')
            logs.append(log)
            process = subprocess.Popen(command, env=env, cwd=work,
                                       stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
            processes.append(process)
            state[name + '_pid'] = process.pid
            save_state()
        editor = pynvim.attach('socket', path=str(socket))

        def dismiss_fixture_prompts():
            # Expected corrupt/over-quota diagnostics may trigger hit-enter.
            # A separate fast-API connection can dismiss it even while the
            # assertion connection is waiting for an ordinary Lua RPC.
            peer = pynvim.attach('socket', path=str(socket))
            try:
                while not finished.wait(.05):
                    if peer.api.get_mode().get('blocking'):
                        peer.input('\r')
            except (EOFError, OSError, pynvim.api.common.NvimError):
                pass
            finally:
                peer.close()

        threading.Thread(target=dismiss_fixture_prompts, daemon=True).start()

        def wait(predicate, description, timeout=None):
            deadline = time.monotonic() + (timeout or args.timeout)
            while time.monotonic() < deadline:
                if any(process.poll() is not None for process in processes):
                    raise AssertionError(description + ': an owned process exited; see logs')
                value = predicate()
                if value:
                    return value
                time.sleep(.05)
            raise AssertionError(description + ': timed out\n' + editor.command_output('messages'))

        wait(lambda: editor.exec_lua("return vim.g.neovide_native_image==true and type(vim.g.neovide_channel_id)=='number'"),
             'Native GUI image capability')
        editor.exec_lua(OBSERVERS)
        state['phase'] = 'testing'
        save_state()

        def calls(method):
            return editor.exec_lua('local r={};for _,v in ipairs(_qa.calls)do if v.method==... then r[#r+1]=v end end;return r', method)

        def status(identifier):
            return editor.exec_lua('for i=#_qa.statuses,1,-1 do local v=_qa.statuses[i];if v.id==... then return v end end', identifier)

        def decoded(identifier, owner='image', error=False):
            result = wait(lambda: status(identifier), 'Actual native callback ' + str(identifier))
            assert result['owner'] == owner, result
            assert bool(result['error']) == error, result
            if not error:
                assert (result['width'], result['height']) == (960, 640), result
            else:
                # Expected decoder diagnostics can fill the minimal UI's message
                # area. Dismiss its hit-enter prompt before the next fixture so
                # the final held image is visible without manual intervention.
                editor.input('\r')
                editor.exec_lua("vim.cmd('redraw!')")
            return result

        def ordinary(path, error=False):
            before = len(calls('neovide.image.load'))
            assert editor.exec_lua("return require('config.media.image').open(...)", str(path))
            load = wait(lambda: (items[-1] if len(items := calls('neovide.image.load')) > before else None),
                        'Ordinary image request')
            result = decoded(load['args'][0], error=error)
            if error:
                assert '图片加载失败' in '\n'.join(editor.current.buffer[:])
            editor.exec_lua("require('config.media.image').close()")
            return result

        state['results']['ordinary'] = ordinary(png)
        start = time.monotonic()
        fifo_result = ordinary(fifo, error=True)
        assert 'regular file' in fifo_result['error'], fifo_result
        assert editor.eval('6*7') == 42, 'Editor must respond after FIFO failure'
        fifo_result['elapsed_seconds'] = round(time.monotonic() - start, 3)
        state['results']['fifo'] = fifo_result
        state['results']['corrupt'] = ordinary(broken, error=True)

        def raw_load(path, owner='image'):
            return editor.exec_lua("local path,owner=...;local id=require('config.media.image_transport').allocate(owner);assert(id);vim.rpcnotify(vim.g.neovide_channel_id,'neovide.image.load',id,path,owner);return id", str(path), owner)

        # A failed request must return its reservation without requiring close.
        failed = raw_load(broken)
        decoded(failed, error=True)
        slots = []
        for _ in range(8):
            identifier = raw_load(png)
            decoded(identifier)
            slots.append(identifier)
        rejected = raw_load(png)
        result = decoded(rejected, error=True)
        assert 'maximum 8' in result['error'], result
        editor.exec_lua("vim.rpcnotify(vim.g.neovide_channel_id,'neovide.image.close',...)", slots.pop())
        replacement = raw_load(png)
        decoded(replacement)
        slots.append(replacement)
        for identifier in slots:
            editor.exec_lua("vim.rpcnotify(vim.g.neovide_channel_id,'neovide.image.close',...)", identifier)
        state['results']['quota'] = {'held': 8, 'ninth_rejected': True,
                                     'failed_decode_releases': True, 'close_releases': True}

        # Notebook output cannot consume the two shared interactive slots.
        notebook_slots = []
        for _ in range(6):
            identifier = raw_load(png, 'molten')
            decoded(identifier, 'molten_images')
            notebook_slots.append(identifier)
        rejected = raw_load(png, 'molten')
        assert 'Notebook maximum 6' in decoded(rejected, 'molten_images', error=True)['error']
        interactive = [raw_load(png, owner) for owner in ('image', 'yazi')]
        decoded(interactive[0])
        decoded(interactive[1], 'yazi')
        editor.exec_lua("vim.rpcnotify(vim.g.neovide_channel_id,'neovide.image.close',...)", notebook_slots.pop())
        replacement = raw_load(png, 'molten')
        decoded(replacement, 'molten_images')
        for identifier in notebook_slots + interactive + [replacement]:
            editor.exec_lua("vim.rpcnotify(vim.g.neovide_channel_id,'neovide.image.close',...)", identifier)
        state['results']['fair_quota'] = {'notebook': 6, 'ordinary_image': 1, 'yazi': 1,
                                          'seventh_notebook_deferred': True, 'release_reused': True}

        editor.exec_lua(r"""
          _qa_molten_buf=vim.api.nvim_create_buf(false,true)
          vim.api.nvim_buf_set_lines(_qa_molten_buf,0,-1,false,{'Saved output (no kernel)'})
          _qa_molten_win=vim.api.nvim_open_win(_qa_molten_buf,true,
            {relative='editor',row=2,col=3,width=70,height=25,border='rounded'})
          local api=require('config.media.molten_images').image_api
          api.from_file(...,{id='gui-saved-output',buffer=_qa_molten_buf,window=_qa_molten_win,x=0,y=0})
          api.render('gui-saved-output')
        """, str(png))
        molten_load = wait(lambda: next((item for item in reversed(calls('neovide.image.load'))
                                        if 1000000 < item['args'][0] < 2000000), None), 'Molten native request')
        molten_id = molten_load['args'][0]
        state['results']['molten'] = decoded(molten_id, 'molten_images')
        editor.command('tabnew')
        wait(lambda: any(item['args'][0] == molten_id for item in calls('neovide.image.close')),
             'Molten tab departure releases pixels')
        editor.command('tabprevious')
        reloaded = wait(lambda: next((item for item in reversed(calls('neovide.image.load'))
                                     if 1000000 < item['args'][0] < 2000000 and item['args'][0] != molten_id), None),
                        'Molten returning tab reloads')
        decoded(reloaded['args'][0], 'molten_images')
        editor.exec_lua("require('config.media.molten_images').image_api.clear_all();vim.api.nvim_win_close(_qa_molten_win,true)")
        editor.command('tabonly!')

        editor.exec_lua(r"""
          local config,path=...
          _qa_yazi_opts=require('config.media.yazi').configure({config_home=config,
            hooks={on_yazi_ready=function(_,_,api)_qa_yazi_api=api end}})
          require('yazi').setup(_qa_yazi_opts)
          require('yazi').yazi(nil,path)
        """, str(yazi_home), str(png))
        yazi_load = wait(lambda: next((item for item in reversed(calls('neovide.image.load'))
                                      if item['args'][0] > 2000000), None), 'Actual Yazi native request')
        state['results']['yazi'] = decoded(yazi_load['args'][0], 'yazi')
        wait(lambda: editor.exec_lua("return _qa_yazi_api~=nil"), 'Yazi ready hook before quit')
        yazi_win = editor.current.window.handle
        editor.exec_lua("_qa_yazi_api:emit_to_yazi({'quit'})")
        wait(lambda: not editor.api.win_is_valid(yazi_win), 'Actual Yazi closes')
        wait(lambda: any(item['args'][0] == yazi_load['args'][0] for item in calls('neovide.image.close')),
             'Yazi close releases pixels')
        state['results']['tab_lifecycle'] = True
        state['results']['editor_responsive'] = editor.eval('6*7') == 42
        editor.exec_lua("require('config.media.image').open(...)", str(png))
        last_load = calls('neovide.image.load')[-1]
        decoded(last_load['args'][0])
        editor.exec_lua("vim.cmd('redraw!')")
        state['phase'] = 'holding' if args.keep_open else 'passed'
        state['messages'] = editor.command_output('messages')
        state['observed'] = editor.exec_lua('return _qa')
        save_state()
        print(json.dumps({'result': 'PASS', 'state': str(work / 'state.json'),
                          'socket': str(socket), 'results': state['results']}, ensure_ascii=False), flush=True)
        if args.keep_open:
            deadline = time.monotonic() + args.hold_seconds
            while time.monotonic() < deadline and not stop_file.exists() and processes[-1].poll() is None:
                time.sleep(.2)
        state['phase'] = 'passed'
    except BaseException as error:
        state['phase'], state['error'] = 'failed', repr(error)
        if editor:
            # Avoid another unbounded RPC request while handling a timeout.
            state['last_known_observed'] = state.get('observed')
        raise
    finally:
        finished.set()
        if editor:
            editor.close()
        stop_owned()
        state['owned_processes_stopped'] = True
        save_state()
        for log in logs:
            log.close()


if __name__ == '__main__':
    main()
