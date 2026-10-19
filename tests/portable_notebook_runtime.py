#!/usr/bin/env python3
"""Notebook installer lifecycle checks; temporary files/fake commands, no downloads."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('glow_installer', ROOT / 'portable/scripts/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class NotebookRuntime(unittest.TestCase):
    def instance(self, directory):
        instance = installer.Installer.__new__(installer.Installer)
        instance.root = directory / 'stack'
        instance.meta = instance.root / '.installer'
        instance.profile_data = instance.root / 'data/nvim'
        instance.payload = ROOT / 'portable/payload'
        instance.bundle = ROOT / 'portable'
        instance.manifest = {'runtimes': {'mason_python': '3.12.2'}}
        instance.plugins = installer.read_json(instance.payload / 'plugins.json')['plugins']
        instance.target = 'macos-arm64'
        instance.env = {'UV_PYTHON_DOWNLOADS': 'never', 'XDG_DATA_HOME': str(instance.root / 'data')}
        requirements = instance.root / 'config/nvim/lua/config/media/runtime/requirements.txt'
        requirements.parent.mkdir(parents=True)
        requirements.write_bytes((instance.payload / 'nvim/lua/config/media/runtime/requirements.txt').read_bytes())
        instance.calls = []
        instance.package_result = '[["pynvim", "0.6.0"]]'

        def fake_run(arguments, **kwargs):
            args = [str(item) for item in arguments]
            instance.calls.append((args, kwargs))
            venv = instance.profile_data / 'glow-notebook-venv'
            if args[1:2] == ['venv']:
                (venv / 'bin').mkdir(parents=True)
                (venv / 'bin/python').write_text('fake python')
                (venv / 'pyvenv.cfg').write_text('version = 3.12.2\n')
            elif '-m' in args:
                kernel = instance.notebook_files()[1]
                kernel.parent.mkdir(parents=True)
                kernel.write_text(json.dumps({'argv': [str(venv / 'bin/python')]}))
            elif '--headless' in args:
                instance.notebook_files()[-1].write_text('MoltenInit remote manifest')
            elif '-c' in args:
                return instance.package_result
            return ''

        instance.run = fake_run
        return instance

    def test_new_install_and_repeat_without_package_mutation(self):
        with tempfile.TemporaryDirectory() as work:
            instance = self.instance(Path(work))
            instance.install_notebook_runtime()
            calls = instance.calls
            self.assertEqual(calls[0][0][1:4], ['venv', '--python', str(instance.root / 'runtime/bin/python3')])
            self.assertEqual(calls[1][0][1:3], ['pip', 'sync'])
            self.assertIn('--prefix', calls[2][0])
            self.assertEqual(calls[3][1]['env']['NVIM_BUNDLE_PHASE'], 'notebook')
            self.assertEqual(calls[3][1]['env']['UV_PYTHON_DOWNLOADS'], 'never')
            self.assertEqual(installer.read_json(instance.meta / 'notebook-runtime.json')['status'], 'ready')
            instance.calls.clear()
            instance.install_notebook_runtime()
            self.assertEqual(len(instance.calls), 1)
            self.assertIn('-c', instance.calls[0][0])

    def test_user_environment_and_generated_file_edits_are_preserved(self):
        for change in ('packages', 'kernel', 'manifest', 'pyvenv'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as work:
                instance = self.instance(Path(work))
                instance.install_notebook_runtime()
                if change == 'packages':
                    instance.package_result = '[["pynvim", "99.0"]]'
                else:
                    path = instance.notebook_files()[{'pyvenv': 0, 'kernel': 1, 'manifest': 2}[change]]
                    path.write_text('user edit')
                instance.calls.clear()
                with self.assertRaises(installer.InstallError):
                    instance.install_notebook_runtime()
                self.assertFalse(any('sync' in call[0] or '--prefix' in call[0] for call in instance.calls))
                if change != 'packages':
                    self.assertEqual(path.read_text(), 'user edit')

    def test_unmanaged_environment_and_edited_config_are_preserved(self):
        for change in ('venv', 'requirements'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as work:
                instance = self.instance(Path(work))
                if change == 'venv':
                    (instance.profile_data / 'glow-notebook-venv').mkdir(parents=True)
                else:
                    path = instance.root / 'config/nvim/lua/config/media/runtime/requirements.txt'
                    path.write_text('user requirements')
                with self.assertRaises(installer.InstallError):
                    instance.install_notebook_runtime()
                self.assertEqual(instance.calls, [])
                self.assertFalse((instance.meta / 'notebook-runtime.json').exists())

    def test_owned_interrupted_install_can_resume(self):
        with tempfile.TemporaryDirectory() as work:
            instance = self.instance(Path(work))
            installer.write_json(instance.meta / 'notebook-runtime.json', {
                'inputs': instance.notebook_inputs(), 'status': 'preparing'})
            instance.install_notebook_runtime()
            instance.check_notebook_runtime()

    def test_new_plugin_checkouts_match_existing_config_lock(self):
        payload = ROOT / 'portable/payload'
        lock = installer.read_json(payload / 'nvim/lazy-lock.json')
        plugins = {item['name']: item for item in installer.read_json(payload / 'plugins.json')['plugins']}
        for name in ('molten-nvim', 'jupytext.nvim'):
            self.assertEqual(plugins[name]['commit'], lock[name]['commit'])
            self.assertEqual(plugins[name]['build_action'], 'none')


if __name__ == '__main__':
    unittest.main()
