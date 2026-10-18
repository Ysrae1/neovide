#!/usr/bin/env python3
"""One isolated live Molten run: semantic chunks, exact text, one output writer."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

import pynvim


PROBE = '''
from contextvars import ContextVar
import pynvim
from pynvim import Nvim
from molten.outputbuffer import OutputBuffer

active = ContextVar('glow_output_write', default=None)
observations = []
violations = []
original_request = Nvim.request
original_build = OutputBuffer.build_output_text
adapted_show = OutputBuffer.show_virtual_output

def build(self, *args):
    result = original_build(self, *args)
    current = active.get()
    if current is not None and args[-1]: current['raw'] = result[0]
    return result

def request(self, name, *args, **kwargs):
    if name == 'nvim_buf_set_extmark' and isinstance(args[-1], dict) and 'virt_lines' in args[-1]:
        current = active.get()
        if current is None:
            violations.append('output mark written outside Molten show_virtual_output')
        else:
            current['writes'] += 1
            actual = [''.join(chunk[0] for chunk in line) for line in args[-1]['virt_lines']]
            if actual != current.get('raw'): violations.append('output text changed')
            observations.append({'state': current['state'], 'writes': current['writes'], 'raw_equal': actual == current.get('raw')})
    return original_request(self, name, *args, **kwargs)

def show(self, anchor):
    original_nvim = self.nvim
    token = active.set({'state': self.output.status.name, 'writes': 0})
    try:
        return adapted_show(self, anchor)
    finally:
        current = active.get()
        if current['writes'] > 1: violations.append('multiple writes for a single Molten render')
        if self.nvim is not original_nvim: violations.append('Nvim proxy was not restored')
        active.reset(token)

Nvim.request = request
OutputBuffer.build_output_text = build
OutputBuffer.show_virtual_output = show

@pynvim.function('GlowOutputProbe', sync=True)
def report(_nvim, _args):
    return {'observations': observations, 'violations': violations}
'''


def main():
    root = Path(__file__).resolve().parents[2]
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nvim'
    with tempfile.TemporaryDirectory(prefix='glow-output-colors-') as temporary:
        work = Path(temporary)
        manifest = work / 'rplugin.vim'
        init = work / 'init.lua'
        probe = work / 'glow_output_probe.py'
        probe.write_text(PROBE)
        init.write_text('\n'.join([
            'vim.opt.rtp:prepend(' + json.dumps(str(root / 'portable/payload/nvim')) + ')',
            'vim.opt.rtp:append(' + json.dumps(str(data / 'lazy/molten-nvim')) + ')',
            "package.preload['config.media.molten_images']=function() return {setup=function() return false end} end",
            "require('config.media.runtime').configure_molten()",
            "vim.fn['remote#host#RegisterPlugin']('python3', " + json.dumps(str(probe)) + ", {{type='function',name='GlowOutputProbe',sync=1,opts=vim.empty_dict()}})",
            "vim.api.nvim_create_autocmd('User',{pattern='MoltenKernelReady',callback=function() vim.g.output_test_ready=true end})",
        ]))
        env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
        subprocess.run(['nvim', '--headless', '-i', 'NONE', '-n', '-u', str(init), '+UpdateRemotePlugins', '+qa'],
                       env=env, check=True, timeout=20, capture_output=True, text=True)
        previous = os.environ.get('NVIM_RPLUGIN_MANIFEST')
        os.environ['NVIM_RPLUGIN_MANIFEST'] = str(manifest)
        editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-i', 'NONE', '-n', '-u', str(init)])
        try:
            source = ['# %%', 'import time; time.sleep(0.2)', "print('Out[99]: ✗ Failed is ordinary result text')", '6 * 7', '', '# %%', "raise ValueError('expected colored error')", '']
            editor.current.buffer[:] = source
            editor.current.buffer.options['filetype'] = 'python'
            editor.command('MoltenInit glow-python')

            def wait_until(predicate, description):
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    if predicate(): return
                    time.sleep(0.05)
                raise AssertionError(description + ': ' + editor.command_output('messages'))

            wait_until(lambda: editor.eval("get(g:,'output_test_ready',v:false)"), 'kernel ready')
            info = editor.funcs.GlowNotebookOutputAdapterInfo()
            assert info['active'], info
            editor.funcs.MoltenEvaluateRange('glow-python', 2, 4, 1, len(source[3]) + 1)
            editor.funcs.MoltenEvaluateRange('glow-python', 7, 7, 1, len(source[6]) + 1)

            def outputs():
                namespace = editor.api.get_namespaces()['molten-extmarks']
                return [mark[3]['virt_lines'] for mark in editor.api.buf_get_extmarks(0, namespace, 0, -1, {'details': True}) if 'virt_lines' in mark[3]]

            def completed():
                text = [str(lines[0]) for lines in outputs()]
                return any('✓ Done' in line for line in text) and any('✗ Failed' in line for line in text)

            wait_until(completed, 'coexisting Done and Failed')
            final = outputs()
            assert len(final) == 2, final
            for lines in final:
                header = lines[0]
                text = ''.join(chunk[0] for chunk in header)
                failed = '✗ Failed' in text
                state_group = 'GlowNotebookOutputFailure' if failed else 'GlowNotebookOutputSuccess'
                assert any(chunk[1] == 'GlowNotebookOutputNumber' and chunk[0].startswith('Out[') for chunk in header), header
                assert any(chunk[1] == state_group for chunk in header), header
                assert not any(chunk[1] == ('GlowNotebookOutputSuccess' if failed else 'GlowNotebookOutputFailure') for chunk in header), header
                body = lines[1:]
                assert all(chunk[1] == ('GlowNotebookOutputError' if failed else 'MoltenVirtualText') for line in body for chunk in line), body
                if not failed:
                    assert any('Out[99]: ✗ Failed' in chunk[0] for line in body for chunk in line)
                    assert any(chunk[0] == '42' for line in body for chunk in line)
            report = editor.funcs.GlowOutputProbe()
            assert report['observations'] and not report['violations'], report
            assert all(item['writes'] == 1 and item['raw_equal'] for item in report['observations']), report
            assert editor.current.buffer[:] == source
            editor.command('MoltenDeinit')
            assert editor.funcs.MoltenRunningKernels() == []
            print(json.dumps({'done_green': True, 'failed_red': True, 'out_accent': True, 'normal_results': True, 'raw_text_unchanged': True,
                              'single_writer': True, 'provider_proxy_restored': True, 'observed_writes': len(report['observations']), 'kernels_after_close': []}))
        finally:
            try: editor.command('qa!')
            except (EOFError, OSError): pass
            if previous is None: os.environ.pop('NVIM_RPLUGIN_MANIFEST', None)
            else: os.environ['NVIM_RPLUGIN_MANIFEST'] = previous


if __name__ == '__main__':
    main()
