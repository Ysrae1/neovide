#!/usr/bin/env python3
"""Real Molten: imported errors survive an owned-kernel switch with fresh output."""
import json
import faulthandler
import os
import subprocess
import tempfile
import time
import runpy
import sys
import threading
from types import SimpleNamespace
from pathlib import Path

import nbformat
import pynvim


def verify_position_destructor(adapter, data):
    sys.path.insert(0, str(data / 'lazy/molten-nvim/rplugin/python3'))
    try:
        from molten.position import DynamicPosition
    finally:
        sys.path.pop(0)
    owner = threading.current_thread()
    calls, pending, errors, unraisable = [], [], [], []
    class Session:
        _loop_thread = owner
        def request(self, name, *args, **_kwargs):
            calls.append((threading.current_thread(), name, args))
            return True
        def threadsafe_call(self, callback):
            pending.append(callback)
    nvim = pynvim.Nvim(Session(), 1, {'version': {}}, {}, err_cb=errors.append)
    def holder():
        position = DynamicPosition.__new__(DynamicPosition)
        position.nvim, position.bufno, position.extmark_namespace, position.extmark_id = nvim, 7, 11, 13
        return [position]
    def collect(items):
        worker = threading.Thread(target=items.clear)
        worker.start()
        worker.join(timeout=2)
        assert not worker.is_alive()
    original, original_hook = DynamicPosition.__del__, sys.unraisablehook
    try:
        sys.unraisablehook = lambda event: unraisable.append(event.exc_value)
        collect(holder())  # Actual class finalizer, original pynvim thread guard.
        assert len(unraisable) == 1 and 'non-main thread' in str(unraisable[0]) and not calls
        assert len(pending) == 1
        pending.pop(0)()
        assert 'position.py' in errors[0] and '__del__' in errors[0], errors
        DynamicPosition.__del__ = adapter['_main_thread_position_destructor'](original)
        collect(holder())
        assert len(unraisable) == 1 and not calls and len(pending) == 1, 'background finalizer must only enqueue'
        pending.pop(0)()
        assert len(calls) == 1 and calls[0][0] is owner and calls[0][1] == 'nvim_call_function', calls
        assert calls[0][2][0] == 'nvim_buf_del_extmark' and list(calls[0][2][1]) == [7, 11, 13], calls
        holder().clear()
        assert len(calls) == 2 and calls[1][0] is owner and not pending, 'main-thread behavior remains direct'
        def fail(_position):
            raise RuntimeError('original destructor error')
        try:
            adapter['_main_thread_position_destructor'](fail)(SimpleNamespace(nvim=nvim))
        except RuntimeError as error:
            assert str(error) == 'original destructor error'
        else:
            raise AssertionError('original main-thread error swallowed')
    finally:
        DynamicPosition.__del__, sys.unraisablehook = original, original_hook
    print('position cleanup: actual background destructor reproduces thread guard; queued main-thread cleanup passes', flush=True)


def main():
    faulthandler.dump_traceback_later(35)
    root = Path(__file__).resolve().parents[2]
    adapter = runpy.run_path(str(root / 'portable/payload/nvim/lua/config/media/runtime/glow_molten_output.py'))
    extras = {'output_type': 'error', 'data': None, 'metadata': {'keep': True},
              'ename': 'ValueError', 'evalue': 'saved-only-error', 'traceback': ['saved trace']}
    chunk = SimpleNamespace(output_type='error', jupyter_metadata=None, extras=extras)
    kernel = SimpleNamespace(outputs={1: SimpleNamespace(output=SimpleNamespace(chunks=[chunk]))})
    def failed_export(*_args):
        assert chunk.extras == {key: value for key, value in extras.items() if key not in {'output_type', 'data'}}
        raise RuntimeError('test exporter failed')
    try:
        adapter['_export_without_duplicate_error_fields'](failed_export)(None, kernel, 'unused', True)
    except RuntimeError as error:
        assert str(error) == 'test exporter failed'
    assert chunk.extras is extras, 'failed original exporter did not restore exact error payload'
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nvim'
    verify_position_destructor(adapter, data)
    with tempfile.TemporaryDirectory(prefix="glow kernel's outputs ") as temporary:
        work = Path(temporary)
        notebook = work / "saved error's output.ipynb"
        original = nbformat.v4.new_notebook(
            metadata={'kernelspec': {'name': 'python3', 'language': 'python', 'display_name': 'Python 3'},
                      'preserved': {'owner': 'user'}},
            cells=[nbformat.v4.new_code_cell('a = 6\na * 7', execution_count=7,
                        outputs=[nbformat.v4.new_output('execute_result', data={'text/plain': '36'}, execution_count=7)]),
                   nbformat.v4.new_code_cell("raise ValueError('saved-only-error')", execution_count=8,
                        outputs=[nbformat.v4.new_output('error', ename='ValueError', evalue='saved-only-error',
                                                        traceback=['Traceback (saved only)', 'ValueError: saved-only-error'])])])
        nbformat.write(original, notebook)
        disk = notebook.read_bytes()
        manifest, init = work / 'rplugin.vim', work / 'init.lua'
        init.write_text('\n'.join([
            "vim.g.mapleader=' ';vim.o.hidden=true",
            "_G.kernel_test_notifications={};vim.notify=function(msg) kernel_test_notifications[#kernel_test_notifications+1]=msg end",
            'vim.opt.rtp:prepend(' + json.dumps(str(Path(os.environ.get('GLOW_TEST_CONFIG', root / 'portable/payload/nvim')))) + ')',
            *['vim.opt.rtp:append(' + json.dumps(str(data / 'lazy' / plugin)) + ')'
              for plugin in ['molten-nvim', 'nvim-treesitter', 'jupytext.nvim']],
            "require('config.media.runtime').configure_molten()",
            "require('config.media.runtime').configure_jupytext()",
            "require('config.media.notebook_edit').setup()",
        ]))
        env = dict(os.environ, NVIM_RPLUGIN_MANIFEST=str(manifest))
        subprocess.run(['nvim', '--headless', '-i', 'NONE', '-n', '-u', str(init), '+UpdateRemotePlugins', '+qa'],
                       env=env, check=True, timeout=20, capture_output=True, text=True)
        previous = os.environ.get('NVIM_RPLUGIN_MANIFEST')
        os.environ['NVIM_RPLUGIN_MANIFEST'] = str(manifest)
        editor = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-i', 'NONE', '-n', '-u', str(init)])
        try:
            editor.ui_attach(100, 30, rgb=True)
            def lua(code, *args):
                return editor.exec_lua(code, *args)

            def wait(predicate, description):
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(.1)
                raise AssertionError(description + ': ' + str(lua('return kernel_test_notifications')) + '\n' + editor.command_output('messages'))

            def status():
                return lua("return require('config.media.notebook_edit').status()")

            def output():
                return str([mark[3].get('virt_lines', []) for mark in editor.api.buf_get_extmarks(buf, -1, 0, -1, {'details': True})])

            assert lua("return require('config.media.notebook_edit').open(...)", str(notebook))
            buf = editor.current.buffer.number
            print('kernel preservation: importing saved error', flush=True)
            editor.command('GlowNotebookKernel glow-python')
            wait(lambda: status()['ready'] and 'saved-only-error' in output(), 'saved error imported')
            cells = lua("return require('config.media.notebook_edit').cells(0)")
            editor.current.window.cursor = (cells[0]['first'], 0)
            editor.command('GlowNotebookRun')
            wait(lambda: '42' in output() and 'Done' in output(), 'fresh arithmetic result')
            old = status()['kernel']
            print('kernel preservation: switching with fresh result + saved error', flush=True)
            source, changedtick = editor.current.buffer[:], editor.api.buf_get_changedtick(buf)
            editor.command('GlowNotebookKernel python3')
            wait(lambda: status()['ready'] and status()['kernel'] != old, 'switch accepts imported error output')
            wait(lambda: '42' in output() and 'saved-only-error' in output(), 'restored old error and new result')
            assert old not in editor.funcs.MoltenRunningKernels()
            assert editor.current.buffer[:] == source and editor.api.buf_get_changedtick(buf) == changedtick
            assert notebook.read_bytes() == disk, 'switch implicitly saved or changed original notebook'
            # A second switch re-exports the imported snapshot, catching the
            # same upstream error again rather than only a one-time workaround.
            second = status()['kernel']
            print('kernel preservation: re-exporting restored error', flush=True)
            editor.command('GlowNotebookKernel glow-python')
            wait(lambda: status()['ready'] and status()['kernel'] != second, 'second switch')
            wait(lambda: '42' in output() and 'saved-only-error' in output(), 'second restoration')
            editor.command('write')
            saved = nbformat.read(notebook, 4)
            assert saved.cells[0].outputs[0].data['text/plain'] == '42'
            assert saved.cells[1].outputs == original.cells[1].outputs, 'error type/message/traceback changed'
            assert saved.metadata.preserved == original.metadata.preserved
            editor.command('bwipeout!')
            wait(lambda: editor.funcs.MoltenRunningKernels() == [], 'owned kernels released')
            print(json.dumps({'real_molten_imported_error': 'preserved', 'fresh_result': 42,
                              'switches': 2, 'source_and_disk_unchanged_until_save': True,
                              'saved_error_exact': True, 'kernels_after_close': []}))
        finally:
            faulthandler.cancel_dump_traceback_later()
            try:
                editor.command('qa!')
            except (EOFError, OSError):
                pass
            if previous is None:
                os.environ.pop('NVIM_RPLUGIN_MANIFEST', None)
            else:
                os.environ['NVIM_RPLUGIN_MANIFEST'] = previous


if __name__ == '__main__':
    main()
