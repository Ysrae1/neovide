#!/usr/bin/env python3
"""Package only reviewed deployment files; never include caches or user state."""
from pathlib import Path
import argparse, hashlib, io, json, os, shutil, tarfile, zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
args = parser.parse_args()
out = Path(args.output).resolve()
out.mkdir(parents=True, exist_ok=True)
name = 'Neovide-Glow-20261017'
files = []
for item in ('README.md', 'DEPLOY.md', 'manifest.json', 'install.sh', 'install.ps1', 'scripts', 'payload', 'licenses'):
    path = ROOT / item
    if path.is_file(): files.append(path)
    else: files.extend(p for p in sorted(path.rglob('*')) if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc')
for p in files:
    if p.is_symlink(): raise SystemExit('Unexpected packaged symlink: ' + str(p))
    if any(part in ('.git', 'node_modules', '.codex', 'download-cache') for part in p.relative_to(ROOT).parts):
        raise SystemExit('Private/runtime content in package: ' + str(p))
checksums = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
checksum_bytes = (json.dumps(checksums, indent=2) + '\n').encode()
archive = io.BytesIO()
with tarfile.open(fileobj=archive, mode='w:gz') as tar:
    for p in files:
        info = tar.gettarinfo(str(p), arcname=str(p.relative_to(ROOT)))
        info.uid = info.gid = 0; info.uname = info.gname = ''
        with p.open('rb') as f: tar.addfile(info, f)
    info = tarfile.TarInfo('bundle-sha256.json'); info.size = len(checksum_bytes); info.mode = 0o644
    tar.addfile(info, io.BytesIO(checksum_bytes))
data = archive.getvalue()
sha = hashlib.sha256(data).hexdigest()
header = '''#!/usr/bin/env bash
# Self-contained Apple Silicon Mac deployment entry. Sources and pinned payload
# are inside this file. Runtime dependencies are fetched from the locked URLs.
set -euo pipefail
case "$(uname -s):$(uname -m)" in Darwin:arm64) ;; *) echo 'This single-file entry supports Apple Silicon Mac. Use the ZIP install.ps1 on Windows.' >&2; exit 1;; esac
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/neovide-glow.XXXXXX")"
trap 'rm -rf -- "$scratch_dir"' EXIT
archive_line="$(awk '/^__NEOVIDE_GLOW_PAYLOAD_BELOW__$/ { print NR + 1; exit }' "$0")"
actual_sha="$(tail -n +"$archive_line" "$0" | shasum -a 256 | awk '{print $1}')"
if [ "$actual_sha" != '__SHA__' ]; then echo 'Embedded payload checksum mismatch. Nothing was installed.' >&2; exit 1; fi
tail -n +"$archive_line" "$0" | tar -xz -C "$scratch_dir"
bash "$scratch_dir/install.sh" "$@"
exit $?
__NEOVIDE_GLOW_PAYLOAD_BELOW__
'''.replace('__SHA__', sha).encode()
sh = out / (name + '-macOS-arm64.sh')
sh.write_bytes(header + data); sh.chmod(0o755)
zip_path = out / (name + '.zip')
with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for p in files: z.write(p, arcname=str(Path(name) / p.relative_to(ROOT)))
    z.writestr(name + '/bundle-sha256.json', checksum_bytes)
shutil.copy2(ROOT / 'DEPLOY.md', out / '部署说明.md')
shutil.copy2(ROOT / 'README.md', out / 'README.md')
(out / 'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in (sh, zip_path)))
print(f'Created {sh.name} ({sh.stat().st_size:,} bytes), {zip_path.name} ({zip_path.stat().st_size:,} bytes)')
