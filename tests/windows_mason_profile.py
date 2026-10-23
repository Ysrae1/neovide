#!/usr/bin/env python3
"""Windows acceptance: frozen Mason CLIs and stdio LSPs in a private profile.

Run with a Python containing psutil. Only test-owned process trees are ended;
no user editor or global environment is changed. Pass --mason and --output.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time

import psutil


def launch(command, arguments):
    cmd = subprocess.list2cmdline([str(command), *arguments])
    return subprocess.Popen('"' + os.environ['COMSPEC'] + '" /d /s /c "' + cmd + '"',
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            creationflags=subprocess.CREATE_NO_WINDOW)


def stop(process):
    if process.poll() is None:
        try:
            owner = psutil.Process(process.pid)
            for child in reversed(owner.children(recursive=True)):
                try:
                    child.terminate()
                except psutil.NoSuchProcess:
                    pass
            process.kill()
        except psutil.NoSuchProcess:
            pass
        process.wait(timeout=10)


def cli(mason, name, args):
    process = launch(mason / 'bin' / (name + '.cmd'), args)
    try:
        out, err = process.communicate(timeout=30)
        return {'command': name, 'arguments': args, 'exit': process.returncode,
                'stdout': out.decode('utf-8', errors='replace')[:3500],
                'stderr': err.decode('utf-8', errors='replace')[:3500],
                'passed': process.returncode == 0}
    except subprocess.TimeoutExpired as error:
        return {'command': name, 'arguments': args, 'passed': False, 'error': 'timeout',
                'stdout': (error.output or b'').decode('utf-8', errors='replace')[:3500],
                'stderr': (error.stderr or b'').decode('utf-8', errors='replace')[:3500]}
    finally:
        stop(process)


def send(process, message):
    body = json.dumps(message).encode('utf-8')
    process.stdin.write(b'Content-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)
    process.stdin.flush()


def lsp(mason, name, args):
    process = launch(mason / 'bin' / (name + '.cmd'), args)
    messages, errors = queue.Queue(), []

    def read():
        try:
            while True:
                headers = {}
                while True:
                    line = process.stdout.readline()
                    if not line:
                        return
                    if line in (b'\r\n', b'\n'):
                        break
                    key, value = line.decode().split(':', 1)
                    headers[key.lower()] = value.strip()
                body = process.stdout.read(int(headers['content-length']))
                messages.put(json.loads(body))
        except Exception as error:
            errors.append(str(error))

    threading.Thread(target=read, daemon=True).start()
    stderr = []
    threading.Thread(target=lambda: stderr.append(process.stderr.read().decode('utf-8', errors='replace')), daemon=True).start()
    result = {'command': name, 'arguments': args, 'passed': False}
    try:
        send(process, {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
                       'params': {'processId': os.getpid(), 'rootUri': None, 'capabilities': {}}})
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            message = messages.get(timeout=max(0.1, deadline - time.monotonic()))
            if message.get('id') == 1:
                result['initialize'] = message
                result['passed'] = 'capabilities' in message.get('result', {})
                break
        if result['passed']:
            send(process, {'jsonrpc': '2.0', 'method': 'initialized', 'params': {}})
            send(process, {'jsonrpc': '2.0', 'id': 2, 'method': 'shutdown'})
            shutdown = time.monotonic() + 5
            while time.monotonic() < shutdown:
                message = messages.get(timeout=max(0.1, shutdown - time.monotonic()))
                if message.get('id') == 2:
                    send(process, {'jsonrpc': '2.0', 'method': 'exit'})
                    process.wait(timeout=10)
                    result['shutdown_exit'] = process.returncode
                    break
    except (queue.Empty, OSError, subprocess.TimeoutExpired) as error:
        result['error'] = type(error).__name__ + ': ' + str(error)
    finally:
        stop(process)
    result['reader_errors'] = errors
    result['stderr'] = ''.join(stderr)[:3500]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mason', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--commands', nargs='*')
    parser.add_argument('--servers', nargs='*')
    args = parser.parse_args()
    commands = {name: ['--version'] for name in ('black', 'clang-format', 'clangd', 'debugpy', 'gofumpt',
                'hadolint', 'jq', 'lua-language-server', 'markdown-toc', 'markdownlint-cli2',
                'marksman', 'mypy', 'neocmakelsp', 'prettierd', 'pyright', 'ruff', 'shfmt', 'stylua', 'texlab', 'yamllint')}
    fixture = args.output.parent / 'mason-fixture.md'
    fixture.write_text('# Mason fixture\n\n## ARM64 tools\n', encoding='utf-8')
    commands.update({'gopls': ['version'], 'isort': ['--version-number'], 'markdown-toc': [str(fixture), '--json']})
    servers = {'pyright-langserver': ['--stdio'], 'clangd': [], 'texlab': [], 'lua-language-server': [],
               'vscode-json-language-server': ['--stdio'], 'marksman': ['server'], 'gopls': [],
               'neocmakelsp': ['stdio'], 'ltex-ls': []}
    if args.commands is not None:
        commands = {name: commands[name] for name in args.commands}
    if args.servers is not None:
        servers = {name: servers[name] for name in args.servers}
    # Limit concurrency so this check does not compete with native plugin builds.
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        cli_results = list(pool.map(lambda item: cli(args.mason, *item), commands.items()))
        lsp_results = list(pool.map(lambda item: lsp(args.mason, *item), servers.items()))
    result = {'cli': cli_results, 'lsp': lsp_results,
              'passed': all(item['passed'] for item in cli_results + lsp_results)}
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'passed': result['passed'], 'cli_count': len(cli_results), 'lsp_count': len(lsp_results),
                     'failures': [item for item in cli_results + lsp_results if not item['passed']]}, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
