#!/usr/bin/env python3
"""Build and install a Linux GUI core without changing an existing editor.

Use the existing install.sh for the full x86_64 profile, then pass --profile-root
here. ARM64 can use an existing Neovim/config; the frozen profile downloads are
x86_64 only. `plan` and `doctor` never install packages or start a GUI.
"""
import argparse
import ctypes.util
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile


BUNDLE = Path(__file__).resolve().parents[1]
TARGETS = {"x86_64": ("x86_64-unknown-linux-gnu", 62),
           "aarch64": ("aarch64-unknown-linux-gnu", 183)}


class LinuxError(Exception):
    pass


def architecture(machine):
    machine = {"amd64": "x86_64", "arm64": "aarch64"}.get(machine.lower(), machine.lower())
    if machine not in TARGETS:
        raise LinuxError("Supported Linux architectures: x86_64 and aarch64.")
    return machine


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command, **kwargs):
    result = subprocess.run([str(part) for part in command], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise LinuxError(shlex.join([str(p) for p in command]) + "\n" + result.stderr[-3000:])
    return result.stdout.strip()


def linux_config(template, nvim):
    # Buttonless/transparent are macOS-only Frame enum variants.
    result = re.sub(r'^neovim-bin\s*=.*$', lambda _: 'neovim-bin = ' + json.dumps(str(nvim)), template, flags=re.M)
    result = re.sub(r'^frame\s*=.*$', 'frame = "none"', result, flags=re.M)
    result = re.sub(r'^title-hidden\s*=.*\n?', '', result, flags=re.M)
    return result.replace('"PingFang SC"', '"Noto Sans Mono CJK SC"')


def launcher(profile=None):
    extra = ""
    if profile:
        extra = '''PROFILE={profile}
if [ ! -x "$PROFILE/bin/nvim" ] || [ ! -d "$PROFILE/config/nvim" ]; then
  echo "The configured Glow profile is unavailable: $PROFILE" >&2; exit 1
fi
export XDG_CONFIG_HOME="$PROFILE/config" XDG_DATA_HOME="$PROFILE/data"
export XDG_STATE_HOME="$PROFILE/state" XDG_CACHE_HOME="$PROFILE/cache" NVIM_APPNAME=nvim
export YAZI_CONFIG_HOME="$PROFILE/config/yazi"
export PATH="$PROFILE/bin:$PROFILE/data/nvim/mason/bin:$PROFILE/runtime/bin:$PATH"
'''.format(profile=shlex.quote(str(profile)))
    return '''#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
{extra}export NEOVIDE_CONFIG="$ROOT/config/neovide/config.toml"
exec "$ROOT/lib/neovide" "$@"
'''.format(extra=extra)


def check_elf(path, arch):
    with Path(path).open('rb') as stream:
        header = stream.read(64)
    if (len(header) < 64 or header[:6] != b'\x7fELF\x02\x01'
            or int.from_bytes(header[16:18], 'little') not in (2, 3)
            or int.from_bytes(header[18:20], 'little') != TARGETS[arch][1]):
        raise LinuxError("Expected a Linux 64-bit ELF executable for " + arch + ": " + str(path))


def neovim(path):
    if not path or not Path(path).is_file() or not os.access(path, os.X_OK):
        raise LinuxError("Neovim is missing. Pass --nvim /path/to/nvim or an installed --profile-root.")
    lines = run([path, '--version']).splitlines()
    first = lines[0] if lines else '(empty version output)'
    match = re.search(r'NVIM v(\d+)\.(\d+)', first)
    if not match or tuple(map(int, match.groups())) < (0, 12):
        raise LinuxError("Neovim 0.12+ is required; found " + first)
    return first


def build_checks(toolchain):
    missing = [name for name in ('git', 'cargo', 'rustup', 'cc', 'c++', 'cmake', 'ninja', 'clang', 'pkg-config')
               if not shutil.which(name)]
    if shutil.which('pkg-config'):
        for library in ('fontconfig', 'freetype2', 'x11', 'xcursor', 'xi', 'gl'):
            if subprocess.run(['pkg-config', '--exists', library], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode:
                missing.append('pkg-config:' + library)
    if shutil.which('rustup'):
        installed = run(['rustup', 'toolchain', 'list']).splitlines()
        if not any(line.split()[0].startswith(toolchain + '-') for line in installed):
            missing.append('Rust toolchain ' + toolchain + ' (rustup toolchain install ' + toolchain + ' --profile minimal)')
    return missing


def committed_inputs(source, revision):
    commit = run(['git', '-C', source, 'rev-parse', '--verify', revision + '^{commit}'])
    manifest_text = run(['git', '-C', source, 'show', commit + ':portable/manifest.json'])
    return commit, json.loads(manifest_text)


def build(source, commit, root, arch, toolchain):
    missing = build_checks(toolchain)
    if missing:
        raise LinuxError('Missing build prerequisites: ' + ', '.join(missing))
    source_dir = root / 'source' / commit
    # Always build an immutable committed snapshot, never the active checkout or
    # its shared target symlink. Refuse stale/unowned source directories.
    if source_dir.exists():
        raise LinuxError('Build snapshot already exists; preserve it and choose another --root: ' + str(source_dir))
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryFile() as archive:
        subprocess.run(['git', '-C', str(source), 'archive', '--format=tar', commit], stdout=archive, check=True)
        archive.seek(0)
        with tarfile.open(fileobj=archive) as tar:
            members = tar.getmembers()
            for member in members:
                if (Path(member.name).is_absolute() or '..' in Path(member.name).parts
                        or not (member.isfile() or member.isdir())):
                    raise LinuxError('Unsafe source archive member: ' + member.name)
            source_dir.mkdir(parents=True)
            tar.extractall(source_dir, members=members)
    target = root / 'build' / commit
    env = dict(os.environ, CARGO_TARGET_DIR=str(target))
    command = ['cargo', '+' + toolchain, 'build', '--locked', '--release', '--bin', 'neovide', '--target', TARGETS[arch][0]]
    print('Building committed source ' + commit + ' in ' + str(target), flush=True)
    subprocess.run(command, cwd=source_dir, env=env, check=True)
    binary = target / TARGETS[arch][0] / 'release/neovide'
    check_elf(binary, arch)
    receipt = {'commit': commit, 'architecture': arch, 'toolchain': toolchain,
               'binary': str(binary), 'sha256': digest(binary), 'command': command}
    (root / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def install(root, binary, nvim, profile, arch, commit):
    check_elf(binary, arch)
    version = run([binary, '--version'])  # Checks the real dynamic loader; no window is opened.
    nvim_version = neovim(nvim)
    if profile and not (profile / 'config/nvim').is_dir():
        raise LinuxError('Missing Glow configuration in --profile-root: ' + str(profile))
    template = (BUNDLE / 'payload/neovide/config.toml').read_text()
    files = {'lib/neovide': Path(binary).read_bytes(),
             'bin/neovide-glow': launcher(profile).encode(),
             'config/neovide/config.toml': linux_config(template, nvim).encode(),
             'share/icons/neovide.svg': (BUNDLE.parent / 'assets/neovide.svg').read_bytes()
             if (BUNDLE.parent / 'assets/neovide.svg').is_file() else b''}
    for path in (BUNDLE / 'licenses').iterdir():
        if path.is_file():
            files['licenses/' + path.name] = path.read_bytes()
    for name in ('THIRD-PARTY-NOTICES.md',):
        if (BUNDLE.parent / name).is_file():
            files['licenses/' + name] = (BUNDLE.parent / name).read_bytes()
    receipt = {'schema': 1, 'architecture': arch, 'source_commit': commit,
               'version': version, 'neovim_version': nvim_version,
               'profile': str(profile) if profile else None,
               'files': {name: hashlib.sha256(content).hexdigest() for name, content in files.items()},
               'gui_verified': False}
    receipt_text = json.dumps(receipt, indent=2) + '\n'
    files['linux-core.json'] = receipt_text.encode()
    # Preflight every destination before writing any application file.
    for relative, content in files.items():
        path = root / relative
        if any(parent.is_symlink() for parent in path.parents if parent != root and root in parent.parents):
            raise LinuxError('Existing directory symlink preserved: ' + str(path))
        if path.is_symlink() or (path.exists() and (not path.is_file() or path.read_bytes() != content)):
            raise LinuxError('Existing different file preserved; choose another --root: ' + str(path))
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        if relative in ('lib/neovide', 'bin/neovide-glow'):
            path.chmod(0o755)
    print('Installed Linux core: ' + str(root / 'bin/neovide-glow'))


def package(root, output):
    receipt_path = root / 'linux-core.json'
    receipt = json.loads(receipt_path.read_text())
    files = [receipt_path]
    for relative, expected in receipt['files'].items():
        if Path(relative).is_absolute() or '..' in Path(relative).parts:
            raise LinuxError('Invalid installed file path: ' + relative)
        path = root / relative
        if any(parent.is_symlink() for parent in path.parents if parent != root and root in parent.parents):
            raise LinuxError('Installed directory symlink changed; package refused: ' + str(path))
        if path.is_symlink() or not path.is_file() or digest(path) != expected:
            raise LinuxError('Installed file changed; package refused: ' + str(path))
        files.append(path)
    if output.exists():
        raise LinuxError('Output already exists and was preserved: ' + str(output))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('xb') as stream:
        with tarfile.open(fileobj=stream, mode='w:gz') as tar:
            for path in files:
                tar.add(path, arcname='neovide-glow-linux-' + receipt['architecture'] + '/' + str(path.relative_to(root)), recursive=False)
    print(json.dumps({'archive': str(output), 'sha256': digest(output), 'bytes': output.stat().st_size,
                      'scope': 'Linux GUI core; external Neovim/profile paths remain prerequisites'}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('plan', 'doctor', 'build', 'install', 'package'), nargs='?', default='plan')
    parser.add_argument('--source', type=Path, default=BUNDLE.parent)
    parser.add_argument('--revision', default='HEAD')
    parser.add_argument('--root', type=Path)
    parser.add_argument('--arch', choices=tuple(TARGETS))
    parser.add_argument('--profile-root', type=Path)
    parser.add_argument('--nvim', type=Path)
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    arch = args.arch or architecture(platform.machine())
    manifest = json.loads((BUNDLE / 'manifest.json').read_text())
    commit = None
    if (args.source / '.git').exists():
        commit, manifest = committed_inputs(args.source, args.revision)
    toolchain = manifest['neovide']['rust_toolchain']
    root = (args.root or Path.home() / '.local/share/neovide-glow/native' /
            ((commit[:12] if commit else manifest['stack_id']) + '-' + arch)).expanduser().resolve()
    profile = args.profile_root.expanduser().resolve() if args.profile_root else None
    nvim = args.nvim.expanduser().absolute() if args.nvim else profile / 'bin/nvim' if profile else shutil.which('nvim')
    if args.command == 'plan':
        print(json.dumps({'architecture': arch, 'target': TARGETS[arch][0], 'root': str(root),
                          'source_commit': commit, 'toolchain': toolchain,
                          'neovim': str(nvim) if nvim else None, 'profile': str(profile) if profile else None,
                          'build_target': str(root / 'build'), 'gui_verified': False,
                          'host_changes': False}, indent=2))
        return 0
    if sys.platform != 'linux' or architecture(platform.machine()) != arch:
        raise LinuxError('Run this action on native Linux of the selected architecture; cross builds are not enabled.')
    if args.command == 'doctor':
        missing = build_checks(toolchain)
        try:
            nvim_result = neovim(nvim)
        except LinuxError as error:
            nvim_result = str(error)
        libraries = {name: ctypes.util.find_library(name) for name in (
            'GL', 'fontconfig', 'xkbcommon', 'X11', 'wayland-client',
            'gtk-3', 'webkit2gtk-4.1', 'webkit2gtk-4.0', 'poppler-glib')}
        helper = args.source / 'src/native_preview/linux_helper.py'
        preview = {'kinds': [], 'reason': 'Helper probe source is unavailable; see the Linux native preview deployment instructions.'}
        if helper.is_file():
            interpreter = os.environ.get('NEOVIDE_LINUX_PREVIEW_PYTHON', '/usr/bin/python3')
            try:
                probe = subprocess.run([interpreter, '-I', '-B', str(helper), '--probe'],
                                       text=True, capture_output=True, timeout=5)
                preview = json.loads(probe.stdout) if probe.returncode == 0 else {'kinds': [], 'error': probe.stderr[-1000:]}
            except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                preview = {'kinds': [], 'error': str(error)}
        print(json.dumps({'architecture': arch, 'missing_build_prerequisites': missing,
                          'neovim': nvim_result, 'runtime_libraries': libraries,
                          'native_preview_dependencies': preview,
                          'display_available': bool(os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')),
                          'gui_verified': False, 'host_changes': False}, indent=2))
        return int(bool(missing) or not nvim_result.startswith('NVIM v') or not libraries['GL'] or
                   not (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')))
    if args.command == 'build':
        if not commit:
            raise LinuxError('--source must be a Git checkout; only committed source can be built.')
        print(json.dumps(build(args.source.resolve(), commit, root, arch, toolchain), indent=2))
    elif args.command == 'install':
        binary = args.binary.expanduser().resolve() if args.binary else None
        if binary:
            commit = None  # An externally supplied ELF has no verified source provenance.
        else:
            receipt = json.loads((root / 'build.json').read_text())
            binary = Path(receipt['binary'])
            if digest(binary) != receipt['sha256'] or receipt['architecture'] != arch:
                raise LinuxError('Build binary does not match its receipt.')
            commit = receipt['commit']
        install(root, binary, nvim, profile, arch, commit)
    else:
        if not args.output:
            raise LinuxError('package requires --output /path/to/new-archive.tar.gz')
        package(root, args.output.expanduser().resolve())
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (LinuxError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
