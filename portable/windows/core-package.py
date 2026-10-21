#!/usr/bin/env python3
"""Derive a fresh core stage from a checksum-sealed offline build, without mutating it.

Only release workers run this. Python/Node/Java, Mason language packages and
bundled CLI tools are intentionally absent; system dependency setup is separate.
"""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def safe_relative(value):
    if not isinstance(value, str) or not value:
        raise ValueError("Unsafe sealed payload path")
    path = PurePosixPath(value)
    if "\\" in value or ":" in value or path.is_absolute() or ".." in path.parts or str(path) != value:
        raise ValueError("Unsafe sealed payload path")
    return path


def retained(relative):
    path = safe_relative(relative)
    if path.parts[0] in {"fonts", "licenses", "share", "lib", "config"}:
        return True
    if path.parts[:2] == ("profile", "config"):
        return True
    if path.parts[:4] == ("profile", "data", "nvim", "lazy"):
        # Keep fixed plugins, their prebuilt native modules and parsers.
        return True
    if path.parts[0] == "bin":
        return path.name in {"neovide.exe", "nvim.exe", "cmatrix-gm.exe"} or path.suffix.lower() == ".dll"
    return relative in {"neovide.ico", "LICENSE"}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def package_dependency_notices(destination):
    # Reuse the reviewed, offline notice generator; the dependency stage may
    # predate the explicitly supplied frontend and its Rust dependencies.
    root = HERE.parents[1]
    subprocess.run([sys.executable, "-I", "-B", "-X", "utf8", str(root / "scripts/generate-third-party-notices.py"),
                    "--output", str(destination / "licenses/THIRD-PARTY-NOTICES.txt")], check=True)
    shutil.copy2(root / "licenses/third-party/manifest.json", destination / "licenses/THIRD-PARTY-NOTICES.json")


def size_breakdown(root, files):
    components, plugins, largest = {}, {}, []
    for relative in files:
        path = root / relative
        size = path.stat().st_size
        parts = PurePosixPath(relative).parts
        component = "/".join(parts[:4]) if parts[:3] == ("profile", "data", "nvim") else parts[0]
        bucket = components.setdefault(component, {"bytes": 0, "files": 0})
        bucket["bytes"] += size
        bucket["files"] += 1
        if parts[:4] == ("profile", "data", "nvim", "lazy") and len(parts) > 4:
            bucket = plugins.setdefault(parts[4], {"bytes": 0, "files": 0, "native_bytes": 0, "download_cache_bytes": 0})
            bucket["bytes"] += size
            bucket["files"] += 1
            if path.suffix.lower() in {".exe", ".dll", ".so"}:
                bucket["native_bytes"] += size
            if any(part.casefold() in {"download", "downloads", ".cache", "cache"} for part in parts[5:-1]):
                bucket["download_cache_bytes"] += size
        largest.append({"path": relative, "bytes": size})
    return {"components": components, "plugins": dict(sorted(plugins.items(), key=lambda item: -item[1]["bytes"])),
            "largest_files": sorted(largest, key=lambda item: -item["bytes"])[:20]}


def frontend_provenance(frontend, checksum, source_commit, source_state, source_fingerprint):
    if not checksum or not re.fullmatch(r"[0-9a-fA-F]{64}", checksum):
        raise ValueError("An explicit frontend requires its expected SHA256")
    if source_commit and not re.fullmatch(r"[0-9a-fA-F]{40}", source_commit):
        raise ValueError("Invalid frontend source base commit")
    if source_fingerprint and not re.fullmatch(r"[0-9a-fA-F]{64}", source_fingerprint):
        raise ValueError("Invalid frontend source fingerprint")
    source_state = source_state or "unknown"
    if source_state not in {"clean", "dirty", "unknown"} or (source_state == "clean" and not source_commit):
        raise ValueError("Clean frontend provenance requires a source commit")
    if not frontend.is_file() or digest(frontend) != checksum.lower():
        raise ValueError("Explicit frontend SHA256 differs from the expected build artifact")
    with frontend.open("rb") as stream:
        header = stream.read(64)
        if len(header) < 64 or header[:2] != b"MZ":
            raise ValueError("The frontend override is not a Windows PE executable")
        offset = struct.unpack_from("<I", header, 0x3C)[0]
        stream.seek(offset)
        pe = stream.read(26)
    if len(pe) != 26 or pe[:4] != b"PE\0\0" or struct.unpack_from("<H", pe, 4)[0] != 0x8664 or struct.unpack_from("<H", pe, 24)[0] != 0x20B:
        raise ValueError("The frontend override must be a Windows x64 PE32+ executable")
    record = {"origin": "explicit_build_artifact", "sha256": checksum.lower(), "bytes": frontend.stat().st_size,
              "architecture": "x86_64", "source_state": source_state}
    if source_commit:
        record["source_base_commit"] = source_commit.lower()
    if source_fingerprint:
        record["source_fingerprint_sha256"] = source_fingerprint.lower()
    return record


def build(source, destination, launcher, stack_id, frontend=None, frontend_sha256=None,
          frontend_source_commit=None, frontend_source_state=None, frontend_source_fingerprint=None):
    source, destination, launcher = source.resolve(), destination.resolve(), launcher.resolve()
    if destination.exists():
        raise ValueError("Core destination must be fresh; existing files were preserved")
    if source == destination or source in destination.parents:
        raise ValueError("Core output must be outside the sealed source stage")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,100}", stack_id):
        raise ValueError("Invalid core stack identifier")
    metadata = json.loads((source / "bundle.json").read_text(encoding="utf-8"))
    source_stack = metadata.get("stack_id")
    checksums = json.loads((source / "bundle-sha256.json").read_text(encoding="utf-8"))
    if metadata.get("schema_version") != 1 or metadata.get("distribution") == "core" or not checksums:
        raise ValueError("Input must be a sealed offline bundle")
    if metadata.get("stack_id") == stack_id:
        raise ValueError("Core must use a new stack identifier to preserve existing profiles")
    if not launcher.is_file():
        raise ValueError("Compile the current core-aware launcher before packaging")
    override = None
    if frontend is not None:
        frontend = frontend.resolve()
        override = frontend_provenance(frontend, frontend_sha256, frontend_source_commit,
                                       frontend_source_state, frontend_source_fingerprint)
    elif any((frontend_sha256, frontend_source_commit, frontend_source_state, frontend_source_fingerprint)):
        raise ValueError("Frontend provenance options require an explicit frontend artifact")
    selected = []
    for relative, checksum in checksums.items():
        safe_relative(relative)
        if not retained(relative):
            continue
        original = source / relative
        if any(parent.is_symlink() for parent in [original, *original.parents] if parent != source.parent):
            raise ValueError("Links are not permitted in the sealed source")
        if not original.is_file() or digest(original) != checksum:
            raise ValueError("Sealed source checksum differs: " + relative)
        selected.append(relative)
    essentials = {"bin/neovide.exe", "bin/nvim.exe", "bin/cmatrix-gm.exe", "share/nvim/runtime/filetype.lua",
                  "profile/config/nvim/init.lua", "profile/config/nvim/lazy-lock.json", "config/neovide.toml"}
    selected_set = set(selected)
    if not essentials.issubset(selected_set):
        raise ValueError("Sealed input lacks core editor components")
    required = [path for path in metadata.get("native_required", []) if retained(path)]
    if not any(path.startswith("profile/data/nvim/lazy/") for path in required):
        raise ValueError("Sealed input must declare precompiled plugin components")
    payload = HERE.parent / "payload"
    # Refresh current config without changing the frozen plugin/native ABI set.
    if digest(payload / "nvim/lazy-lock.json") != checksums["profile/config/nvim/lazy-lock.json"]:
        raise ValueError("Current configuration has a different plugin lock; rebuild native dependencies first")
    for name in ("nvim", "yazi"):
        for path in (payload / name).rglob("*"):
            if path.is_symlink() or path.name.casefold() in {"auth.json", "credentials.json", ".credentials.json", ".env", ".codex", ".git"}:
                raise ValueError("Private/link content is not permitted in current configuration")
    destination.mkdir(parents=True)
    for relative in selected:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, target)
    if override:
        shutil.copy2(frontend, destination / "bin/neovide.exe")
        if digest(destination / "bin/neovide.exe") != override["sha256"]:
            raise ValueError("The frontend artifact changed while being packaged")
        # An explicit dirty/local build must not inherit an unrelated frozen
        # source claim from the dependency stage.
        if "neovide_commit" in metadata:
            metadata["dependency_stage_neovide_commit"] = metadata.pop("neovide_commit")
        metadata["frontend_provenance"] = override
    else:
        metadata["frontend_provenance"] = {"origin": "sealed_dependency_stage", "sha256": checksums["bin/neovide.exe"]}
    # Frozen offline stages used the system title bar. New core installs use
    # the same frameless default as the verified Windows desktop entry.
    neovide_config = destination / "config/neovide.toml"
    config_lines = neovide_config.read_text(encoding="utf-8").splitlines(keepends=True)
    frame_found = False
    for index, line in enumerate(config_lines):
        if line.lstrip().startswith("["):
            break
        if re.match(r"[ \t]*frame[ \t]*=", line):
            config_lines[index] = 'frame = "none"\n'
            frame_found = True
            break
    if not frame_found:
        config_lines.insert(0, 'frame = "none"\n')
    neovide_config.write_text("".join(config_lines), encoding="utf-8")
    for name in ("nvim", "yazi"):
        target = destination / "profile/config" / name
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(payload / name, target, ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc"))
    init = destination / "profile/config/nvim/init.lua"
    guard = 'if vim.env.NEOVIDE_GLOW_INIT then dofile(vim.env.NEOVIDE_GLOW_INIT) end\n'
    if not init.read_text(encoding="utf-8").startswith(guard):
        init.write_text(guard + init.read_text(encoding="utf-8"), encoding="utf-8")
    shutil.copy2(launcher, destination / "Glow.exe")
    runtime = destination / "runtime/lua"
    runtime.mkdir(parents=True)
    shutil.copy2(HERE / "runtime/WindowsInit.lua", runtime / "WindowsInit.lua")
    dependencies = destination / "dependencies"
    dependencies.mkdir()
    for name in ("Setup-Dependencies.ps1", "dependencies.json", "WebView2.ps1", "Dependency-Helpers.ps1", "system-assets.lock.json", "Setup-LaTeX.ps1"):
        shutil.copy2(HERE / name, dependencies / name)
    shutil.copytree(HERE / "tex", dependencies / "tex")
    shutil.copy2(payload / "nvim/lua/config/media/runtime/requirements.txt", dependencies / "notebook-requirements.txt")
    shutil.copy2(payload / "requirements-latex.lock", dependencies / "latex-requirements.lock")
    package_dependency_notices(destination)
    metadata.update({"stack_id": stack_id, "distribution": "core", "native_required": sorted(required), "tool_paths": []})
    write_json(destination / "bundle.json", metadata)
    source_bytes = sum((source / path).stat().st_size for path in checksums) + (source / "bundle-sha256.json").stat().st_size
    for path in destination.rglob("*"):
        if path.is_symlink() or path.name.casefold() in {"auth.json", "credentials.json", ".credentials.json", ".env", ".codex", ".git"}:
            raise ValueError("Private/link content is not permitted in the core package")
    output = {path.relative_to(destination).as_posix(): digest(path) for path in sorted(destination.rglob("*")) if path.is_file()}
    write_json(destination / "bundle-sha256.json", output)
    final_files = [*output, "bundle-sha256.json"]
    core_bytes = sum((destination / relative).stat().st_size for relative in final_files)
    return {"distribution": "core", "source_bytes": source_bytes, "core_bytes": core_bytes,
            "core_files": len(final_files), "omitted_input_files": len(checksums) - len(selected),
            "source_stack": source_stack, "stack_id": stack_id,
            "frontend": metadata["frontend_provenance"],
            "retained": size_breakdown(destination, final_files),
            "omitted": size_breakdown(source, [path for path in checksums if path not in selected_set])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--launcher", required=True, type=Path)
    parser.add_argument("--stack-id", required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--frontend", type=Path)
    parser.add_argument("--frontend-sha256")
    parser.add_argument("--frontend-source-commit")
    parser.add_argument("--frontend-source-state", choices=("clean", "dirty", "unknown"))
    parser.add_argument("--frontend-source-fingerprint")
    args = parser.parse_args()
    report = build(args.source, args.destination, args.launcher, args.stack_id, args.frontend,
                   args.frontend_sha256, args.frontend_source_commit, args.frontend_source_state,
                   args.frontend_source_fingerprint)
    if args.report:
        write_json(args.report, report)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
