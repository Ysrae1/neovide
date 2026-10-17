#!/usr/bin/env python3
"""Resolve explicit official releases and verify one cached download per artifact.

This maintenance helper never installs tools or updates the user's environment.
Every version is deliberate. No fallback to latest is allowed.
"""
import argparse
import concurrent.futures
import hashlib
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / 'download-cache'
MANIFEST = ROOT / 'manifest.json'
UA = {'User-Agent': 'neovide-glow-lock-resolver', 'Accept': 'application/vnd.github+json'}
PLATFORMS = ('macos-arm64', 'linux-x86_64')
UNIMATRIX_COMMIT = 'dff519f972103f91384f360f270614184de8aa92'
SPECS = {
 'tree_sitter': ('0.25.3', 'tree-sitter/tree-sitter', 'v0.25.3', ('tree-sitter-macos-arm64.gz', 'tree-sitter-linux-x64.gz'), 'tree-sitter'),
 'nvim': ('0.12.3', 'neovim/neovim', 'v0.12.3', ('nvim-macos-arm64.tar.gz', 'nvim-linux-x86_64.tar.gz'), 'nvim'),
 'yazi': ('26.5.6', 'sxyazi/yazi', 'v26.5.6', ('yazi-aarch64-apple-darwin.zip', 'yazi-x86_64-unknown-linux-gnu.zip'), 'yazi'),
 'rg': ('15.2.0', 'BurntSushi/ripgrep', '15.2.0', ('ripgrep-15.2.0-aarch64-apple-darwin.tar.gz', 'ripgrep-15.2.0-x86_64-unknown-linux-musl.tar.gz'), 'rg'),
 'fd': ('10.4.2', 'sharkdp/fd', 'v10.4.2', ('fd-v10.4.2-aarch64-apple-darwin.tar.gz', 'fd-v10.4.2-x86_64-unknown-linux-gnu.tar.gz'), 'fd'),
 'fzf': ('0.73.1', 'junegunn/fzf', 'v0.73.1', ('fzf-0.73.1-darwin_arm64.tar.gz', 'fzf-0.73.1-linux_amd64.tar.gz'), 'fzf'),
 'lazygit': ('0.62.2', 'jesseduffield/lazygit', 'v0.62.2', ('lazygit_0.62.2_darwin_arm64.tar.gz', 'lazygit_0.62.2_linux_x86_64.tar.gz'), 'lazygit'),
 'uv': ('0.11.24', 'astral-sh/uv', '0.11.24', ('uv-aarch64-apple-darwin.tar.gz', 'uv-x86_64-unknown-linux-gnu.tar.gz'), 'uv'),
 'fff': ('0.11.0', 'dmtrKovalenko/fff', 'v0.11.0', ('aarch64-apple-darwin.dylib', 'x86_64-unknown-linux-gnu.so'), None),
 'font': ('3.3.0', 'ryanoasis/nerd-fonts', 'v3.3.0', ('FiraCode.zip',), None),
 'cmatrix': ('2.0', 'abishekvashok/cmatrix', 'v2.0', ('cmatrix-v2.0-Butterscotch.tar',), 'cmatrix'),
}

def request(url):
 return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120)

def read_metadata(name, url):
 path = CACHE / name
 if not path.exists():
  with request(url) as response:
   data = response.read()
  path.write_bytes(data)
 return path.read_bytes()

def digest(path):
 h = hashlib.sha256()
 with path.open('rb') as stream:
  for block in iter(lambda: stream.read(1024*1024), b''):
   h.update(block)
 return h.hexdigest()

def archive_format(name):
 if name.endswith('.tar.gz'): return 'tar.gz'
 if name.endswith('.zip'): return 'zip'
 if name.endswith('.tar'): return 'tar'
 if name.endswith('.gz'): return 'gzip'
 return 'raw'

def verify_or_download(task):
 key, platform, entry, expected = task
 name = entry['filename']
 path = CACHE / name
 if not path.exists():
  partial = path.with_name(path.name + '.partial')
  try:
   with request(entry['url']) as response, partial.open('wb') as target:
    while True:
     block = response.read(1024*1024)
     if not block: break
     target.write(block)
   partial.replace(path)
  except BaseException:
   partial.unlink(missing_ok=True)
   raise
 actual = digest(path)
 if expected and actual != expected:
  raise ValueError(f'{key}/{platform}: SHA256 mismatch, expected {expected}, got {actual}')
 entry['sha256'] = actual
 entry['checksum_source'] = ('official-release-sha256' if expected else 'sha256-of-fixed-official-artifact')
 entry['download_size'] = path.stat().st_size
 print(f'OK {key}/{platform} {path.stat().st_size} bytes {actual}', flush=True)
 return key, platform

def main():
 parser = argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--verify-cache', action='store_true', help='Validate the current manifest against cached artifacts, without network access.')
 args = parser.parse_args()
 CACHE.mkdir(parents=True, exist_ok=True)
 if args.verify_cache:
  data = json.loads(MANIFEST.read_text())
  total = 0
  for key, tool in data['assets'].items():
   for platform, entry in tool['platforms'].items():
    path = CACHE / entry['filename']
    actual = digest(path)
    if actual != entry['sha256']:
     raise ValueError(f'{key}/{platform}: cached artifact mismatch')
    total += 1
  print(f'Validated {total} cached artifacts.')
  return
 data = {
  'schema_version': 1,
  'stack_id': 'neovide-glow-20261017',
  'neovide': {'repo': 'https://github.com/Ysrae1/neovide.git', 'commit': '6c152c4d4761b5eda75f67dbd82beaa3a0afb59f', 'rust_toolchain': '1.99.1'},
  'runtimes': {'python': '3.14.6'},
  'assets': {},
 }
 # Preserve other explicit sections added by the main installer author.
 old = {}
 if MANIFEST.exists():
  old = json.loads(MANIFEST.read_text())
  for key,value in old.items():
   if key not in data:
    data[key] = value
  data['neovide'].update(old.get('neovide', {}))
  data['runtimes'].update(old.get('runtimes', {}))
  # Preserve Python's explicit historical build locks; never resolve them to latest.
  for key in ('python', 'python_mason'):
   if key in old.get('assets', {}):
    data['assets'][key] = old['assets'][key]
 tasks = []
 for key,(version,repo,tag,names,binary) in SPECS.items():
  release = json.loads(read_metadata(f'{key}-release.json', f'https://api.github.com/repos/{repo}/releases/tags/{tag}'))
  index = {a['name']: a for a in release['assets']}
  tool = {'version': version, 'source': f'https://github.com/{repo}', 'release': release['html_url'], 'platforms': {}}
  for position,name in enumerate(names):
   platform = 'any' if len(names) == 1 else PLATFORMS[position]
   if name not in index:
    raise ValueError(f'Explicit release {repo}@{tag} lacks required asset {name}')
   source = index[name]
   entry = {'url': source['browser_download_url'], 'filename': name, 'format': archive_format(name)}
   if binary: entry['binary'] = binary
   if key == 'fff': entry['install_name'] = 'libfff_nvim.dylib' if platform == 'macos-arm64' else 'libfff_nvim.so'
   if key == 'cmatrix': entry['build_from_source'] = True
   expected = (source.get('digest') or '').removeprefix('sha256:') or None
   tool['platforms'][platform] = entry
   tasks.append((key,platform,entry,expected))
  # Keep explicit source patch locks and other metadata authored separately.
  for extra,value in old.get('assets', {}).get(key, {}).items():
   if extra not in tool:
    tool[extra] = value
  data['assets'][key] = tool
 checksums = read_metadata('node-shasums.txt', 'https://nodejs.org/dist/v26.3.1/SHASUMS256.txt').decode()
 checksums = dict((line.split()[1].lstrip('*'),line.split()[0]) for line in checksums.splitlines() if len(line.split()) == 2)
 node = {'version': '26.3.1', 'source': 'https://nodejs.org', 'checksums_url': 'https://nodejs.org/dist/v26.3.1/SHASUMS256.txt', 'platforms': {}}
 for platform,suffix in zip(PLATFORMS, ('darwin-arm64','linux-x64')):
  name = f'node-v26.3.1-{suffix}.tar.gz'
  if name not in checksums: raise ValueError(f'Official Node SHA256 list lacks {name}')
  entry = {'url': f'https://nodejs.org/dist/v26.3.1/{name}', 'filename': name, 'format': 'tar.gz', 'binary': 'node'}
  node['platforms'][platform] = entry
  tasks.append(('node',platform,entry,checksums[name]))
 data['assets']['node'] = node
 url = f'https://raw.githubusercontent.com/will8211/unimatrix/{UNIMATRIX_COMMIT}/unimatrix.py'
 entry = {'url':url,'filename':f'unimatrix-{UNIMATRIX_COMMIT}.py','format':'raw','binary':'unimatrix'}
 data['assets']['unimatrix'] = {'version':UNIMATRIX_COMMIT, 'source':'https://github.com/will8211/unimatrix', 'commit':UNIMATRIX_COMMIT,'platforms':{'any':entry}}
 tasks.append(('unimatrix','any',entry,None))
 # One fetch and one digest calculation per requested artifact. Entries without
 # publisher checksums explicitly disclose that the lock was obtained from bytes.
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
  list(pool.map(verify_or_download,tasks))
 MANIFEST.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 print(f'Wrote {MANIFEST} with {len(tasks)} pinned, downloaded artifacts.')

if __name__ == '__main__':
 main()
