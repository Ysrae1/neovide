"""Run a pinned Mason Python tool without its non-relocatable venv launcher."""

from importlib import metadata, util
import json
import os
from pathlib import Path
import re
import runpy
import sys
from urllib.parse import unquote


def normalize(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def package_distribution(package):
    receipt = json.loads((package / "mason-receipt.json").read_text(encoding="utf-8"))
    source = receipt.get("primary_source", {}).get("id", "")
    match = re.fullmatch(r"pkg:pypi/([^@?#]+)@([^?#]+)(?:[?#].*)?", source)
    if not match:
        raise ValueError("This is not a pinned Mason Python package")
    site = package / "venv/Lib/site-packages"
    if not site.is_dir():
        raise ValueError("The package's isolated Python dependencies are missing")
    name, version = normalize(unquote(match[1])), unquote(match[2])
    matches = [dist for dist in metadata.distributions(path=[str(site)])
               if normalize(dist.metadata.get("Name", "")) == name and dist.version == version]
    if len(matches) != 1:
        raise ValueError(f"Pinned distribution {name}=={version} is missing or ambiguous")
    return site, matches[0]


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) < 4 or argv[0] != "--package" or argv[2] not in ("--entry", "--module"):
        print("Usage: mason_tool.py --package DIRECTORY (--entry NAME | --module MODULE) [--] [arguments ...]", file=sys.stderr)
        return 2
    package, mode, name = Path(argv[1]).resolve(), argv[2], argv[3]
    arguments = argv[4:]
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    previous_argv, previous_path = sys.argv, list(sys.path)
    previous_pythonpath = os.environ.get("PYTHONPATH")
    previous_no_user_site = os.environ.get("PYTHONNOUSERSITE")
    try:
        site, distribution = package_distribution(package)
        # Do not process venv .pth files or execute its old Python executable.
        # Child adapters (debugpy) inherit the same private package imports.
        sys.path.insert(0, str(site))
        os.environ["PYTHONPATH"] = str(site)
        os.environ["PYTHONNOUSERSITE"] = "1"
        sys.argv = [name, *arguments]
        if mode == "--module":
            if not re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*", name):
                raise ValueError("Invalid Python module name")
            module = util.find_spec(name)
            if not module or not module.origin or not Path(module.origin).resolve().is_relative_to(site.resolve()):
                raise ValueError("The requested Python module does not belong to this isolated package")
            runpy.run_module(name, run_name="__main__", alter_sys=True)
            return 0
        entries = [entry for entry in distribution.entry_points if entry.group == "console_scripts" and entry.name == name]
        if len(entries) != 1:
            raise ValueError(f"Pinned console command {name!r} is missing or ambiguous")
        return entries[0].load()()
    except (OSError, ValueError) as error:
        print(f"Neovide Glow Python tool failed: {error}", file=sys.stderr)
        return 1
    finally:
        sys.argv, sys.path[:] = previous_argv, previous_path
        if previous_pythonpath is None:
            os.environ.pop("PYTHONPATH", None)
        else:
            os.environ["PYTHONPATH"] = previous_pythonpath
        if previous_no_user_site is None:
            os.environ.pop("PYTHONNOUSERSITE", None)
        else:
            os.environ["PYTHONNOUSERSITE"] = previous_no_user_site


if __name__ == "__main__":
    sys.exit(main())
