#!/usr/bin/env python3
"""Prepare an explicitly overlaid, sealed native core source without running it.

This is a maintainer input to core-package.py, not a complete offline installer.
All target native files must be individually supplied and hash-pinned.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PureWindowsPath
import re
import shutil
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
PE_SUFFIXES = {".exe", ".dll", ".so", ".node", ".pyd"}
PRIVATE_NAMES = {"auth.json", "credentials.json", ".credentials.json", ".env", ".codex", ".git"}


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


core = load_module("glow_stage_core", "core-package.py")
native = load_module("glow_stage_native", "verify-native.py")


class PreparationError(ValueError):
    def __init__(self, message, report):
        super().__init__(message)
        self.report = report


def no_links(path):
    for part in (path, *path.parents):
        if part.is_symlink() or (hasattr(part, "is_junction") and part.is_junction()):
            raise ValueError("Links are not permitted: " + str(path))


def relative(value):
    path = core.safe_relative(value)
    if value == "." or "\0" in value:
        raise ValueError("Unsafe payload path")
    if any(part.casefold() in PRIVATE_NAMES or part.casefold().startswith(".env.") for part in path.parts):
        raise ValueError("Private content is not permitted: " + value)
    return path.as_posix()


def checksum(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value):
        raise ValueError("An explicit SHA256 is required")
    return value.lower()


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Repeated JSON key: " + key)
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def prepare(source, destination, inputs):
    report = {"schema_version": 1, "state": "failed", "source": str(source),
              "destination": str(destination), "error": None}
    try:
        source, destination = Path(source).absolute(), Path(destination).absolute()
        no_links(source)
        no_links(destination)
        source, destination = source.resolve(), destination.resolve()
        if destination.exists():
            raise ValueError("Use a fresh destination; existing files were preserved")
        if destination == source or destination.is_relative_to(source) or source.is_relative_to(destination):
            raise ValueError("Destination must be outside the sealed source")
        no_links(source / "bundle-sha256.json")
        seal_digest = core.digest(source / "bundle-sha256.json")
        if not isinstance(inputs, dict) or inputs.get("schema_version") != 1:
            raise ValueError("Inputs must use schema_version 1")
        if checksum(inputs.get("base_seal_sha256")) != seal_digest:
            raise ValueError("The base seal SHA256 differs from the explicit inputs")
        sealed = read_json(source / "bundle-sha256.json")
        if not isinstance(sealed, dict) or not sealed:
            raise ValueError("The source seal must be a nonempty file map")
        seen, base = set(), {}
        for name, expected in sealed.items():
            name = relative(name)
            if name.casefold() in seen:
                raise ValueError("Case-colliding sealed paths are not permitted")
            seen.add(name.casefold())
            expected = checksum(expected)
            if name == "bundle.json" or core.retained(name):
                original = source / name
                no_links(original)
                if not original.is_file() or core.digest(original) != expected:
                    raise ValueError("Sealed source checksum differs: " + name)
                base[name] = expected
        if "bundle.json" not in base:
            raise ValueError("The source bundle.json must be covered by its seal")
        metadata = read_json(source / "bundle.json")
        if metadata.get("schema_version") != 1 or metadata.get("distribution") == "core":
            raise ValueError("The base must be a sealed pre-core source stage")
        architecture, stack = inputs.get("architecture"), inputs.get("stack_id")
        if architecture not in native.MACHINES:
            raise ValueError("Architecture must be x64 or arm64")
        if not isinstance(stack, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,100}", stack):
            raise ValueError("Invalid native stage stack_id")
        if stack == metadata.get("stack_id"):
            raise ValueError("Native preparation requires an independent stack_id")
        if bool(re.search(r"(?:^|[-_.])arm64(?:$|[-_.])", stack, re.I)) != (architecture == "arm64"):
            raise ValueError("ARM64 stack_id must contain an independent arm64 segment; x64 must not reuse it")
        prefixes = inputs.get("replace_prefixes")
        if not isinstance(prefixes, list):
            raise ValueError("replace_prefixes must be an explicit array")
        normalized_prefixes = []
        for prefix in prefixes:
            if not isinstance(prefix, str) or not prefix.endswith("/"):
                raise ValueError("Replacement prefixes must end in /")
            prefix = relative(prefix[:-1]) + "/"
            if not core.retained(prefix + "__prefix_validation__.dll") or prefix.casefold() in {p.casefold() for p in normalized_prefixes}:
                raise ValueError("Invalid or repeated replacement prefix")
            normalized_prefixes.append(prefix)
        def replaced(name):
            return any(name.casefold().startswith(p.casefold()) for p in normalized_prefixes)
        # Copilot is a separate Node process and ships assets for several OSes.
        # Preserve only explicitly hash-bound assets from that sealed package;
        # this does not establish the external Node process's runtime/ABI health.
        external_entries = inputs.get("sealed_external_files", [])
        if not isinstance(external_entries, list):
            raise ValueError("sealed_external_files must be an explicit array")
        external, external_seen = {}, set()
        copilot = "profile/data/nvim/lazy/copilot.lua/copilot/js/"
        for entry in external_entries:
            if not isinstance(entry, dict):
                raise ValueError("Invalid sealed external file entry")
            name = relative(entry.get("path"))
            allowed = name.startswith(copilot) and (name.endswith(".node") or
                re.fullmatch(re.escape(copilot) + r"bin/win32/[^/]+/rg\.exe", name))
            if not allowed or name.casefold() in external_seen:
                raise ValueError("Sealed external exceptions are limited to unique Copilot Node/helper assets")
            expected = checksum(entry.get("sha256"))
            if base.get(name) != expected or replaced(name):
                raise ValueError("Sealed external file must match the retained base seal: " + name)
            external_seen.add(name.casefold())
            external[name] = expected
        files = inputs.get("files")
        if not isinstance(files, list) or not files:
            raise ValueError("Inputs must explicitly list native overlay files")
        overlays, overlay_seen = {}, set()
        for entry in files:
            if not isinstance(entry, dict):
                raise ValueError("Invalid native overlay entry")
            name = relative(entry.get("path"))
            if not core.retained(name) or name.casefold() in overlay_seen or name.casefold() in external_seen:
                raise ValueError("Overlay paths must be retained and unique")
            overlay_seen.add(name.casefold())
            original = Path(entry.get("source", ""))
            if not original.is_absolute():
                raise ValueError("Overlay sources must be absolute files")
            no_links(original)
            expected = checksum(entry.get("sha256"))
            if not original.is_file() or core.digest(original) != expected:
                raise ValueError("Overlay SHA256 differs: " + name)
            kind = entry.get("source_kind")
            if (not isinstance(kind, str) or not kind.strip() or len(kind) > 160 or
                    Path(kind).is_absolute() or PureWindowsPath(kind).is_absolute() or
                    re.search(r"[\x00-\x1f]|(?:^|\s)(?:[A-Za-z]:[\\/]|\\\\|/)", kind)):
                raise ValueError("source_kind must be a short origin label without absolute paths")
            if Path(name).suffix.lower() in PE_SUFFIXES:
                image = native.PE(original.read_bytes())
                if image.machine != native.MACHINES[architecture]:
                    raise ValueError("Overlay PE architecture differs: " + name)
            overlays[name] = {"source": original, "sha256": expected, "source_kind": kind}
        retained = {name: digest for name, digest in base.items()
                    if name != "bundle.json" and not replaced(name)}
        for name in retained:
            if Path(name).suffix.lower() in PE_SUFFIXES and name.casefold() not in overlay_seen and name not in external:
                raise ValueError("Explicit native replacement required; old PE would remain: " + name)
            if name.casefold() in overlay_seen and name not in overlays:
                raise ValueError("Overlay spelling differs from the sealed Windows path: " + name)
        final_names = set(retained) | set(overlays)
        essentials = {"bin/neovide.exe", "bin/nvim.exe", "bin/cmatrix-gm.exe", "share/nvim/runtime/filetype.lua",
                      "config/neovide.toml", "profile/config/nvim/init.lua", "profile/config/nvim/lazy-lock.json"}
        if not essentials.issubset(final_names):
            raise ValueError("Native stage lacks core components: " + ", ".join(sorted(essentials - final_names)))
        required = set()
        for name in metadata.get("native_required", []):
            name = relative(name)
            if core.retained(name) and name in final_names and name not in external:
                required.add(name)
        required.update(name for name in final_names if name not in external and
                        Path(name).suffix.lower() in {".dll", ".so", ".node", ".pyd"})
        required.update({"bin/neovide.exe", "bin/nvim.exe", "bin/cmatrix-gm.exe"})
        public_overlays = [{"path": name, "sha256": item["sha256"], "source_kind": item["source_kind"]}
                           for name, item in sorted(overlays.items())]
        prepared = {"schema_version": 1, "stack_id": stack, "architecture": architecture,
                    "distribution": "offline", "preparation": "verified-native-core-source",
                    "native_required": sorted(required), "tool_paths": [],
                    "sealed_external_files": [{"path": name, "sha256": digest} for name, digest in sorted(external.items())],
                    "external_runtime_assets_acceptance": "Separate Copilot Node resources; not native editor ABI or external runtime execution acceptance",
                    "native_preparation": {"base_seal_sha256": seal_digest,
                                           "base_bundle_sha256": base["bundle.json"],
                                           "replace_prefixes": normalized_prefixes, "files": public_overlays}}
        report.update({"architecture": architecture, "stack_id": stack, "base_seal_sha256": seal_digest,
                       "retained_file_count": len(retained), "overlay_file_count": len(overlays),
                       "sealed_external_files": prepared["sealed_external_files"],
                       "external_runtime_assets_acceptance": prepared["external_runtime_assets_acceptance"],
                       "overlays": [{**item, "source": str(overlays[item["path"]]["source"])} for item in public_overlays]})
        destination.mkdir(parents=True)
        for name in sorted(final_names):
            item = overlays.get(name)
            original = item["source"] if item else source / name
            expected = item["sha256"] if item else retained[name]
            no_links(original)
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, target)
            if core.digest(target) != expected:
                raise ValueError("Input changed during native stage copy: " + name)
        write_json(destination / "bundle.json", prepared)
        verification = native.verify_stage(destination, architecture)
        report["native_verification"] = verification
        if verification["status"] != "passed":
            raise ValueError("Native stage gate failed: " + "; ".join(verification["errors"]))
        output = {path.relative_to(destination).as_posix(): core.digest(path)
                  for path in sorted(destination.rglob("*")) if path.is_file()}
        write_json(destination / "bundle-sha256.json", output)
        report.update({"state": "sealed_native_core_source", "sealed_file_count": len(output),
                       "seal_sha256": core.digest(destination / "bundle-sha256.json"),
                       "native_execution": "not_performed", "complete_offline_installer": False})
        return report
    except (ValueError, OSError, TypeError, AttributeError) as error:
        report["error"] = str(error)
        raise PreparationError(str(error), report) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("source", "destination", "inputs", "report"):
        parser.add_argument("--" + option, type=Path, required=True)
    arguments = parser.parse_args()
    try:
        no_links(arguments.inputs.absolute())
        report_path = arguments.report.absolute()
        no_links(report_path)
        if report_path.exists() or any(report_path.resolve().is_relative_to(p.resolve())
                                       for p in (arguments.source, arguments.destination)):
            raise ValueError("Use a fresh report outside both source and destination")
        report = prepare(arguments.source, arguments.destination, read_json(arguments.inputs))
        code = 0
    except PreparationError as error:
        report, code = error.report, 1
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 1
    report_path.parent.mkdir(parents=True, exist_ok=True)
    write_json(report_path, report)
    print(json.dumps(report, ensure_ascii=False))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
