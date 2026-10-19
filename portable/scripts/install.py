#!/usr/bin/env python3
"""Install the pinned Neovide Glow profile without touching existing editor data."""
import argparse
import concurrent.futures
import hashlib
import gzip
import json
import os
import platform
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

BUNDLE = Path(__file__).resolve().parents[1]

class InstallError(RuntimeError):
    pass

def say(message):
    print(message, flush=True)

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()

def read_json(path):
    return json.loads(Path(path).read_text())

def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.new')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)

def bundled_font_files(directory, platform_name=None):
    """Validate shipped font inputs before copying anything into a user font directory."""
    directory = Path(directory)
    metadata = read_json(directory / 'fonts.json')
    if metadata.get('schema_version') != 1:
        raise InstallError('Unsupported bundled font manifest.')
    selected = []
    families = set()
    seen = set()
    for item in metadata['fonts'] + metadata['notices']:
        filename = item['filename']
        relative = Path(filename)
        path = directory / relative
        if (relative.is_absolute() or '..' in relative.parts or '\\' in filename
                or filename in seen or not path.resolve().is_relative_to(directory.resolve())
                or path.is_symlink() or not path.is_file()):
            raise InstallError('Invalid/missing bundled font or notice: ' + filename)
        seen.add(filename)
        if sha(path) != item['sha256']:
            raise InstallError('Bundled font/notice checksum mismatch: ' + filename)
        if item in metadata['fonts']:
            if relative.name != filename or relative.suffix not in ('.ttf', '.otf'):
                raise InstallError('Invalid bundled font filename: ' + filename)
            if platform_name is None or platform_name in item['platforms']:
                selected.append(path)
                families.add(item['family'])
    if not selected:
        raise InstallError('No bundled fonts for platform: ' + str(platform_name))
    required = {'FiraCode Nerd Font Mono'}
    if platform_name != 'macos':
        required.add('Noto Sans Mono CJK SC')
    if not required.issubset(families):
        raise InstallError('Bundled default font families missing: ' + ', '.join(sorted(required - families)))
    return selected

class Installer:
    def __init__(self, args):
        self.args = args
        self.manifest_path = Path(args.manifest).expanduser().resolve()
        self.manifest = read_json(self.manifest_path)
        if self.manifest.get('schema_version') != 1:
            raise InstallError('Unsupported manifest schema; expected schema_version 1.')
        self.stack_id = self.manifest['stack_id']
        if not re.fullmatch(r'[A-Za-z0-9_.-]+', self.stack_id):
            raise InstallError('Invalid stack_id.')
        self.payload = self.manifest_path.parent / 'payload'
        self.bundle = self.manifest_path.parent
        self.root = Path(args.root).expanduser().resolve() if args.root else Path.home() / '.local/share/neovide-glow/stacks' / self.stack_id
        self.cache = Path(args.cache_dir).expanduser().resolve() if args.cache_dir else self.root / 'download-cache'
        machine = platform.machine().lower()
        actual = 'macos-arm64' if sys.platform == 'darwin' and machine in ('arm64', 'aarch64') else 'linux-x86_64' if sys.platform.startswith('linux') and machine in ('x86_64', 'amd64') else None
        self.target = 'linux-x86_64' if args.target == 'wsl' else actual
        if self.target is None:
            raise InstallError('Supported targets: native Apple Silicon macOS, or Ubuntu 24.04 x86_64 in WSL2.')
        if not (args.plan or args.doctor) and actual != self.target:
            raise InstallError('Run --target wsl inside the target WSL2 Ubuntu distro, not on macOS/Windows Python.')
        self.is_mac = self.target == 'macos-arm64'
        self.meta = self.root / '.installer'
        self.env = dict(os.environ)
        self.env.update({
            'XDG_CONFIG_HOME': str(self.root / 'config'),
            'XDG_DATA_HOME': str(self.root / 'data'),
            'XDG_STATE_HOME': str(self.root / 'state'),
            'XDG_CACHE_HOME': str(self.root / 'cache'),
            'NVIM_APPNAME': 'nvim',
            'PATH': os.pathsep.join([str(self.root / 'bin'), str(self.root / 'data/nvim/mason/bin'), str(self.root / 'runtime/bin'), os.environ.get('PATH', '')]),
            'UV_PYTHON_DOWNLOADS': 'never',
            'UV_CACHE_DIR': str(self.root / 'cache/uv'),
            'npm_config_cache': str(self.root / 'cache/npm'),
        })
        self.plugins_manifest = self.payload / 'plugins.json'
        self.plugins = read_json(self.plugins_manifest)['plugins']
        self.profile_data = self.root / 'data/nvim'
        self.native_ext = 'dylib' if self.is_mac else 'so'

    def run(self, args, cwd=None, capture=False, env=None):
        say('=> ' + shlex.join([str(a) for a in args]))
        result = subprocess.run([str(a) for a in args], cwd=cwd, env=env or self.env,
                                text=True, stdout=subprocess.PIPE if capture else None,
                                stderr=subprocess.PIPE if capture else None)
        if result.returncode:
            detail = '\n' + (result.stderr or result.stdout or '')[-4000:] if capture else ''
            raise InstallError(f'Command failed ({result.returncode}): {shlex.join([str(a) for a in args])}{detail}')
        return result.stdout.strip() if capture else ''

    def prereqs(self, stage):
        required = ['git', 'curl', 'make', 'cc', 'pkg-config']
        if stage in ('all', 'plugins'):
            required += ['rustup', 'cargo']
        if stage in ('all', 'languages'):
            required += ['go', 'java']
        missing = [name for name in required if not shutil.which(name)]
        if self.is_mac and stage in ('all', 'tools'):
            prefix = Path(os.environ.get('NEOVIDE_NCURSES_PREFIX', '/opt/homebrew/opt/ncurses'))
            if not (prefix / 'lib/pkgconfig/ncursesw.pc').is_file():
                missing.append('native ARM ncursesw (Homebrew ncurses)')
        if not self.is_mac and stage in ('all', 'tools') and not Path('/usr/include/ncurses.h').exists() and not Path('/usr/include/ncursesw/ncurses.h').exists():
            missing.append('libncurses-dev (headers)')
        if not self.is_mac and stage in ('all', 'plugins'):
            if not Path('/usr/include/openssl/ssl.h').exists():
                missing.append('libssl-dev (headers)')
            if not list(Path('/usr/lib').glob('llvm*/lib/libclang.so*')) and not list(Path('/usr/lib/x86_64-linux-gnu').glob('libclang*.so*')):
                missing.append('libclang-dev (shared library)')
        return missing

    def instructions(self):
        if self.is_mac:
            return 'Install missing prerequisites explicitly: complete xcode-select --install; install native ARM Homebrew from https://brew.sh if missing; brew install python git pkgconf ncurses rustup go openjdk@21. Follow Homebrew Python, Java and rustup PATH setup in DEPLOY.md; this installer never changes your default Rust toolchain. No preinstalled Neovim is needed.'
        return 'Ubuntu 24.04 prerequisites (run yourself): sudo apt update && sudo apt install -y python3 python3-venv git curl build-essential pkg-config libncurses-dev libssl-dev libclang-dev golang-go openjdk-21-jre-headless unzip xz-utils. Install rustup from https://rustup.rs separately, then reopen the shell. No apt package is installed automatically. No preinstalled Neovim is needed.'

    def plan(self):
        say(f'Stack: {self.stack_id}\nTarget: {self.target}\nIsolated root: {self.root}\nStage: {self.args.stage}')
        for key, tool in self.manifest['assets'].items():
            if key == 'font':
                continue  # Fonts are shipped in payload, not fetched at installation time.
            entry = tool['platforms'].get(self.target) or tool['platforms'].get('any')
            if entry:
                say(f'  {key} {tool["version"]}: {entry["filename"]} / SHA256 {entry["sha256"]}')
        say(f'{len(self.plugins)} plugin checkouts are pinned. Config, data, state and cache stay inside the isolated root.')
        say('No preinstalled Neovim is needed: tools downloads and verifies the locked Neovim first; later stages use only the isolated launcher.')
        fonts = bundled_font_files(self.payload / 'fonts', 'macos' if self.is_mac else 'linux')
        say(f'{len(fonts)} default font files are bundled and checksum-verified; macOS uses system PingFang SC, Windows/WSL use bundled Noto Sans Mono CJK SC.')
        say('Stages: tools (runtimes/config/fonts), plugins (exact sources/native builds/ACP/formula converter), languages (frozen parsers/Mason/health).')
        say('macOS keeps DMG drag installation. Windows uses install.ps1 for its native GUI; this script manages the WSL profile.')
        say('Optional features not installed: MarkdownPreview, Peek, full TeX/PDF toolchain, rich video/PDF/image previews. Codex login remains local and is never copied.')
        missing = self.prereqs(self.args.stage)
        say('Missing host prerequisites: ' + (', '.join(missing) or 'none detected'))
        if missing:
            say(self.instructions())
        say('Plan only: no directory, download, installation, shell or application change was made.')

    def doctor(self):
        say(f'Read-only doctor: {self.target}\nIsolated root: {self.root}')
        missing = self.prereqs(self.args.stage)
        failures = ['host prerequisite: ' + name for name in missing]
        try:
            fonts = bundled_font_files(self.payload / 'fonts', 'macos' if self.is_mac else 'linux')
            font_directory = self.user_font_directory()
            for font in fonts:
                installed = font_directory / font.name
                if not installed.is_file() or sha(installed) != sha(font):
                    failures.append('font missing/different: ' + str(installed))
        except (InstallError, OSError, ValueError, KeyError) as error:
            failures.append(str(error))
        required_stages = ['tools']
        if self.args.stage in ('plugins', 'languages', 'all'):
            required_stages.append('plugins')
        if self.args.stage in ('languages', 'all'):
            required_stages.append('languages')
        manifest_sha = sha(self.manifest_path)
        for stage in required_stages:
            marker = self.meta / 'stages' / (stage + '.json')
            if not marker.is_file():
                failures.append('stage not completed: ' + stage)
            elif read_json(marker).get('manifest_sha256') != manifest_sha:
                failures.append('stage marker has a different manifest: ' + stage)
            else:
                say(stage + ': completed for this manifest')
        for relative in ('bin/nvim', 'bin/yazi', 'bin/tree-sitter', 'bin/cmatrix', 'bin/cmatrix-gm', 'bin/cmatrix-uni', 'bin/unimatrix', 'runtime/bin/node', 'runtime/bin/python-app', 'runtime/bin/python3'):
            path = self.root / relative
            if not path.is_file() or not os.access(path, os.X_OK):
                failures.append(f'not installed/executable: {path}')
        if 'plugins' in required_stages:
            for plugin in self.plugins:
                path = self.profile_data / 'lazy' / plugin['name']
                if not path.is_dir():
                    failures.append('plugin not installed: ' + plugin['name'])
                    continue
                try:
                    self.verify_source(plugin, path)
                except InstallError as error:
                    failures.append(str(error))
                for output in self.plugin_outputs(plugin):
                    if not output.is_file():
                        failures.append('native plugin output missing: ' + str(output))
            converter = self.profile_data / 'latex2text-venv/bin/latex2text'
            if not converter.is_file() or not os.access(converter, os.X_OK):
                failures.append('formula converter not installed: ' + str(converter))
            acp = self.profile_data / 'codex-acp'
            if not (acp / 'node_modules/@agentclientprotocol/codex-acp/dist/index.js').is_file():
                failures.append('Codex ACP adapter not installed')
            if not (acp / 'package-lock.json').is_file() or sha(acp / 'package-lock.json') != sha(self.payload / 'codex-acp/package-lock.json'):
                failures.append('Codex ACP lock missing/different')
            try:
                self.check_notebook_runtime()
            except (InstallError, OSError, ValueError, KeyError) as error:
                failures.append(str(error))
        if 'languages' in required_stages:
            for name in read_json(self.payload / 'treesitter.json')['parsers']:
                if not (self.profile_data / 'lazy/nvim-treesitter/parser' / (name + '.so')).is_file():
                    failures.append('parser missing: ' + name)
            for item in read_json(self.payload / 'mason.json')['packages']:
                if item.get('platforms') and self.target not in item['platforms']:
                    say('Optional Mason tool omitted on ' + self.target + ': ' + item['name'] + ' (' + item.get('reason', 'not selected for platform') + ')')
                    continue
                receipt = self.profile_data / 'mason/packages' / item['name'] / 'mason-receipt.json'
                source = read_json(receipt).get('primary_source', {}).get('id', '') if receipt.is_file() else ''
                if source.rsplit('@', 1)[-1] != item['version']:
                    failures.append('Mason package missing/different: ' + item['name'] + '@' + item['version'])
        if failures:
            for item in failures:
                say('MISSING/CHANGED: ' + item)
            if missing:
                say(self.instructions())
            return 1
        say('Requested stages, required artifacts and source records are consistent. No download or application startup was performed.')
        return 0

    def entry(self, key):
        tool = self.manifest['assets'][key]
        entry = tool['platforms'].get(self.target) or tool['platforms'].get('any')
        if not entry:
            raise InstallError(f'No locked {key} artifact for {self.target}.')
        return tool, entry

    def download(self, entry):
        self.cache.mkdir(parents=True, exist_ok=True)
        path = self.cache / entry['filename']
        if not path.exists():
            partial = path.with_name(path.name + '.partial')
            say('Downloading ' + entry['url'])
            try:
                req = urllib.request.Request(entry['url'], headers={'User-Agent': 'neovide-glow-installer/1'})
                with urllib.request.urlopen(req, timeout=120) as response, partial.open('wb') as output:
                    shutil.copyfileobj(response, output)
                partial.replace(path)
            finally:
                partial.unlink(missing_ok=True)
        if sha(path) != entry['sha256']:
            raise InstallError(f'Checksum mismatch: {path}. File preserved; remove this bad cached file explicitly and rerun.')
        return path

    def unpack(self, key):
        tool, entry = self.entry(key)
        destination = self.root / 'vendor' / key / (tool['version'] + '-' + self.target)
        marker = destination / '.artifact.json'
        if marker.exists():
            if read_json(marker).get('sha256') != entry['sha256']:
                raise InstallError(f'Existing managed vendor source has a different lock: {destination}; preserved.')
            return destination
        if destination.exists():
            raise InstallError(f'Incomplete/unmanaged extraction exists: {destination}; preserve or remove it before rerunning.')
        archive = self.download(entry)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temp = Path(tempfile.mkdtemp(prefix='.' + key + '-', dir=destination.parent))
        try:
            if entry['format'] in ('tar', 'tar.gz', 'tar.xz'):
                with tarfile.open(archive) as stream:
                    stream.extractall(temp, filter='data')
            elif entry['format'] == 'zip':
                with zipfile.ZipFile(archive) as stream:
                    for info in stream.infolist():
                        candidate = temp / info.filename
                        if not candidate.resolve().is_relative_to(temp.resolve()):
                            raise InstallError('Unsafe zip member: ' + info.filename)
                        mode = info.external_attr >> 16
                        if stat.S_ISLNK(mode):
                            raise InstallError('Unexpected symlink in zip: ' + info.filename)
                        stream.extract(info, temp)
                        if mode & 0o777 and candidate.is_file():
                            candidate.chmod(mode & 0o777)
            elif entry['format'] == 'gzip':
                with gzip.open(archive, 'rb') as stream, (temp / entry['binary']).open('wb') as output:
                    shutil.copyfileobj(stream, output)
            elif entry['format'] == 'raw':
                shutil.copy2(archive, temp / entry['filename'])
            else:
                raise InstallError('Unsupported locked archive format: ' + entry['format'])
            write_json(temp / '.artifact.json', {'sha256': entry['sha256'], 'url': entry['url']})
            temp.rename(destination)
        finally:
            if temp.exists():
                shutil.rmtree(temp)
        return destination

    def locate(self, directory, name):
        candidates = [path for path in directory.rglob(name) if path.is_file() and path.name == name]
        if not candidates:
            raise InstallError(f'{name} missing in locked extraction: {directory}')
        candidates.sort(key=lambda p: (len(p.parts), str(p)))
        return candidates[0]

    def link(self, name, target, runtime=False):
        path = self.root / ('runtime/bin' if runtime else 'bin') / name
        path.parent.mkdir(parents=True, exist_ok=True)
        target = Path(target).resolve()
        if path.is_symlink() and path.resolve() == target:
            return
        if path.exists() or path.is_symlink():
            raise InstallError(f'Existing different launcher preserved: {path}')
        path.symlink_to(target)

    def managed_bytes(self, target, content, executable=False):
        target = Path(target)
        # Record the first shipped content. Subsequent runs never overwrite a
        # different file, even if a later payload changes its defaults.
        records_path = self.meta / 'managed-files.json'
        records = read_json(records_path) if records_path.exists() else {}
        key = str(target)
        incoming = hashlib.sha256(content).hexdigest()
        if target.exists():
            current = sha(target)
            if current != incoming:
                reason = 'user edits' if key in records and current != records[key] else 'different existing content'
                say(f'Preserved {reason}: {target}')
                return
            if key not in records:
                records[key] = incoming
                write_json(records_path, records)
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        if executable:
            target.chmod(0o755)
        records[key] = incoming
        write_json(records_path, records)

    def copy_tree(self, source, destination):
        for path in sorted(source.rglob('*')):
            if path.is_symlink():
                raise InstallError('Unexpected symlink in shipped payload: ' + str(path))
            if path.is_file():
                self.managed_bytes(destination / path.relative_to(source), path.read_bytes(), bool(path.stat().st_mode & 0o111))

    def wrapper(self, name, executable, extra='', arguments='"$@"', runtime=False):
        body = f'''#!/bin/sh
STACK={shlex.quote(str(self.root))}
export XDG_CONFIG_HOME="$STACK/config" XDG_DATA_HOME="$STACK/data"
export XDG_STATE_HOME="$STACK/state" XDG_CACHE_HOME="$STACK/cache" NVIM_APPNAME=nvim
export YAZI_CONFIG_HOME="$STACK/config/yazi"
export PATH="$STACK/bin:$STACK/data/nvim/mason/bin:$STACK/runtime/bin:$PATH"
{extra}
exec {shlex.quote(str(executable))} {arguments}
'''
        self.managed_bytes(self.root / ('runtime/bin' if runtime else 'bin') / name, body.encode(), True)

    def python_wrapper(self, name, executable):
        # CPython's venv uses sys.executable's parent for pyvenv.cfg home.
        # A symlink under runtime/bin can point home there and lose stdlib.
        # Exec the fully resolved interpreter so its real vendor path survives.
        executable = Path(executable).resolve()
        launcher = self.root / 'runtime/bin' / name
        if launcher.is_symlink() and launcher.resolve() == executable:
            launcher.unlink()  # Only migrate this exact old managed symlink.
        self.wrapper(name, executable, runtime=True)

    def check_python_venv(self):
        with tempfile.TemporaryDirectory(prefix='python-venv-check-', dir=self.root / 'cache') as directory:
            venv = Path(directory) / 'venv'
            self.run([self.root / 'runtime/bin/python3', '-m', 'venv', venv])
            # venv invokes ensurepip with bundled wheels; no network pip action.
            self.run([venv / 'bin/python', '-m', 'ensurepip', '--version'])
            config = dict(line.split(' = ', 1) for line in (venv / 'pyvenv.cfg').read_text().splitlines() if ' = ' in line)
            tool, entry = self.entry('python_mason')
            directory = self.root / 'vendor/python_mason' / (tool['version'] + '-' + self.target)
            real_python = self.locate(directory, entry['binary']).resolve()
            if Path(config.get('home', '')).resolve() != real_python.parent:
                raise InstallError('Python venv home does not match the real standalone interpreter; pyvenv.cfg was not accepted.')
        say('Mason Python temporary venv and bundled ensurepip startup passed; temporary environment removed.')

    def install_profile(self):
        self.copy_tree(self.payload / 'nvim', self.root / 'config/nvim')
        self.copy_tree(self.payload / 'yazi', self.root / 'config/yazi')
        config = (self.payload / 'neovide/config.toml').read_text()
        literal = json.dumps(str(self.root / 'bin/nvim'))
        config = re.sub(r'^neovim-bin\s*=.*$', 'neovim-bin = ' + literal, config, flags=re.M)
        if not self.is_mac:
            config = config.replace('"PingFang SC"', '"Noto Sans Mono CJK SC"')
        self.managed_bytes(self.root / 'config/neovide/config.toml', config.encode())

    def user_font_directory(self):
        if self.is_mac:
            return Path.home() / 'Library/Fonts'
        return Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'fonts/neovide-glow'

    def install_fonts(self):
        source = self.payload / 'fonts'
        fonts = bundled_font_files(source, 'macos' if self.is_mac else 'linux')
        directory = self.user_font_directory()
        # Preflight all destinations: a later duplicate must not leave a half-installed family.
        for font in fonts:
            target = directory / font.name
            if target.is_symlink() or (target.exists() and (not target.is_file() or sha(target) != sha(font))):
                raise InstallError(f'A different font already exists and was preserved: {target}. Resolve this duplicate font explicitly, then rerun.')
        for path in source.rglob('*'):
            if path.is_file():
                staged = self.root / 'payload/fonts' / path.relative_to(source)
                if staged.is_symlink() or (staged.exists() and (not staged.is_file() or sha(staged) != sha(path))):
                    raise InstallError('Different staged font payload was preserved: ' + str(staged))
        self.copy_tree(source, self.root / 'payload/fonts')
        for font in fonts:
            self.managed_bytes(directory / font.name, font.read_bytes())
        if not self.is_mac and shutil.which('fc-cache'):
            self.run(['fc-cache', '-f', directory])
        say(f'Installed/verified {len(fonts)} bundled font files for this user; no font download was needed.')

    def tools(self):
        bundled_font_files(self.payload / 'fonts', 'macos' if self.is_mac else 'linux')
        for name in ('bin', 'runtime/bin', 'config', 'data', 'state', 'cache'):
            (self.root / name).mkdir(parents=True, exist_ok=True)
        for key in ('nvim', 'yazi', 'rg', 'fd', 'fzf', 'lazygit', 'uv', 'tree_sitter', 'node', 'python', 'python_mason'):
            tool, entry = self.entry(key)
            directory = self.unpack(key)
            binary = self.locate(directory, entry['binary'])
            binary.chmod(binary.stat().st_mode | 0o111)
            if key == 'nvim':
                self.wrapper('nvim', binary)
            elif key == 'yazi':
                previous = self.root / 'bin/yazi'
                if previous.is_symlink() and previous.resolve() == binary.resolve():
                    previous.unlink()  # Migrate only our exact old managed symlink.
                self.wrapper('yazi', binary)
            elif key == 'python':
                self.link('python-app', binary, True)
            elif key == 'python_mason':
                self.python_wrapper('python3', binary)
                self.python_wrapper('python', binary)
            elif key == 'node':
                self.link('node', binary, True)
                for name in ('npm', 'npx'):
                    self.link(name, binary.parent / name, True)
            else:
                self.link(entry['binary'], binary)
            if key == 'yazi':
                self.link('ya', self.locate(directory, 'ya'))
        source = self.unpack('unimatrix')
        self.wrapper('unimatrix', self.root / 'runtime/bin/python-app', arguments=shlex.quote(str(self.locate(source, self.entry('unimatrix')[1]['filename']))) + ' "$@"')
        self.install_cmatrix()
        self.install_fonts()
        self.install_profile()
        if self.is_mac:
            dmg = self.manifest['neovide'].get('macos_dmg')
            if not dmg:
                raise InstallError('This manifest lacks the pinned macOS DMG.')
            source = self.bundle / dmg['path']
            if not source.is_file() and dmg.get('url'):
                source = self.download({'url': dmg['url'], 'filename': 'Neovide-Glow-macOS-arm64.dmg', 'sha256': dmg['sha256']})
            if not source.is_file() or sha(source) != dmg['sha256']:
                raise InstallError('Neovide DMG is missing or has a different SHA256.')
            self.managed_bytes(self.root / 'installer/Neovide.dmg', source.read_bytes())
            self.wrapper('neovide-glow', '/Applications/Neovide.app/Contents/MacOS/neovide', extra='export NEOVIDE_CONFIG="$STACK/config/neovide/config.toml"')
            self.wrapper('neovide', '/Applications/Neovide.app/Contents/MacOS/neovide', extra='export NEOVIDE_CONFIG="$STACK/config/neovide/config.toml"')
            say(f'DMG ready: {self.root / "installer/Neovide.dmg"}. Open it yourself and drag Neovide.app into Applications. Existing applications were not replaced or opened.')
        self.check_python_venv()
        self.check_cmatrix_terminal()
        self.stage_marker('tools')

    def ncurses_environment(self):
        env = dict(self.env)
        if self.is_mac:
            # System pkg-config on recent Apple SDKs can select its ncurses
            # compatibility ABI. Use one explicit ARM Homebrew prefix for both
            # the wide header and dylib, matching the verified local build.
            prefix = Path(os.environ.get('NEOVIDE_NCURSES_PREFIX', '/opt/homebrew/opt/ncurses'))
            pkgdir = prefix / 'lib/pkgconfig'
            if not (pkgdir / 'ncursesw.pc').is_file():
                raise InstallError('Native wide-character ncurses is required. Run /opt/homebrew/bin/brew install ncurses explicitly, or set NEOVIDE_NCURSES_PREFIX to its ARM prefix. No system library was changed.')
            env['PKG_CONFIG_PATH'] = str(pkgdir) + (os.pathsep + env['PKG_CONFIG_PATH'] if env.get('PKG_CONFIG_PATH') else '')
        flags = shlex.split(self.run(['pkg-config', '--cflags', '--libs', 'ncursesw'], capture=True, env=env))
        return env, flags

    def check_cmatrix_terminal(self):
        # Raw PTY ASCII is insufficient: libvterm renders addch(0) as two
        # visible cells (^@). Validate its actual Neovim terminal buffer.
        executable = str(self.root / 'bin/cmatrix')
        delimiter = '='
        while ']' + delimiter + ']' in executable:
            delimiter += '='
        literal = '[' + delimiter + '[' + executable + ']' + delimiter + ']'
        lua = r'''local executable = EXECUTABLE_LITERAL
local jobs = {}
local function stop_jobs()
  for _, job in ipairs(jobs) do
    pcall(vim.fn.chansend, job, "q")
    local status = vim.fn.jobwait({job}, 700)[1]
    if status == -1 then
      pcall(vim.fn.jobstop, job)
      vim.fn.jobwait({job}, 1500)
    end
  end
end
local ok, err = xpcall(function()
  vim.o.columns = 84
  vim.o.lines = 18
  vim.o.laststatus = 0
  vim.o.showtabline = 0
  for _, height in ipairs({6, 12}) do
    local buffer = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buffer, true, {
      relative = "editor", row = 0, col = 0, width = 80,
      height = height, style = "minimal", focusable = true,
    })
    local job = vim.fn.jobstart({executable, "-a", "-b", "-u", "5", "-o"}, {term = true})
    assert(job > 0, "CMatrix terminal did not start")
    jobs[#jobs + 1] = job
    local seen = false
    for _, delay in ipairs({300, 600, 1000}) do
      vim.wait(delay, function() return false end, 20)
      assert(vim.fn.jobwait({job}, 0)[1] == -1, "CMatrix exited before terminal verification")
      local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
      local start = math.max(1, #lines - height + 1)
      for row = start, #lines do
        local text = lines[row]
        if text:match("[^ ]") then seen = true end
        for byte = 1, #text do
          assert(text:byte(byte) < 128, "CMatrix produced visible non-ASCII glyphs in Neovim terminal")
        end
        -- Legacy rain draws only zero-based even columns. A zero sentinel
        -- rendered as ^@ leaks its second cell into the untouched odd column.
        for column = 2, math.min(80, #text), 2 do
          assert(text:sub(column, column) == " ", "CMatrix leaked glyphs into a blank odd column in Neovim terminal")
        end
      end
    end
    assert(seen, "CMatrix terminal remained empty")
    stop_jobs()
    jobs = {}
    vim.api.nvim_win_close(win, true)
    pcall(vim.api.nvim_buf_delete, buffer, {force = true})
    print("CMatrix Neovim terminal 80x" .. height .. ": visible ASCII, odd separator columns blank")
  end
end, debug.traceback)
stop_jobs()
if not ok then
  vim.api.nvim_err_writeln(err)
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
'''.replace('EXECUTABLE_LITERAL', literal)
        with tempfile.NamedTemporaryFile(mode='w', suffix='.lua', prefix='cmatrix-visible-', dir=self.root / 'cache', delete=False) as stream:
            stream.write(lua)
            script = Path(stream.name)
        try:
            self.run([self.root / 'bin/nvim', '--headless', '-u', 'NONE', '-l', script])
        finally:
            script.unlink(missing_ok=True)

    def install_cmatrix(self):
        archive_root = self.unpack('cmatrix')
        source = self.locate(archive_root, 'cmatrix.c').parent
        tool, entry = self.entry('cmatrix')
        patch = tool.get('source_patch')
        if not patch:
            raise InstallError('The CMatrix native-unimatrix source patch is missing from the manifest lock.')
        patch_path = self.bundle / patch['path']
        if not patch_path.is_file() or sha(patch_path) != patch['sha256']:
            raise InstallError('CMatrix source patch SHA256 mismatch; source was preserved.')
        env, flags = self.ncurses_environment()
        identity = fingerprint({'archive': entry['sha256'], 'patch': patch['sha256'], 'platform': self.target, 'flags': flags})
        build = self.root / 'build/cmatrix' / identity[:16]
        source_record = build / '.source-record.json'
        marker = build / '.build-record.json'
        if not build.exists():
            build.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(source, build)
            self.run(['git', 'apply', '--binary', patch_path], cwd=build)
            names = ['cmatrix.c', 'unimatrix.c', 'unimatrix.h', 'configure', 'configure.ac', 'build-native.sh']
            write_json(source_record, {name: sha(build / name) for name in names})
        if not source_record.is_file():
            raise InstallError('Incomplete CMatrix source preparation was preserved: ' + str(build))
        for name, original in read_json(source_record).items():
            if not (build / name).is_file() or sha(build / name) != original:
                raise InstallError('Edited CMatrix source preserved: ' + str(build / name))
        binary = build / 'cmatrix'
        if not marker.is_file() or read_json(marker).get('identity') != identity or not binary.is_file():
            arch = ['-arch', 'arm64'] if self.is_mac else []
            cflags = ['-O2', '-D_XOPEN_SOURCE_EXTENDED=1', *arch]
            # Generate platform config.h with the same selected headers. Compile
            # directly afterwards, avoiding the old autoheader timestamp rules.
            cppflags = [flag for flag in flags if flag.startswith(('-I', '-D'))]
            ldflags = [flag for flag in flags if flag.startswith(('-L', '-Wl,'))]
            self.run(['sh', './configure', 'CC=cc', 'CFLAGS=' + shlex.join(cflags), 'CPPFLAGS=' + shlex.join(cppflags), 'LDFLAGS=' + shlex.join(arch + ldflags)], cwd=build, env=env)
            self.run(['cc', *cflags, 'cmatrix.c', 'unimatrix.c', '-o', binary, *flags], cwd=build, env=env)
            if self.is_mac and self.run(['lipo', '-archs', binary], capture=True) != 'arm64':
                raise InstallError('CMatrix output is not native arm64.')
            write_json(marker, {'identity': identity, 'compiled': True})
        launcher = self.root / 'bin/cmatrix'
        if launcher.is_symlink() and launcher.resolve() != binary.resolve():
            previous = launcher.resolve()
            if previous.is_relative_to(self.root / 'vendor/cmatrix') or previous.is_relative_to(self.root / 'build/cmatrix'):
                launcher.unlink()  # Only our previous isolated build link.
        self.link('cmatrix', binary)
        self.wrapper('cmatrix-uni', binary, arguments='--unimatrix "$@"')
        self.wrapper('cmatrix-gm', binary, arguments='--unimatrix --gomatrix "$@"')

    def source_input(self, plugin):
        return fingerprint({'commit': plugin['commit'], 'url': plugin['url'], 'patches': [sha(self.payload / p) for p in plugin.get('patches', [])], 'submodules': plugin.get('submodules', [])})

    def git(self, path, *args):
        result = subprocess.run(['git', '-C', str(path), *args], text=True, capture_output=True, env=self.env)
        if result.returncode:
            raise InstallError(f'Could not inspect source {path}: {result.stderr.strip()}')
        return result.stdout.strip()

    def source_diff(self, path):
        return fingerprint(self.git(path, 'diff', '--binary', 'HEAD'))

    def verify_source(self, plugin, path):
        marker = self.meta / 'sources' / (plugin['name'] + '.json')
        if not marker.is_file():
            raise InstallError('Source checkout lacks an installer record and was preserved: ' + str(path))
        record = read_json(marker)
        if record['input'] != self.source_input(plugin) or self.git(path, 'rev-parse', 'HEAD') != plugin['commit'] or self.git(path, 'remote', 'get-url', 'origin') != plugin['url']:
            raise InstallError('Source lock/commit changed; checkout preserved: ' + str(path))
        if self.source_diff(path) != record['diff']:
            raise InstallError('Local source edits detected; checkout preserved: ' + str(path))
        for sub in plugin.get('submodules', []):
            subpath = path / sub['path']
            if self.git(subpath, 'rev-parse', 'HEAD') != sub['commit'] or self.git(subpath, 'diff', '--binary', 'HEAD'):
                raise InstallError('Local submodule edits/commit changed; preserved: ' + str(subpath))

    def checkout(self, plugin):
        path = self.profile_data / 'lazy' / plugin['name']
        marker = self.meta / 'sources' / (plugin['name'] + '.json')
        if marker.exists():
            self.verify_source(plugin, path)
            return path
        if path.exists():
            # An interrupted clone can resume only while its tracked state is
            # clean and its origin/HEAD match. No reset/clean is ever used.
            if self.git(path, 'remote', 'get-url', 'origin') != plugin['url'] or self.git(path, 'rev-parse', 'HEAD') != plugin['commit'] or self.git(path, 'diff', '--binary', 'HEAD'):
                raise InstallError('Unmanaged or edited checkout preserved: ' + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            self.run(['git', 'clone', '--filter=blob:none', '--no-checkout', plugin['url'], path])
            self.run(['git', '-C', path, 'fetch', '--depth', '1', 'origin', plugin['commit']])
            self.run(['git', '-C', path, 'checkout', '--detach', plugin['commit']])
        for patch in plugin.get('patches', []):
            self.run(['git', '-C', path, 'apply', '--binary', self.payload / patch])
        for sub in plugin.get('submodules', []):
            subpath = path / sub['path']
            if not (subpath / '.git').exists():
                # The local source patch changes LuaSnip's gitlink without
                # staging it. Clone the explicitly recorded submodule commit,
                # rather than asking git submodule update for the old index.
                self.run(['git', 'clone', '--filter=blob:none', '--no-checkout', sub['url'], subpath])
                self.run(['git', '-C', subpath, 'fetch', '--depth', '1', 'origin', sub['commit']])
                self.run(['git', '-C', subpath, 'checkout', '--detach', sub['commit']])
            if self.git(subpath, 'rev-parse', 'HEAD') != sub['commit'] or self.git(subpath, 'diff', '--binary', 'HEAD'):
                raise InstallError('Pinned submodule has unexpected commit/edits; preserved: ' + str(subpath))
        write_json(marker, {'input': self.source_input(plugin), 'commit': plugin['commit'], 'diff': self.source_diff(path)})
        say('Pinned source ready: ' + plugin['name'])
        return path

    def ensure_rust(self):
        toolchain = self.manifest['neovide']['rust_toolchain']
        installed = self.run(['rustup', 'toolchain', 'list'], capture=True)
        if not any(line.split()[0].startswith(toolchain + '-') for line in installed.splitlines() if line):
            self.run(['rustup', 'toolchain', 'install', toolchain, '--profile', 'minimal'])
        return toolchain

    def plugin_outputs(self, plugin):
        path = self.profile_data / 'lazy' / plugin['name']
        action = plugin.get('build_action', 'none')
        outputs = []
        if action == 'fff':
            outputs = [path / 'target/release' / self.entry('fff')[1]['install_name']]
        elif action == 'telescope-fzf-native':
            outputs = [path / 'build/libfzf.so']
        elif action == 'luasnip':
            outputs = [path / 'lua/luasnip-jsregexp.lua', path / 'deps/luasnip-jsregexp.so']
        elif action == 'avante':
            outputs = [path / 'build' / (name + '.' + self.native_ext) for name in ('avante_tokenizers', 'avante_templates', 'avante_repo_map', 'avante_html2md')]
        return outputs

    def build_plugin(self, plugin, toolchain):
        path = self.profile_data / 'lazy' / plugin['name']
        self.verify_source(plugin, path)
        action = plugin.get('build_action', 'none')
        marker = self.meta / 'builds' / (plugin['name'] + '.json')
        identity = fingerprint({'input': self.source_input(plugin), 'platform': self.target, 'rust': toolchain, 'action': action})
        outputs = self.plugin_outputs(plugin)
        if marker.exists() and read_json(marker).get('identity') == identity and all(p.is_file() for p in outputs):
            return
        if action == 'fff':
            _, entry = self.entry('fff')
            source = self.download(entry)
            destination = path / 'target/release' / entry['install_name']
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        elif action == 'telescope-fzf-native':
            self.run(['make'], cwd=path)
        elif action == 'luasnip':
            flags = ['make', '-C', 'deps/jsregexp', 'INCLUDE_DIR=-I../lua51_include']
            if self.is_mac:
                flags += ['LDFLAGS=-bundle -undefined dynamic_lookup']
            self.run(flags, cwd=path)
            shutil.copy2(path / 'deps/jsregexp/jsregexp.lua', path / 'lua/luasnip-jsregexp.lua')
            shutil.copy2(path / 'deps/jsregexp/jsregexp.so', path / 'deps/luasnip-jsregexp.so')
        elif action == 'avante':
            (path / 'build').mkdir(exist_ok=True)
            for package in ('tokenizers', 'templates', 'repo-map', 'html2md'):
                self.run(['cargo', '+' + toolchain, 'build', '--release', '--locked', '--features=luajit', '-p', 'avante-' + package], cwd=path)
                basename = 'avante_' + package.replace('-', '_')
                shutil.copy2(path / 'target/release' / ('lib' + basename + '.' + self.native_ext), path / 'build' / (basename + '.' + self.native_ext))
        elif action in ('markdown-preview', 'peek'):
            say('Optional preview build omitted: ' + plugin['name'] + '. See payload/BUILD-NOTES.txt before enabling it.')
        elif action not in ('none', 'treesitter', 'base46'):
            raise InstallError('Unrecognized plugin build action: ' + action)
        write_json(marker, {'identity': identity, 'action': action})

    def require_tools(self):
        for name in ('nvim', 'uv', 'tree-sitter'):
            if not (self.root / 'bin' / name).is_file():
                raise InstallError('Run --stage tools first; missing ' + name)
        for name in ('node', 'python-app', 'python3'):
            if not (self.root / 'runtime/bin' / name).is_file():
                raise InstallError('Run --stage tools first; missing runtime ' + name)

    def plugins_stage(self):
        self.require_tools()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(self.checkout, self.plugins))
        toolchain = self.ensure_rust()
        for plugin in self.plugins:
            self.build_plugin(plugin, toolchain)
        acp = self.profile_data / 'codex-acp'
        self.copy_tree(self.payload / 'codex-acp', acp)
        expected = sha(self.payload / 'codex-acp/package-lock.json')
        if sha(acp / 'package-lock.json') != expected:
            raise InstallError('Locally edited ACP package lock preserved; cannot install a different dependency tree.')
        marker = self.meta / 'acp.json'
        if not marker.exists() or read_json(marker).get('lock') != expected or not (acp / 'node_modules').is_dir():
            self.run([self.root / 'runtime/bin/npm', 'ci', '--no-audit', '--no-fund'], cwd=acp)
            write_json(marker, {'lock': expected})
        for name in ('codex-acp', 'codex'):
            entry = acp / 'node_modules/.bin' / name
            if entry.is_file():
                launcher = self.root / 'bin' / name
                if launcher.is_symlink() and launcher.resolve() == entry.resolve():
                    launcher.unlink()  # Migrate this exact old managed link.
                self.wrapper(name, self.root / 'runtime/bin/node', arguments=shlex.quote(str(entry.resolve())) + ' "$@"')
        venv = self.profile_data / 'latex2text-venv'
        lock = self.payload / 'requirements-latex.lock'
        marker = self.meta / 'latex.json'
        if not marker.exists() or read_json(marker).get('lock') != sha(lock) or not (venv / 'bin/latex2text').is_file():
            if not venv.exists():
                self.run([self.root / 'bin/uv', 'venv', '--python', self.root / 'runtime/bin/python-app', venv])
            self.run([self.root / 'bin/uv', 'pip', 'install', '--python', venv / 'bin/python', '--require-hashes', '-r', lock])
            write_json(marker, {'lock': sha(lock)})
        self.install_notebook_runtime()
        self.stage_marker('plugins')

    def notebook_inputs(self):
        requirements = self.payload / 'nvim/lua/config/media/runtime/requirements.txt'
        expected = {name: next((p['commit'] for p in self.plugins if p['name'] == name), None)
                    for name in ('molten-nvim', 'jupytext.nvim')}
        if not all(expected.values()):
            raise InstallError('Frozen Notebook plugin sources are missing from plugins.json.')
        installed = self.root / 'config/nvim/lua/config/media/runtime/requirements.txt'
        if not installed.is_file() or sha(installed) != sha(requirements):
            raise InstallError('Notebook requirements are missing or locally edited; configuration was preserved.')
        return {'requirements': sha(requirements), 'python': self.manifest['runtimes']['mason_python'],
                'platform': self.target, 'plugins': expected,
                'bootstrap': sha(self.bundle / 'scripts/bootstrap-plugins.lua')}

    def notebook_files(self):
        venv = self.profile_data / 'glow-notebook-venv'
        return (venv / 'pyvenv.cfg', venv / 'share/jupyter/kernels/glow-python/kernel.json',
                self.profile_data / 'rplugin.vim')

    def notebook_packages(self):
        # Import the host dependencies, but never instantiate/start a kernel.
        code = ('import importlib.metadata as m, json; '
                'import pynvim, jupyter_client, jupytext, nbformat, PIL, matplotlib; '
                'print(json.dumps(sorted((d.metadata["Name"].lower().replace("_", "-"), '
                'd.version) for d in m.distributions())))')
        result = self.run([self.profile_data / 'glow-notebook-venv/bin/python', '-c', code], capture=True)
        return fingerprint(json.loads(result))

    def check_notebook_runtime(self):
        marker = self.meta / 'notebook-runtime.json'
        if not marker.is_file():
            raise InstallError('Notebook runtime has no completed installer record.')
        record = read_json(marker)
        if record.get('inputs') != self.notebook_inputs() or record.get('status') != 'ready':
            raise InstallError('Notebook runtime is incomplete or has a different frozen input.')
        for path in self.notebook_files():
            if not path.is_file() or sha(path) != record.get('files', {}).get(str(path)):
                raise InstallError('Notebook generated file missing/changed; preserved: ' + str(path))
        if self.notebook_packages() != record.get('packages'):
            raise InstallError('Notebook Python packages changed; existing environment was preserved.')
        return record

    def install_notebook_runtime(self):
        inputs = self.notebook_inputs()
        marker = self.meta / 'notebook-runtime.json'
        venv = self.profile_data / 'glow-notebook-venv'
        record = read_json(marker) if marker.is_file() else None
        if record:
            if record.get('inputs') != inputs:
                raise InstallError('Notebook runtime inputs changed; existing environment was preserved.')
            if record.get('status') == 'ready':
                self.check_notebook_runtime()
                say('Frozen Notebook runtime and remote-plugin registration retained; no package install needed.')
                return
        elif venv.exists() or self.notebook_files()[-1].exists():
            raise InstallError('Unmanaged Notebook environment/remote-plugin manifest was preserved.')
        # Record ownership before creating the environment so interrupted installs
        # can resume. A different existing environment is never pip-synced.
        write_json(marker, {'inputs': inputs, 'status': 'preparing'})
        if not (venv / 'bin/python').is_file():
            self.run([self.root / 'bin/uv', 'venv', '--python', self.root / 'runtime/bin/python3', venv])
        requirements = self.payload / 'nvim/lua/config/media/runtime/requirements.txt'
        self.run([self.root / 'bin/uv', 'pip', 'sync', '--python', venv / 'bin/python', requirements])
        self.run([venv / 'bin/python', '-m', 'ipykernel', 'install', '--prefix', venv,
                  '--name', 'glow-python', '--display-name', 'Neovide Glow Python'])
        env = dict(self.env, NEOVIDE_BUNDLE_PAYLOAD=str(self.payload), NVIM_BUNDLE_PHASE='notebook')
        self.run([self.root / 'bin/nvim', '--headless', '-u', 'NONE', '-l',
                  self.bundle / 'scripts/bootstrap-plugins.lua'], env=env)
        packages = self.notebook_packages()
        files = self.notebook_files()
        if not all(path.is_file() for path in files):
            raise InstallError('Notebook setup did not create its environment, kernel spec and remote-plugin manifest.')
        write_json(marker, {'inputs': inputs, 'status': 'ready', 'packages': packages,
                            'files': {str(path): sha(path) for path in files}})
        say('Frozen Notebook Python host, prefix-only kernel and remote plugins are ready; no kernel was started.')

    def stage_marker(self, stage):
        write_json(self.meta / 'stages' / (stage + '.json'), {'stack_id': self.stack_id, 'manifest_sha256': sha(self.manifest_path), 'completed': time.strftime('%Y-%m-%dT%H:%M:%S%z')})

    def languages(self):
        self.require_tools()
        for plugin in self.plugins:
            self.verify_source(plugin, self.profile_data / 'lazy' / plugin['name'])
        script = self.bundle / 'scripts/bootstrap-plugins.lua'
        for phase in ('parsers', 'mason', 'health'):
            marker = self.meta / 'languages' / (phase + '.json')
            inputs = fingerprint({'script': sha(script), 'treesitter': sha(self.payload / 'treesitter.json'), 'grammar_lock': sha(self.payload / 'treesitter-lock.json'), 'mason': sha(self.payload / 'mason.json')})
            if phase != 'health' and marker.exists() and read_json(marker).get('inputs') == inputs:
                say('Completed language phase retained: ' + phase)
                continue
            env = dict(self.env, NEOVIDE_BUNDLE_PAYLOAD=str(self.payload), NEOVIDE_BUNDLE_PLATFORM=self.target, NVIM_BUNDLE_PHASE=phase)
            self.run([self.root / 'bin/nvim', '--headless', '-u', 'NONE', '-l', script], env=env)
            write_json(marker, {'inputs': inputs})
        self.stage_marker('languages')

    def activate(self):
        if not self.is_mac:
            raise InstallError('--activate is a macOS Finder option; use the generated Windows launcher instead.')
        source = self.root / 'config/neovide/config.toml'
        destination = Path.home() / '.config/neovide/config.toml'
        if not source.is_file():
            raise InstallError('Run --stage tools before activation.')
        if destination.exists() and destination.read_bytes() != source.read_bytes():
            backup_dir = self.root / 'backups'
            backup_dir.mkdir(parents=True, exist_ok=True)
            backup = backup_dir / ('neovide-config-' + time.strftime('%Y%m%d-%H%M%S') + '.toml')
            if backup.exists():
                raise InstallError('Activation backup already exists; wait one second and retry.')
            shutil.copy2(destination, backup)
            say('Previous Finder config backed up: ' + str(backup))
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        say('Finder activation config written: ' + str(destination))

    def install(self):
        if self.args.activation_only:
            self.activate()
            return
        missing = self.prereqs(self.args.stage)
        if missing:
            raise InstallError('Missing prerequisites: ' + ', '.join(missing) + '\n' + self.instructions())
        self.root.mkdir(parents=True, exist_ok=True)
        say(f'Installing {self.stack_id} into {self.root}; existing editor configurations stay untouched.')
        if self.args.stage in ('all', 'tools'):
            self.tools()
        if self.args.stage in ('all', 'plugins'):
            self.plugins_stage()
        if self.args.stage in ('all', 'languages'):
            self.languages()
        if self.args.activate:
            self.activate()
        say('Requested stage completed. Launcher: ' + str(self.root / 'bin/nvim'))
        say('Optional MarkdownPreview/Peek, full TeX and rich video/PDF/image preview dependencies were not installed. Mason pins top-level versions; transitive dependencies are not fully frozen. Windows appearance still requires Windows-machine testing.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--plan', action='store_true', help='Show pinned inputs and prerequisites without writing or downloading.')
    modes.add_argument('--doctor', action='store_true', help='Read-only local prerequisite and source check; exits nonzero for missing/changed items.')
    parser.add_argument('--target', choices=('auto', 'wsl'), default='auto')
    parser.add_argument('--manifest', default=str(BUNDLE / 'manifest.json'))
    parser.add_argument('--root', help='Exact isolated stack directory; does not change shell configuration.')
    parser.add_argument('--cache-dir', help='Reuse a directory of downloaded locked artifacts.')
    parser.add_argument('--stage', choices=('tools', 'plugins', 'languages', 'all'), default=None)
    parser.add_argument('--activate', action='store_true', help='macOS only: back up and write the user Finder Neovide config explicitly.')
    args = parser.parse_args()
    args.activation_only = args.activate and args.stage is None and not (args.plan or args.doctor)
    args.stage = args.stage or 'all'
    if sys.version_info < (3, 12):
        parser.error('Python 3.12+ is required. Install it explicitly before running the bootstrap.')
    try:
        installer = Installer(args)
        if args.plan:
            installer.plan()
            return 0
        if args.doctor:
            return installer.doctor()
        installer.install()
        return 0
    except (InstallError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print('INSTALL FAILED: ' + str(error), file=sys.stderr, flush=True)
        print('Existing files and source edits were preserved. Resolve the reported failure and rerun the same stage; no reset/clean or application replacement was performed.', file=sys.stderr)
        return 1

if __name__ == '__main__':
    raise SystemExit(main())
