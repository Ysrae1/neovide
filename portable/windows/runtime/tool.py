"""Relocatable entry point for the installer's precompiled Python CLI shims."""

from importlib import metadata
import sys


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) < 2 or argv[0] != "--entry" or not argv[1]:
        print("Usage: tool.py --entry CONSOLE_SCRIPT [arguments ...]", file=sys.stderr)
        return 2
    name, arguments = argv[1], argv[2:]
    matches = list(metadata.entry_points(group="console_scripts", name=name))
    if len(matches) != 1:
        print(f"Packaged Python command {name!r} is missing or ambiguous. Reinstall Neovide Glow.", file=sys.stderr)
        return 1
    previous = sys.argv
    try:
        sys.argv = [name, *arguments]
        return matches[0].load()()
    finally:
        sys.argv = previous


if __name__ == "__main__":
    sys.exit(main())
