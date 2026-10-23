#!/usr/bin/env python3
"""Prepare a private native Notebook provider; never modify the source Python."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-root', type=Path, required=True)
    parser.add_argument('--config-root', type=Path, required=True)
    parser.add_argument('--nvim', type=Path, required=True)
    parser.add_argument('--requirements', type=Path, required=True)
    parser.add_argument('--latex-requirements', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--install', action='store_true')
    args = parser.parse_args()
    report = args.report.resolve()
    report.parent.mkdir(parents=True, exist_ok=True)
    record = {'schema_version': 1, 'status': 'failed', 'source_python': sys.executable,
              'source_python_sha256': sha(sys.executable)}
    env = dict(os.environ, PYTHONNOUSERSITE='1', PYTHONUTF8='1', PIP_DISABLE_PIP_VERSION_CHECK='1')
    for name in ('PYTHONHOME', 'PYTHONPATH', 'PYTHONSTARTUP', 'VIRTUAL_ENV'):
        env.pop(name, None)

    def run(label, command, timeout=120, environment=None):
        with (report.parent / (label + '.log')).open('wb') as output:
            process = subprocess.Popen([str(item) for item in command], stdout=output, stderr=subprocess.STDOUT,
                                       env=environment or env, creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                result = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                # Stop only this invocation's process tree, including a provider
                # started by the isolated Neovim registration process.
                subprocess.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'],
                               stdout=output, stderr=subprocess.STDOUT, timeout=15)
                process.wait(timeout=10)
                raise RuntimeError(f'{label} exceeded {timeout} seconds; see {label}.log')
        if result:
            raise RuntimeError(f'{label} exited {result}; see {label}.log')

    try:
        import platform
        import struct
        import sysconfig
        machine = sysconfig.get_platform().lower()
        if platform.python_implementation() != 'CPython' or sys.version_info[:2] < (3, 12) or struct.calcsize('P') != 8:
            raise RuntimeError('A compatible 64-bit CPython 3.12 or newer is required')
        if machine not in ('win-arm64', 'win-amd64'):
            raise RuntimeError('A native Windows ARM64 or x64 Python is required')
        record.update(platform=machine, version=list(sys.version_info[:3]), bits=64)
        venv = args.data_root.resolve() / 'glow-notebook-venv'
        python = venv / 'Scripts/python.exe'
        marker = venv / '.glow-notebook-runtime.json'
        desired = {'schema_version': 1, 'source_python_sha256': sha(sys.executable),
                   'requirements_sha256': sha(args.requirements), 'latex_requirements_sha256': sha(args.latex_requirements),
                   'platform': machine, 'version': list(sys.version_info[:3])}
        if venv.exists():
            if not marker.is_file() or json.loads(marker.read_text()) != desired:
                raise RuntimeError('Preserving an existing unmanaged or differently configured Notebook environment')
        elif args.install:
            run('create-venv', [sys.executable, '-m', 'venv', venv])
            marker.write_text(json.dumps(desired, indent=2), encoding='utf-8')
        else:
            raise RuntimeError('Notebook environment is missing; use -Install to prepare it')
        if args.install:
            run('install-notebook', [python, '-m', 'pip', 'install', '--only-binary=:all:', '-r', args.requirements], 300)
            run('install-latex', [python, '-m', 'pip', 'install', '--require-hashes', '-r', args.latex_requirements], 120)
        run('check-imports', [python, '-c', 'import pynvim,jupyter_client,ipykernel,jupytext,nbformat,PIL,matplotlib,pylatexenc,zmq;print("imports passed")'])
        run('check-packages', [python, '-m', 'pip', 'check'])
        kernel = venv / 'share/jupyter/kernels/glow-python/kernel.json'
        if not kernel.is_file():
            if not args.install:
                raise RuntimeError('The private glow-python kernelspec is missing')
            run('register-kernel', [python, '-m', 'ipykernel', 'install', '--prefix', venv, '--name', 'glow-python', '--display-name', 'Neovide Glow Python'])
        specification = json.loads(kernel.read_text(encoding='utf-8'))
        if Path(specification['argv'][0]).resolve() != python.resolve():
            raise RuntimeError('Preserving a kernelspec belonging to another interpreter')
        manifest = args.data_root.resolve() / 'rplugin.vim'
        if not manifest.is_file():
            if not args.install:
                raise RuntimeError('The remote-plugin manifest is missing')
            init = report.parent / 'register-notebook.lua'
            molten = args.data_root.resolve() / 'lazy/molten-nvim'
            if not (molten / 'rplugin/python3/molten/__init__.py').is_file():
                raise RuntimeError('The pinned Molten plugin is missing')
            init.write_text('\n'.join([
                'vim.opt.rtp:prepend(' + json.dumps(args.config_root.resolve().as_posix()) + ')',
                'vim.opt.rtp:append(' + json.dumps(molten.as_posix()) + ')',
                'vim.g.python3_host_prog = ' + json.dumps(python.as_posix()),
                'require("config.media.runtime").prepare_host()',
            ]), encoding='utf-8')
            register_env = dict(env, NVIM_RPLUGIN_MANIFEST=str(manifest))
            run('register-rplugin', [args.nvim, '--headless', '-i', 'NONE', '-n', '-u', init, '+UpdateRemotePlugins', '+qa'], 60, register_env)
        if not manifest.is_file() or 'MoltenInit' not in manifest.read_text(encoding='utf-8'):
            raise RuntimeError('Molten commands are absent from the remote-plugin manifest')
        parser_check = report.parent / 'check-notebook-parser.lua'
        parser_check.write_text('\n'.join([
            'vim.opt.rtp:append(' + json.dumps((args.data_root.resolve() / 'lazy/nvim-treesitter').as_posix()) + ')',
            'vim.opt.rtp:append(' + json.dumps((args.data_root.resolve() / 'site').as_posix()) + ')',
            'local ok, err = pcall(function() vim.treesitter.get_string_parser("answer = 42", "python"):parse() end)',
            'if not ok then io.stderr:write("Notebook output export requires a matching native Python Tree-sitter parser: " .. tostring(err)); vim.cmd("cquit 1") end',
            'vim.cmd("qa!")',
        ]), encoding='utf-8')
        run('check-parser', [args.nvim, '--headless', '-i', 'NONE', '-n', '-u', 'NONE', '-l', parser_check], 30)
        record.update(status='ready', python=str(python), python_parser='passed', jupytext=str(venv / 'Scripts/jupytext.exe'),
                      latex2text=str(venv / 'Scripts/latex2text.exe'), kernelspec=str(kernel),
                      manifest=str(manifest), manifest_sha256=sha(manifest), managed_environment=str(marker))
    except Exception as error:
        record['error'] = str(error)
    report.write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(json.dumps(record))
    return 0 if record['status'] == 'ready' else 1


if __name__ == '__main__':
    raise SystemExit(main())
