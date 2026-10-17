#!/usr/bin/env bash
set -euo pipefail
bundle_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3.12+ is required to start this installer. macOS: install Python using Homebrew; Ubuntu 24.04: install python3. No system packages were changed.' >&2
  exit 1
fi
exec python3 -B "$bundle_dir/scripts/install.py" "$@"
