"""Pinned plugin popup captions in real multigrid frames, isolated from user buffers.

Uses the existing Notebook Python (pynvim/msgpack); GLOW_TEST_CONFIG selects config.
Scratch files are temporary. No code execution, shell, kernel, installation or GUI.
"""
from pathlib import Path
import json
import os
import tempfile

import msgpack
import pynvim

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get('GLOW_TEST_CONFIG', ROOT / 'portable/payload/nvim'))
PLUGINS = Path.home() / '.local/share/nvim/lazy'


def run(theme):
    editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '-n'])
    tmp = tempfile.TemporaryDirectory(prefix='glow-caption-')
    try:
        editor.ui_attach(140, 48, rgb=True, ext_multigrid=True)
        editor.exec_lua('''
          local config,plugins,theme,work,old_material=...
          vim.opt.rtp={config,plugins..'/snacks.nvim',plugins..'/which-key.nvim',plugins..'/nui.nvim',vim.env.VIMRUNTIME}
          vim.g.neovide=true;vim.g.neovide_normal_opacity=.85;vim.g.glow_ui_language='en'
          local original=vim.fn.stdpath
          vim.fn.stdpath=function(name)return (name=='state' or name=='data') and work or original(name)end
          local colors=require('config.appearance.themes.ayu_'..theme..'_customed')
          package.loaded.base46={get_theme_tb=function(kind)return colors[kind] or {} end}
          vim.o.background=theme
          local function rgb(key)return tonumber(colors.base_30[key]:sub(2),16)end
          vim.api.nvim_set_hl(0,'Normal',{fg=rgb('white'),bg=rgb('black')})
          vim.api.nvim_set_hl(0,'NormalFloat',{link='Normal'})
          vim.api.nvim_set_hl(0,'FloatTitle',{fg=rgb('blue'),bg=rgb('one_bg2'),bold=true})
          vim.api.nvim_set_hl(0,'FloatFooter',{fg=rgb('green'),bg=rgb('one_bg3')})
          vim.api.nvim_set_hl(0,'CaptionIcon',{fg=rgb('purple'),bg=rgb('one_bg')})
          vim.api.nvim_set_hl(0,'DiagnosticVirtualTextInfo',{fg=rgb('blue'),bg=rgb('one_bg2')})
          vim.api.nvim_set_hl(0,'DiagnosticInfo',{fg=rgb('green'),bg=rgb('one_bg3')})
          vim.api.nvim_set_hl(0,'Visual',{fg=rgb('white'),bg=rgb('blue')})
          _global=vim.api.nvim_get_hl(0,{})
          _normal=vim.api.nvim_get_hl(0,{name='Normal'})
          if old_material~='' then
            package.loaded['config.appearance.popups']=assert(loadfile(old_material))()
          end
          _material=require('config.appearance.popups')
          require('config.appearance.transparency').setup()
          require('snacks').setup({scratch={root=work},picker={enabled=true,ui_select=true},input={enabled=true},
            notifier={enabled=true,style='compact',timeout=0}})
          vim.api.nvim_exec_autocmds('User',{pattern='LazyLoad',data='snacks.nvim'})
          _locale=require('config.platform.locale');_locale.set_lang('en',{save=false,silent=true})
          _work=work
          function _captions(win)
            local config=vim.api.nvim_win_get_config(win)
            local ns=vim.api.nvim_get_hl_ns({winid=win})
            local h=vim.api.nvim_get_hl(ns,{})
            local ret={win=win,height=config.height,width=config.width,labels={},groups={}}
            for _,field in ipairs({'title','footer'})do
              for _,chunk in ipairs(type(config[field])=='table' and config[field] or {})do
                table.insert(ret.labels,chunk[1])
                local name=type(chunk[2])=='number' and vim.api.nvim_get_hl_name_by_id(chunk[2]) or chunk[2]
                local value=h[name] or {}
                assert(value.bg==_normal.bg and value.blend==15,field..' material '..name..' '..vim.inspect(value)..' state '..vim.inspect(vim.w[win].glow_popup_material)..' config '..vim.inspect(config))
                table.insert(ret.groups,{name=name,attrs=value})
              end
            end
            return ret
          end
        ''', str(CONFIG), str(PLUGINS), theme, tmp.name, os.environ.get('GLOW_TEST_MATERIAL_BASE', ''))
        attrs, grids, cells = {}, {}, {}

        def collect(wanted=None):
            first = {}
            while editor._session._pending_messages:
                m = editor._session._pending_messages.popleft()
                if m[0] != 'notification' or m[1] != 'redraw':
                    continue
                for event in m[2]:
                    for values in event[1:]:
                        if event[0] == 'hl_attr_define':
                            attrs[values[0]] = values[1]
                        elif event[0] == 'win_float_pos':
                            grids[values[0]] = msgpack.unpackb(values[1].data)
                        elif event[0] == 'grid_clear':
                            cells[values[0]] = {}
                        elif event[0] == 'grid_line':
                            grid, row, col, entries, *_ = values
                            current = cells.setdefault(grid, {})
                            hl = 0
                            for entry in entries:
                                if len(entry) > 1:
                                    hl = entry[1]
                                for _ in range(entry[2] if len(entry) > 2 else 1):
                                    current[row, col] = entry[0], hl
                                    col += 1
                        elif event[0] in ('win_hide', 'win_close'):
                            grids.pop(values[0], None)
                    if event[0] == 'flush' and wanted:
                        for grid, win in grids.items():
                            if win not in wanted or win in first:
                                continue
                            caption = [(char, attrs.get(hl, {})) for (row, _), (char, hl) in cells.get(grid, {}).items()
                                       if (wanted[win].get('body') or row in (0, wanted[win]['height'] + 1)) and char.strip()]
                            if not caption:
                                continue
                            for char, actual in caption:
                                assert actual.get('background') == normal['bg'] and actual.get('blend', 0) == 15, \
                                    f'{theme} caption first frame {char!r}: {actual}'
                            first[win] = len(caption)
            return first

        normal = editor.exec_lua('return _normal')
        collect()
        scratch = editor.exec_lua('''
          _scratch=Snacks.scratch({file=_work..'/probe.lua',ft='lua',autowrite=false,icon={'λ','CaptionIcon'},
            win={backdrop=false,width=75,height=8}})
          vim.api.nvim_buf_set_lines(_scratch.buf,0,-1,false,{'Diagnostic selection stays opaque'})
          vim.api.nvim_buf_set_extmark(_scratch.buf,vim.api.nvim_create_namespace('caption-semantic'),0,0,
            {end_col=10,hl_group='DiagnosticVirtualTextInfo'})
          vim.cmd('redraw!')
          return _captions(_scratch.win)
        ''')
        assert 'Scratch' in ''.join(scratch['labels']) and 'Run buffer' in ''.join(scratch['labels'])
        seen = collect({scratch['win']: scratch})
        assert scratch['win'] in seen, 'Scratch actual first border frame absent'
        if os.environ.get('GLOW_TEST_MATERIAL_BASE'):
            editor.exec_lua('''
              local hot_apply=...
              local snacks_win=require('snacks.win')
              local win_opts=snacks_win.win_opts
              snacks_win._glow_caption_locale[_scratch]=nil
              vim.api.nvim_win_set_config(_scratch.win,{title=_scratch.opts.title,footer=_scratch.opts.footer})
              vim.g.glow_ui_language='zh'
              dofile(hot_apply)
              local adopted=_captions(_scratch.win)
              assert(table.concat(adopted.labels):find('运行当前 buffer',1,true),'hot update must adopt existing captions')
              assert(snacks_win.win_opts==win_opts,'locale hot update must not stack caption wrappers')
              package.loaded['config.appearance.popups']=assert(loadfile(vim.env.GLOW_TEST_MATERIAL_BASE))()
              _material=package.loaded['config.appearance.popups']
              require('nui.popup');_material.apply()
              local border=require('nui.popup.border')
              local old, original=border._open_window
              for index=1,20 do
                local name,value=debug.getupvalue(old,index)
                if not name then break end
                if name=='original' then original=value;break end
              end
              assert(original,'old marked Nui closure must be exercised')
              local api_open,api_command=vim.api.nvim_open_win,vim.api.nvim_command
              package.loaded['config.appearance.popups']=nil
              _material=require('config.appearance.popups');_material.apply()
              local utils=require('nui.utils')._
              assert(utils._glow_popup_material_hooks.originals['border:_open_window']==original,
                'hot migration must unwrap old own closure instead of stacking')
              local current,option,show=border._open_window,utils.set_win_option,require('snacks.win').show
              package.loaded['config.appearance.popups']=nil
              _material=require('config.appearance.popups');_material.apply()
              assert(current==border._open_window and option==utils.set_win_option and show==require('snacks.win').show,
                'repeated hot update must keep exactly one provider hook')
              assert(api_open==vim.api.nvim_open_win and api_command==vim.api.nvim_command,'no global API wrappers')
            ''', str(ROOT / 'target/glow-parallels-20261021-qa/hotapply-popup-captions.lua'))
        editor.exec_lua('''
          local ns=vim.api.nvim_get_hl_ns({winid=_scratch.win})
          local h=vim.api.nvim_get_hl(ns,{})
          assert((h.DiagnosticVirtualTextInfo or _global.DiagnosticVirtualTextInfo).bg==_global.DiagnosticVirtualTextInfo.bg,
            'caption fix must not clear the same diagnostic group in the body')
          assert(vim.deep_equal(vim.api.nvim_get_hl(0,{name='CaptionIcon'}),_global.CaptionIcon),'global icon changed')
          local path=vim.api.nvim_buf_get_name(_scratch.buf)
          local content=vim.api.nvim_buf_get_lines(_scratch.buf,0,-1,false)
          for _,lang in ipairs({'zh','en','zh'})do
            _locale.set_lang(lang,{save=false,silent=true})
            local result=_captions(_scratch.win)
            local labels=table.concat(result.labels)
            assert(labels:find(lang=='zh' and '运行当前 buffer' or 'Run buffer',1,true),labels)
            assert(labels:find(lang=='zh' and '关闭' or 'Close',1,true),labels)
            assert(vim.api.nvim_buf_get_name(_scratch.buf)==path and vim.deep_equal(content,vim.api.nvim_buf_get_lines(_scratch.buf,0,-1,false)))
          end
          _scratch:destroy()
        ''')
        cases = []
        for name, code in [
            ('picker', "_active=Snacks.picker({items={{text='alpha'},{text='beta'}},layout={preset='default',preview=true}})"),
            ('select', "_active=vim.ui.select({'one','two'},{prompt='GitHub'},function()end)"),
            ('input', "_active=Snacks.input({prompt='File name',default='untouched'},function()end)"),
            ('notification', "Snacks.notifier.notify('Message body','info',{title='Notification title',timeout=0})"),
            ('dialog', """_dialog=require('nui.popup')({relative='editor',position='50%',size={width=50,height=4},
              border={style='rounded',text={top=require('nui.text')('Confirmation','CaptionIcon'),bottom='Choose an action'}},
              win_options={winhighlight='Normal:NormalFloat,FloatBorder:FloatBorder'}});_material.apply();
              vim.api.nvim_buf_set_lines(_dialog.bufnr,0,-1,false,{'Body text'});_dialog:mount()"""),
            ('dialog_default', """_dialog=require('nui.popup')({relative='editor',position='50%',size={width=50,height=4},
              border={style='rounded',text={top=require('nui.text')('Default options','CaptionIcon'),bottom='Footer'}}});
              vim.api.nvim_buf_set_lines(_dialog.bufnr,0,-1,false,{'Body text'});_dialog:mount()"""),
        ]:
            collect()
            editor.exec_lua(code + ';vim.wait(70);vim.cmd("redraw!")')
            windows = editor.exec_lua('''
              local ret={}
              for _,win in ipairs(vim.api.nvim_list_wins())do
                local c=vim.api.nvim_win_get_config(win)
                if c.relative~='' and (c.title or c.footer)then ret[#ret+1]=_captions(win)end
              end
              return ret
            ''')
            if name.startswith('dialog'):
                dialog = editor.exec_lua('''
                  local win=_dialog.border.winid
                  local h=vim.api.nvim_get_hl(vim.api.nvim_get_hl_ns({winid=win}),{})
                  for _,group in ipairs(vim.w[win].glow_popup_caption_groups or {})do
                    assert(h[group].bg==_normal.bg and h[group].blend==15,'Nui border caption '..group)
                  end
                  assert(h.CaptionIcon,'real Nui title must use local source highlight')
                  return {{win=win,height=vim.api.nvim_win_get_height(win)-2},
                    {win=_dialog.winid,height=vim.api.nvim_win_get_height(_dialog.winid),body=true}}
                ''')
                windows.extend(dialog)
            assert windows, f'{name} has no real caption windows'
            first_caption = collect({win['win']: win for win in windows})
            assert first_caption, f'{name} caption first frame absent'
            cases.append({'kind': name, 'caption_windows': len(windows)})
            editor.exec_lua('''
              if _active then if _active.destroy then _active:destroy() else _active:close()end;_active=nil end
              if _dialog then _dialog:unmount();_dialog=nil end;Snacks.notifier.hide();vim.wait(30)
            ''')
        return {'theme': theme, 'scratch_first_frame_characters': seen[scratch['win']], 'cases': cases}
    finally:
        try:
            editor.command('qa!')
        except (EOFError, OSError):
            pass
        tmp.cleanup()


print(json.dumps([run(theme) for theme in ('dark', 'light')]))
