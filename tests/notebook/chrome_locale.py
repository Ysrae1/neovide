#!/usr/bin/env python3
"""Real pinned Molten/NeoTree renderers; no kernel, notebook execution or user UI."""
from pathlib import Path
from types import SimpleNamespace
import copy
import importlib.util
import os
import sys
import tempfile

import pynvim

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get('GLOW_TEST_CONFIG', Path.home() / '.config/nvim'))
PLUGINS = Path.home() / '.local/share/nvim/lazy'
MOLTEN = PLUGINS / 'molten-nvim/rplugin/python3'
sys.path.insert(0, str(MOLTEN))
sys.argv.append(str(MOLTEN / 'molten'))
from molten.images import NoCanvas
from molten.outputbuffer import OutputBuffer
from molten.outputchunks import Output, OutputStatus, TextOutputChunk, ErrorOutputChunk

spec = importlib.util.spec_from_file_location('glow_chrome_adapter_test', CONFIG / 'lua/config/media/runtime/glow_molten_output.py')
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
assert adapter._info['active'], adapter._info

with tempfile.TemporaryDirectory(prefix='glow-chrome-locale-') as work:
    nvim = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '-n'])
    try:
        nvim.ui_attach(100, 35, rgb=True)
        nvim.exec_lua('''
          local config, plugins, work = ...
          vim.opt.rtp = {config, vim.env.VIMRUNTIME}
          for _, name in ipairs({'neo-tree.nvim','nui.nvim','plenary.nvim','molten-nvim'}) do vim.opt.rtp:append(plugins..'/'..name) end
          local stdpath=vim.fn.stdpath
          vim.fn.stdpath=function(name) return name=='state' and work or name=='config' and (work..'/config') or stdpath(name) end
          vim.g.glow_ui_language='en';vim.env.LANG='en_US.UTF-8';vim.env.LC_ALL='en_US.UTF-8'
          package.loaded['config.platform.locale_ui']={setup=function()end,refresh=function()end}
          _locale=require('config.platform.locale')
          vim.o.laststatus=0;vim.o.showmode=false
        ''', str(CONFIG), str(PLUGINS), work)
        source = ['# %%', 'user_code_must_not_run()', '', '# %%', "raise ValueError('Done')"] + [''] * 20
        nvim.current.buffer[:] = source
        nvim.current.buffer.options['modified'] = False
        buf = nvim.current.buffer.number
        ns = nvim.api.create_namespace('molten-extmarks')
        options = SimpleNamespace(cover_empty_lines=False, virt_lines_off_by_1=False,
            virt_text_max_lines=6, virt_text_truncate='bottom', output_show_exec_time=False,
            image_provider='image.nvim', image_location='float', limit_output_chars=0,
            wrap_output=False, hl=SimpleNamespace(virtual_text='MoltenVirtualText'))
        writer = OutputBuffer(nvim, NoCanvas(), ns, options)
        writer.output = Output(1)
        writer.output.status, writer.output.old = OutputStatus.DONE, True
        printed = '󰁅 17 More lines \n[OLD] Out[1]: ✓ Done\n' + '\n'.join('user output %d' % i for i in range(20))
        writer.output.chunks = [TextOutputChunk(printed)]
        raw_output = copy.deepcopy(writer.output.__dict__)
        raw_chunks = copy.deepcopy([chunk.__dict__ for chunk in writer.output.chunks])
        anchor = SimpleNamespace(bufno=buf, lineno=1)
        writer.show_virtual_output(anchor)
        def lines():
            details = nvim.api.buf_get_extmark_by_id(buf, ns, writer.virt_text_id, {'details': True})[2]
            return [''.join(c[0] for c in row) for row in details['virt_lines']]
        baseline = lines()
        assert baseline[0] == '[OLD] Out[1]: ✓ Done', baseline
        assert baseline[1] == '󰁅 17 More lines ' and baseline[-1].endswith(' More lines ')
        for lang in ['zh', 'en', 'zh', 'en']:
            nvim.exec_lua('_locale.set_lang(...,{save=false,silent=true})', lang)
            rendered = lines()
            if lang == 'zh':
                assert rendered[0] == '[旧输出] Out[1]: ✓ 完成', rendered
                assert rendered[-1].startswith('󰁅 另有 ') and rendered[-1].endswith(' 行 '), rendered
                assert rendered[1] == baseline[1] and rendered[2] == baseline[2], 'user lookalikes translated'
            else:
                assert rendered == baseline, 'English roundtrip lost original bytes'
        assert [chunk.__dict__ for chunk in writer.output.chunks] == raw_chunks, 'Molten stored payload changed'
        assert {k:v for k,v in writer.output.__dict__.items() if k != 'chunks'} == {k:v for k,v in raw_output.items() if k != 'chunks'}, 'Molten execution metadata changed'
        # A printed lookalike in the final (untruncated) row remains user data.
        writer.clear_virt_output(buf)
        writer.output.chunks = [TextOutputChunk('󰁅 17 More lines ')]
        writer.virt_hidden = False
        writer.displayed_status = OutputStatus.NEW
        writer.show_virtual_output(anchor)
        nvim.exec_lua('_locale.set_lang("zh",{save=false,silent=true})')
        assert lines()[1] == '󰁅 17 More lines '
        # Top truncation, running state and exact semantic busy check.
        writer.clear_virt_output(buf)
        from molten.outputbuffer import truncate_top
        writer.truncate_lines = truncate_top
        writer.output.status, writer.output.old = OutputStatus.RUNNING, False
        writer.output.chunks = [TextOutputChunk(printed)]
        writer.virt_hidden = False
        writer.displayed_status = OutputStatus.NEW
        writer.show_virtual_output(anchor)
        assert lines()[0] == 'Out[1]: ... 运行中' and lines()[1].startswith('↑ 另有 '), lines()
        assert nvim.exec_lua('''
          local buf,ns,id=...;local c=require('config.platform.notebook_chrome_locale')
          local m=vim.api.nvim_buf_get_extmark_by_id(buf,ns,id,{details=true})
          return c.status(c.canonical_lines(buf,ns,id,m[3].virt_lines))
        ''', buf, ns, writer.virt_text_id) == 'running'
        # Error trace words and the original Output/chunks stay byte-for-byte.
        writer.clear_virt_output(buf)
        writer.output.status, writer.output.old, writer.output.success = OutputStatus.DONE, False, False
        trace = ['Traceback: Done Running Failed', 'ValueError: [OLD] Out[1] More lines']
        error_chunk = ErrorOutputChunk('ValueError', 'Done', trace)
        error_bytes = copy.deepcopy(error_chunk.__dict__)
        writer.output.chunks = [error_chunk]
        writer.virt_hidden = False
        writer.displayed_status = OutputStatus.NEW
        writer.show_virtual_output(anchor)
        assert lines()[0] == 'Out[1]: ✗ 失败' and lines()[1:] == error_chunk.text.rstrip('\n').split('\n')
        assert error_chunk.__dict__ == error_bytes
        assert nvim.current.buffer[:] == source and not nvim.current.buffer.options['modified']
        assert nvim.eval("exists(':MoltenInit')") == 0, 'test started a kernel-capable plugin'
        # Safe adoption of a pre-upgrade semantic header: no guessed More lines.
        nvim.exec_lua('''
          local ns=vim.api.nvim_create_namespace('molten-extmarks')
          _old=vim.api.nvim_buf_set_extmark(0,ns,12,0,{virt_lines={
            {{'[OLD] ','MoltenVirtualText'},{'Out[8]:','GlowNotebookOutputNumber'},{' ','MoltenVirtualText'},{'✓ Done','GlowNotebookOutputSuccess'}},
            {{'󰁅 17 More lines ','MoltenVirtualText'}}}})
          require('config.platform.notebook_chrome_locale').refresh()
        ''')
        legacy = nvim.api.buf_get_extmark_by_id(buf, ns, nvim.exec_lua('return _old'), {'details': True})[2]['virt_lines']
        assert ''.join(c[0] for c in legacy[0]) == '[旧输出] Out[8]: ✓ 完成'
        assert legacy[1][0][0] == '󰁅 17 More lines '
        popup = nvim.exec_lua('''
          local b=vim.api.nvim_create_buf(false,true)
          vim.api.nvim_buf_set_lines(b,0,-1,false,{'[OLD] Out[8]: ✓ Done','Done More lines','Traceback: Running Failed'})
          vim.bo[b].filetype='molten_output';vim.bo[b].modifiable=false;vim.bo[b].readonly=true
          require('config.platform.notebook_chrome_locale').refresh_popups()
          return b
        ''')
        assert nvim.api.buf_get_lines(popup, 0, -1, False) == ['[旧输出] Out[8]: ✓ 完成', 'Done More lines', 'Traceback: Running Failed']
        nvim.exec_lua('_locale.set_lang("en",{save=false,silent=true})')
        assert nvim.api.buf_get_lines(popup, 0, -1, False) == ['[OLD] Out[8]: ✓ Done', 'Done More lines', 'Traceback: Running Failed']
        assert not nvim.api.buf_get_option(popup, 'modifiable') and nvim.api.buf_get_option(popup, 'readonly')
        tree = nvim.exec_lua('''
          require('neo-tree').setup({enable_git_status=false,enable_diagnostics=false})
          require('neo-tree').ensure_config()
          require('config.navigation.neo_tree_locale').setup()
          local c=require('neo-tree.sources.common.components')
          local Node=require('nui.tree').Node
          local function node(kind,id,name) local n=Node({type=kind,id=id,name=name});n._id=id;n.get_depth=function()return 2 end;return n end
          local generated=node('message','/x/.git_hidden_message','(5 hidden items)')
          local singular=node('message','/x/.git_hidden_message','(1 hidden item)')
          local forced=node('message','/x/.git_hidden_message','(forced to show 5 hidden items)')
          local user=node('file','/x/(5 hidden items)','(5 hidden items)')
          local result={}
          for _,lang in ipairs({'en','zh','en'}) do
            _locale.set_lang(lang,{save=false,silent=true})
            local row={}
            for _,n in ipairs({generated,singular,forced,user}) do row[#row+1]=c.name({right_padding=1},n,{}).text end
            result[#result+1]=row
          end
          assert(generated.name=='(5 hidden items)' and user.name=='(5 hidden items)')
          return result
        ''')
        assert tree[0] == ['(5 hidden items) ', '(1 hidden item) ', '(forced to show 5 hidden items) ', '(5 hidden items) '], tree
        assert tree[1] == ['（5 个隐藏项目） ', '（1 个隐藏项目） ', '（已强制显示 5 个隐藏项目） ', '(5 hidden items) '], tree
        assert tree[2] == tree[0]
        print('PASS:', CONFIG, '| real Molten header/top-bottom folds and NeoTree count en→zh→en; user output/trace/source unchanged; old-host footer left intact')
    finally:
        try: nvim.command('qa!')
        except Exception: pass
