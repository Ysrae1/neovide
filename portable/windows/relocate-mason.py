#!/usr/bin/env python3
"""Seal the build-worker's Mason tree for a movable offline Windows profile.

Only the assembled stage is edited. Tool versions and dependency files stay
pinned; generated launchers stop referring to the worker's absolute paths.
"""

import argparse
from importlib import metadata
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import sys
from urllib.parse import unquote
import zipfile


class RelocationError(RuntimeError):
    pass


def normalize(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def relative_file(package, value):
    value = value.replace("\\", "/")
    path = PurePosixPath(value)
    if not value or path.is_absolute() or PureWindowsPath(value).drive or any(part in ("..", ".") for part in path.parts):
        raise RelocationError("Invalid package-relative link: " + value)
    if any(character in value for character in ('"', "%", "\r", "\n")):
        raise RelocationError("Unsafe generated command path: " + value)
    result = package.joinpath(*path.parts)
    if not result.resolve().is_relative_to(package.resolve()) or not result.is_file() or result.is_symlink():
        raise RelocationError("Missing/escaping package link: " + str(result))
    return result


def read(path):
    return path.read_text(encoding="utf-8-sig")


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))


def dp0(directory, target):
    relative = os.path.relpath(target, directory).replace("/", "\\")
    return "%~dp0" + relative


def command_wrapper(target, *, batch=False):
    # A final batch invocation transfers control without CALL's second round of
    # argument expansion. Native programs return an exit status directly.
    return '@echo off\nsetlocal DisableDelayedExpansion\n"' + target + '" %*\n' + ("" if batch else "exit /b %errorlevel%\n")


def python_wrapper(directory, package, mode, name):
    if not re.fullmatch(r"[A-Za-z0-9_.+-]+", name):
        raise RelocationError("Invalid Python command/module: " + name)
    return ('@echo off\nsetlocal DisableDelayedExpansion\n'
            'if not defined NEOVIDE_GLOW_ROOT (echo Start this tool from Neovide Glow. 1>&2 & exit /b 1)\n'
            'set "PYTHONUTF8=1"\n'
            '"%NEOVIDE_GLOW_ROOT%\\runtime\\python\\python.exe" '
            '"%NEOVIDE_GLOW_ROOT%\\runtime\\mason_tool.py" --package "' + dp0(directory, package) + '" '
            + mode + ' "' + name + '" -- %*\nexit /b %errorlevel%\n')


def pypi_distribution(package, receipt):
    source = receipt.get("primary_source", {}).get("id", "")
    match = re.fullmatch(r"pkg:pypi/([^@?#]+)@([^?#]+)(?:[?#].*)?", source)
    if not match:
        return None
    site = package / "venv/Lib/site-packages"
    name, version = normalize(unquote(match[1])), unquote(match[2])
    distributions = [dist for dist in metadata.distributions(path=[str(site)])
                     if normalize(dist.metadata.get("Name", "")) == name and dist.version == version]
    if len(distributions) != 1:
        raise RelocationError(f"Pinned Python distribution not found: {name}=={version}")
    return distributions[0]


def old_package_roots(text, relative):
    suffix = relative.replace("/", "\\").lstrip("\\")
    roots = []
    for absolute in re.findall(r'"([A-Za-z]:[^"\r\n]+)"', text):
        normalized = absolute.replace("/", "\\")
        if normalized.lower().endswith("\\" + suffix.lower()):
            roots.append(normalized[:-(len(suffix) + 1)])
    return roots


def replace_prefix(text, prefix, replacement):
    for variant in (prefix.replace("/", "\\"), prefix.replace("\\", "/")):
        text = re.sub(re.escape(variant), lambda _: replacement, text, flags=re.IGNORECASE)
    return text


def has_prefix(text, prefixes):
    lower = text.lower().replace("\\", "/")
    return any(prefix.lower().replace("\\", "/") in lower for prefix in prefixes if prefix)


def relocate(stage):
    stage = stage.resolve()
    mason = stage / "profile/data/nvim/mason"
    packages, commands = mason / "packages", mason / "bin"
    for required in (stage / "runtime/python/python.exe", stage / "runtime/mason_tool.py"):
        if not required.is_file():
            raise RelocationError("Required packaged runtime is missing: " + str(required))
    if not packages.is_dir():
        raise RelocationError("Assembled Mason packages are missing")
    commands.mkdir(parents=True, exist_ok=True)
    records, seen, all_roots = [], set(), []
    for receipt_path in sorted(packages.glob("*/mason-receipt.json")):
        package = receipt_path.parent
        receipt = json.loads(read(receipt_path))
        links = receipt.get("links", {}).get("bin", {})
        distribution = pypi_distribution(package, receipt)
        entries = {entry.name for entry in distribution.entry_points if entry.group == "console_scripts"} if distribution else set()
        roots, generated = [], set()
        for name, relative in list(links.items()):
            if not re.fullmatch(r"[A-Za-z0-9_.+-]+", name) or name in (".", ".."):
                raise RelocationError("Invalid Mason executable name: " + name)
            output = commands / (name if name.lower().endswith(".cmd") else name + ".cmd")
            if output.name.lower() in seen:
                raise RelocationError("Duplicate Mason command: " + output.name)
            seen.add(output.name.lower())
            target = relative_file(package, relative)
            if output.is_file():
                roots.extend(old_package_roots(read(output), relative))
            mode, entry = None, None
            if distribution:
                stem = target.stem
                # distlib strips .py/.pyw from Windows executable names while
                # retaining it in metadata (clang-format-diff.py is one).
                matching = [value for value in entries if value == stem or value in (stem + ".py", stem + ".pyw")]
                if len(matching) > 1:
                    raise RelocationError("Ambiguous Python executable metadata: " + str(target))
                if matching:
                    mode, entry = "--entry", matching[0]
                elif target.suffix.lower() in (".cmd", ".bat", ""):
                    module = re.search(r"\s-m\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)", read(target))
                    if module:
                        mode, entry = "--module", module[1]
                if mode:
                    # Replace both exposed and package-local entry points, then
                    # remove their obsolete distlib EXE/interpreter below.
                    local_wrapper = target.with_suffix(".cmd")
                    write(local_wrapper, python_wrapper(local_wrapper.parent, package, mode, entry))
                    generated.add(local_wrapper)
                    links[name] = local_wrapper.relative_to(package).as_posix()
                    write(output, python_wrapper(commands, package, mode, entry))
                    records.append({"package": package.name, "command": output.name, "kind": "python", "mode": mode, "entry": entry})
                    continue
                # Ruff wheels contain a genuine Rust executable instead of a
                # Python console script; retain it without inventing an entry.
                if not (target.suffix.lower() == ".exe" and target.read_bytes()[:2] == b"MZ" and not zipfile.is_zipfile(target)):
                    raise RelocationError("Unsupported Python launcher: " + str(target))
            write(output, command_wrapper(dp0(commands, target), batch=target.suffix.lower() in (".cmd", ".bat")))
            records.append({"package": package.name, "command": output.name, "kind": "native" if target.suffix.lower() == ".exe" else "relative"})

        worker_roots = [old.rsplit("\\profile\\", 1)[0] for old in roots if "\\profile\\" in old]
        all_roots.extend([*roots, *worker_roots])
        if distribution:
            # These files are never used by the relocated dispatcher. Keeping
            # them would expose non-working executables with worker shebangs.
            scripts = package / "venv/Scripts"
            if scripts.is_dir():
                linked_native = {relative_file(package, value) for value in links.values() if str(value).lower().endswith(".exe")}
                for file in scripts.iterdir():
                    if not file.is_file() or file in generated or file in linked_native:
                        continue
                    if file.suffix.lower() in (".exe", ".py", ".ps1", ".bat", ".cmd") or file.name.lower().startswith(("activate", "deactivate")):
                        file.unlink()
            (package / "venv/pyvenv.cfg").unlink(missing_ok=True)
        # npm's normal shims are relative already. Convert Mason-generated
        # package-local CMD prefixes; refuse unhandled PowerShell/.pth paths.
        for file in package.rglob("*"):
            if not file.is_file() or file.suffix.lower() not in (".cmd", ".bat", ".ps1", ".pth"):
                continue
            text = read(file)
            if file.suffix.lower() in (".cmd", ".bat"):
                for old in roots:
                    text = replace_prefix(text, old, dp0(file.parent, package))
                for old in worker_roots:
                    text = replace_prefix(text, old + "\\stage", "%NEOVIDE_GLOW_ROOT%")
                write(file, text)
            if has_prefix(text, [*roots, *worker_roots]) or re.search(r"(?i)(?<![A-Za-z0-9_])[A-Z]:[\\/]", text):
                raise RelocationError("Unresolved worker path in executable configuration: " + str(file))
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")

    if not records:
        raise RelocationError("No installed Mason commands were found")
    # A package wrapper must not reference another package at an old location.
    for file in mason.rglob("*"):
        if file.is_file() and file.suffix.lower() in (".cmd", ".bat", ".ps1", ".pth"):
            text = read(file)
            if has_prefix(text, all_roots) or re.search(r"(?i)(?<![A-Za-z0-9_])[A-Z]:[\\/]", text):
                raise RelocationError("Unresolved absolute path in executable configuration: " + str(file))
    result = {"schema_version": 1, "commands": records, "python_launcher": "runtime/mason_tool.py"}
    (stage / "runtime/mason-relocation.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = relocate(args.stage)
    except (OSError, ValueError, RelocationError) as error:
        parser.exit(1, "Mason relocation failed: " + str(error) + "\n")
    print(f"Relocated {len(result['commands'])} Mason commands with pinned private dependencies")


if __name__ == "__main__":
    main()
