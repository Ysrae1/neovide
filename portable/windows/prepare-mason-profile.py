#!/usr/bin/env python3
"""Prepare an independent Windows Mason profile from a verified frozen profile.

Language tools run as child processes. A private x64 Python remains valid on
Windows 11 ARM64; Node and Java may use same-version ARM64 runtimes. No files
from this tree become Neovim in-process modules.
The destination must be absent, and the source profile is never modified.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
from urllib.parse import unquote


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def relative_file(directory, value):
    value = value.replace("\\", "/")
    if not value or value.startswith("/") or ":" in value or any(p in ("", ".", "..") for p in value.split("/")):
        raise ValueError("Unsafe package-relative link: " + value)
    path = directory / value
    if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(directory.resolve()):
        raise ValueError("Missing or escaping package link: " + str(path))
    return path


def extended(path):
    path = str(path.resolve())
    if os.name == "nt" and not path.startswith("\\\\?\\"):
        path = "\\\\?\\UNC\\" + path[2:] if path.startswith("\\\\") else "\\\\?\\" + path
    return Path(path)


def prepare(source, destination, runtime, manifest, native, dispatcher, runtime_node=None, runtime_java=None):
    # Frozen npm dependencies can exceed MAX_PATH; use extended paths locally
    # rather than changing the user's Windows policy or package contents.
    source, destination, runtime = extended(source), extended(destination), extended(runtime)
    if destination.exists() or destination.is_relative_to(source) or source.is_relative_to(destination):
        raise ValueError("Destination must be absent and separate from the source")
    expected = {p["name"]: p for p in read_json(manifest)["packages"]}
    receipts = {}
    for receipt_path in (source / "packages").glob("*/mason-receipt.json"):
        receipt = read_json(receipt_path)
        name = receipt_path.parent.name
        if name not in expected or receipt.get("primary_source", {}).get("id") != expected[name]["source"]:
            raise ValueError("Package does not match the frozen manifest: " + name)
        for value in receipt.get("links", {}).get("bin", {}).values():
            relative_file(receipt_path.parent, value)
        receipts[name] = receipt
    if not receipts or any(name not in receipts for name in expected if "platforms" not in expected[name]):
        raise ValueError("Frozen Mason packages are incomplete")
    runtime_sources = {"python": runtime / "python", "node": runtime_node or runtime / "node", "java": runtime_java or runtime / "java"}
    for path in (runtime_sources["python"] / "python.exe", runtime_sources["node"] / "node.exe", runtime_sources["java"] / "bin/java.exe", dispatcher):
        if not path.is_file():
            raise ValueError("Required private runtime is missing: " + str(path))
    replacements = read_json(native) if native else []
    for item in replacements:
        exe = native.parent / item["executable"]
        if item["package"] not in receipts or sha(exe) != item["executable_sha256"]:
            raise ValueError("Native replacement hash or package mismatch")
    # Refuse to copy junctions/symlinks that could escape into another profile.
    if any(path.is_symlink() for path in source.rglob("*")):
        raise ValueError("Source Mason tree contains symlinks")
    shutil.copytree(source, destination)
    private = destination / ".glow-runtime/runtime"
    for name in ("python", "node", "java"):
        shutil.copytree(runtime_sources[name], private / name)
    shutil.copy2(dispatcher, private / "mason_tool.py")
    for item in replacements:
        package = destination / "packages" / item["package"]
        links = receipts[item["package"]]["links"]["bin"]
        if item["package"] == "ruff":
            target = relative_file(package, links["ruff.cmd"])
        else:
            target = relative_file(package, links[item["package"] + ".cmd"])
        shutil.copy2(native.parent / item["executable"], target)
    wrappers = []
    for wrapper in destination.rglob("*.cmd"):
        text = wrapper.read_text(encoding="utf-8-sig")
        # All generated wrappers remain relative if this profile is moved.
        root = os.path.relpath(destination / ".glow-runtime", wrapper.parent).replace("/", "\\")
        if any(c in root for c in '"%\r\n'):
            raise ValueError("Unsafe private runtime path")
        prefix = ('@echo off\nsetlocal DisableDelayedExpansion\n'
                  'set "NEOVIDE_GLOW_ROOT=%~dp0' + root + '"\n'
                  'set "JAVA_HOME=%NEOVIDE_GLOW_ROOT%\\runtime\\java"\n')
        # Only public and Python package-local launchers need the private root.
        public_runtime = wrapper.parent == destination / "bin" and any(
            wrapper.name in receipt.get("links", {}).get("bin", {}) and
            (name == "ltex-ls" or receipt.get("primary_source", {}).get("id", "").startswith("pkg:npm/"))
            for name, receipt in receipts.items())
        if public_runtime or "NEOVIDE_GLOW_ROOT" in text:
            text = re.sub(r"(?im)^@?echo off\s*\n", "", text, count=1)
            if wrapper.parent == destination / "bin":
                for name, package_receipt in receipts.items():
                    links = package_receipt.get("links", {}).get("bin", {})
                    source_id = package_receipt.get("primary_source", {}).get("id", "")
                    if wrapper.name in links and source_id.startswith("pkg:npm/"):
                        npm_name = unquote(source_id[len("pkg:npm/"):].rsplit("@", 1)[0])
                        npm_root = destination / "packages" / name / "node_modules" / npm_name
                        bins = read_json(npm_root / "package.json")["bin"]
                        command = wrapper.stem
                        entry = bins if isinstance(bins, str) else bins[command]
                        script = relative_file(npm_root, entry.removeprefix("./"))
                        relative = os.path.relpath(script, wrapper.parent).replace("/", "\\")
                        text = ('"%NEOVIDE_GLOW_ROOT%\\runtime\\node\\node.exe" "%~dp0' + relative + '" %*\n'
                                'exit /b %errorlevel%\n')
                        break
            wrapper.write_bytes((prefix + text).replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
            wrappers.append(str(wrapper.relative_to(destination)))
    receipt = {"schema_version": 1, "state": "prepared", "source": str(source),
               "destination": str(destination), "packages": sorted(receipts),
               "frozen_manifest_sha256": sha(manifest), "native_replacements": replacements,
               "wrappers": sorted(wrappers), "runtime_execution": "private child processes",
               "runtime_sha256": {n: sha(private / p) for n, p in
                   {"python": "python/python.exe", "node": "node/node.exe", "java": "java/bin/java.exe"}.items()}}
    (destination / "glow-profile-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "destination", "runtime", "manifest", "dispatcher"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--native", type=Path)
    parser.add_argument("--runtime-node", type=Path)
    parser.add_argument("--runtime-java", type=Path)
    args = parser.parse_args()
    try:
        result = prepare(args.source, args.destination, args.runtime, args.manifest, args.native, args.dispatcher, args.runtime_node, args.runtime_java)
    except (OSError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
