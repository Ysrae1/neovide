#!/usr/bin/env python3
"""Builder fixture: argv and lifecycle tests only, no shell invocation."""
import pathlib
import sys
import time
root = pathlib.Path.cwd()
print('fixture build started', flush=True)
if (root / 'slow').exists():
    time.sleep(30)
if (root / 'fail').exists():
    print('fixture build error', file=sys.stderr, flush=True)
    sys.exit(7)
countfile = root / 'count'
count = int(countfile.read_text()) + 1 if countfile.exists() else 1
countfile.write_text(str(count))
output = root / '_build/html'
output.mkdir(parents=True, exist_ok=True)
(output / 'index.html').write_text(f'<!doctype html><h1>Build {count}</h1>')
print(f'fixture build {count} complete', flush=True)
