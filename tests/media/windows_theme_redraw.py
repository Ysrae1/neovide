"""Isolated theme replay with the pinned Neo-tree and a real multigrid UI.

Run with the existing Notebook Python and --config local/portable path.
Windows detection is simulated on this host; this does not certify GPU pixels.
No existing session, user buffer, plugin install or system appearance is changed.
"""
import argparse
import json
import os
from pathlib import Path
import tempfile

import pynvim

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config', type=Path, required=True)
args = parser.parse_args()
config = str(args.config.expanduser().resolve())
plugins = str(Path.home() / '.local/share/nvim/lazy')
results = []

for platform in ('windows', 'macos', 'linux', 'windows-terminal'):
    with tempfile.TemporaryDirectory(prefix='glow-theme-redraw-') as temporary:
        work = Path(temporary)
        (work / 'fixture.txt').write_text('isolated fixture\n')
        previous = {key: os.environ.get(key) for key in ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME')}
        for key in previous:
            os.environ[key] = str(work / key.lower())
        editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '-n'])
        try:
            editor.ui_attach(100, 24, rgb=True, ext_multigrid=True, ext_messages=True)
            editor.exec_lua(r'''
              local config,plugins,work,platform=...
              vim.opt.rtp={config,plugins..'/ui',plugins..'/base46',plugins..'/plenary.nvim',
                plugins..'/nui.nvim',plugins..'/neo-tree.nvim',plugins..'/nvim-web-devicons',vim.env.VIMRUNTIME}
              vim.g.base46_cache=work..'/cache/'
              vim.fn.mkdir(vim.g.base46_cache,'p')
              -- Keep normal plugin defaults, without the user's init or integrations.
              package.loaded.chadrc={}
              local conf=require('nvconfig')
              conf.base46.theme='ayu_dark';conf.base46.transparency=false
              conf.base46.integrations={'neo-tree'}
              conf.base46.changed_themes={
                ayu_dark=require('config.appearance.themes.ayu_dark_customed'),
                ayu_light=require('config.appearance.themes.ayu_light_customed')}
              vim.g.neovide=platform~='windows-terminal'
              vim.g.colors_name='nvchad'
              vim.api.nvim_buf_set_lines(0,0,-1,false,{'unsaved fixture text'})
              _editor_buf=vim.api.nvim_get_current_buf()
              require('neo-tree').setup({enable_git_status=false,enable_diagnostics=false,
                filesystem={use_libuv_file_watcher=false},window={width=30}})
              require('neo-tree.command').execute({action='focus',source='filesystem',dir=work})
              assert(vim.bo.filetype=='neo-tree','real Neo-tree must own focus')
              -- Neo-tree was initialized using the host's genuine path semantics.
              local real_has=vim.fn.has
              vim.fn.has=function(feature)
                if feature=='win32' then return platform:match('^windows') and 1 or 0 end
                return real_has(feature)
              end
              _commands={}
              local command=vim.cmd
              vim.cmd=setmetatable({}, {__index=function(_,key)return command[key]end,
                __call=function(_,value) _commands[#_commands+1]=value;return command(value)end})
              require('config.appearance.base46').setup()
              require('base46').load_all_highlights()
              vim.wait(100)
              _before={win=vim.api.nvim_get_current_win(),buf=vim.api.nvim_get_current_buf(),
                cursor=vim.api.nvim_win_get_cursor(0),text=vim.api.nvim_buf_get_lines(_editor_buf,0,-1,false),
                dirty=vim.bo[_editor_buf].modified}
            ''', config, plugins, temporary, platform)
            editor.eval('1')
            editor._session._pending_messages.clear()
            for theme in ('light', 'dark'):
                result = editor.exec_lua(r'''
                  local theme,platform=...
                  _commands={}
                  require('nvconfig').base46.theme='ayu_'..theme
                  require('base46').load_all_highlights()
                  vim.wait(100)
                  local after={win=vim.api.nvim_get_current_win(),buf=vim.api.nvim_get_current_buf(),
                    cursor=vim.api.nvim_win_get_cursor(0),text=vim.api.nvim_buf_get_lines(_editor_buf,0,-1,false),
                    dirty=vim.bo[_editor_buf].modified}
                  assert(vim.deep_equal(_before,after),'theme replay changed focus, content, cursor or dirty state')
                  assert(vim.bo.filetype=='neo-tree' and vim.o.background==theme,'focused tree or mode changed')
                  local full,status=0,0
                  for _,command in ipairs(_commands)do
                    if command=='redraw!' then full=full+1 end
                    if command=='redrawstatus!' then status=status+1 end
                  end
                  assert(full==(platform=='windows' and 1 or 0),'full repaint must occur once only in Windows Neovide')
                  assert(status==(platform=='windows' and 0 or 1),'other paths must retain their status redraw')
                  return {theme=theme,normal=vim.api.nvim_get_hl(0,{name='Normal',link=false}).bg,
                    full_redraws=full,status_redraws=status,dirty=after.dirty,tree_focus=true}
                ''', theme, platform)
                editor.eval('1')
                events = []
                while editor._session._pending_messages:
                    message = editor._session._pending_messages.popleft()
                    if message[0] == 'notification' and message[1] == 'redraw':
                        events.extend(event[0] for event in message[2])
                assert 'flush' in events and 'grid_line' in events, (platform, theme, events)
                result.update(platform=platform, ui_flush=True, grid_lines=True)
                results.append(result)
        finally:
            try:
                editor.command('qa!')
            except (EOFError, OSError):
                pass
            editor.close()
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

print(json.dumps({'status': 'passed', 'config': config, 'scenarios': results}, indent=2))
