#!/usr/bin/env python3
"""Check a complete Windows stage's PE architecture and app-local MSVC runtime.

Read-only, standard-library release gate; this does not run Windows programs or
prove runtime/GUI compatibility. PE import layouts follow Microsoft's PE format:
https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path, PurePosixPath


MACHINES = {"x64": 0x8664, "arm64": 0xAA64}
ARCHITECTURES = {value: key for key, value in MACHINES.items()}
# UCRT/API-set DLLs are supplied by supported Windows versions. The separately
# redistributable MSVC libraries must accompany the frontend when imported.
MSVC_CRT = re.compile(r"(?:msvcp|msvcr|vcruntime|concrt|vccorlib)\d+[a-z0-9_]*\.dll\Z", re.I)


def safe_path(stage, relative):
    if not isinstance(relative, str) or not relative:
        raise ValueError("Invalid native payload path")
    path = PurePosixPath(relative)
    if ("\\" in relative or ":" in relative or "\0" in relative or path.is_absolute()
            or ".." in path.parts or str(path) != relative or relative == "."):
        raise ValueError("Unsafe native payload path: " + repr(relative))
    candidate = stage.joinpath(*path.parts)
    for part in (candidate, *candidate.parents):
        if part == stage:
            break
        if part.is_symlink():
            raise ValueError("Links are not permitted in native payload paths: " + relative)
    if not candidate.is_file():
        raise ValueError("Missing native payload file: " + relative)
    if not candidate.resolve().is_relative_to(stage):
        raise ValueError("Native payload path escapes the stage: " + relative)
    return candidate


class PE:
    """The small, bounds-checked subset of PE needed for DLL names and machine."""

    def __init__(self, data):
        self.data = data
        if len(data) < 64 or data[:2] != b"MZ":
            raise ValueError("Not a Windows PE image (missing MZ header)")
        pe = self.unpack("<I", 0x3C)[0]
        if pe < 64 or self.take(pe, 4) != b"PE\0\0":
            raise ValueError("Invalid PE signature")
        self.machine, count = self.unpack("<HH", pe + 4)
        optional_size = self.unpack("<H", pe + 20)[0]
        optional = pe + 24
        self.take(optional, optional_size)
        if optional_size < 112 or self.unpack("<H", optional)[0] != 0x20B:
            raise ValueError("Expected a PE32+ Windows image")
        self.image_base = self.unpack("<Q", optional + 24)[0]
        self.headers = self.unpack("<I", optional + 60)[0]
        directories = self.unpack("<I", optional + 108)[0]
        if directories > (optional_size - 112) // 8:
            raise ValueError("PE data directories exceed the optional header")
        if not 1 <= count <= 96 or self.headers > len(data):
            raise ValueError("Invalid PE section/header size")
        self.directories = [self.unpack("<II", optional + 112 + 8 * i)
                            for i in range(min(directories, 16))]
        self.sections = []
        for index in range(count):
            section = optional + optional_size + index * 40
            self.take(section, 40)
            _, address, size, pointer = self.unpack("<IIII", section + 8)
            self.take(pointer, size)
            self.sections.append((address, size, pointer))
        self.imports = self.import_names(1, 20, False)
        self.delay_imports = self.import_names(13, 32, True)

    def take(self, offset, size):
        if offset < 0 or size < 0 or offset > len(self.data) - size:
            raise ValueError("Truncated or out-of-bounds PE data")
        return self.data[offset:offset + size]

    def unpack(self, layout, offset):
        return struct.unpack(layout, self.take(offset, struct.calcsize(layout)))

    def mapped(self, rva, size=1):
        matches = []
        if 0 <= rva < self.headers and size <= self.headers - rva:
            matches.append((rva, self.headers - rva))
        for address, raw_size, pointer in self.sections:
            if address <= rva < address + raw_size and size <= address + raw_size - rva:
                matches.append((pointer + rva - address, address + raw_size - rva))
        if len(matches) != 1:
            raise ValueError("PE RVA is unmapped or ambiguous")
        offset, available = matches[0]
        self.take(offset, size)
        return offset, available

    def dll_name(self, rva):
        offset, available = self.mapped(rva)
        raw = self.take(offset, min(available, 512))
        end = raw.find(b"\0")
        if end < 1:
            raise ValueError("Invalid or unterminated PE import name")
        try:
            name = raw[:end].decode("ascii")
        except UnicodeDecodeError as error:
            raise ValueError("Non-ASCII PE import name") from error
        if name in {".", ".."} or any(c in name for c in "/\\:") or any(ord(c) < 32 for c in name):
            raise ValueError("Unsafe PE import name: " + repr(name))
        return name

    def import_names(self, directory_index, stride, delayed):
        if directory_index >= len(self.directories):
            return []
        rva, size = self.directories[directory_index]
        if not rva and not size:
            return []
        if not rva or size < stride or size // stride > 65536:
            raise ValueError("Invalid PE import directory size")
        names = []
        for delta in range(0, size - stride + 1, stride):
            offset, _ = self.mapped(rva + delta, stride)
            descriptor = self.take(offset, stride)
            if not any(descriptor):
                return sorted(set(names), key=str.casefold)
            values = struct.unpack("<" + "I" * (stride // 4), descriptor)
            if delayed:
                attributes, name = values[:2]
                if attributes & ~1:
                    raise ValueError("Unsupported delay-import attributes")
                if not attributes & 1:
                    name -= self.image_base
            else:
                name = values[3]
            names.append(self.dll_name(name))
        raise ValueError("PE import directory has no terminating descriptor")


def verify_stage(stage, architecture):
    """Return a JSON-serializable report; a failed check never mutates the stage."""
    if architecture not in MACHINES:
        raise ValueError("Architecture must be x64 or arm64")
    stage = Path(stage).resolve()
    report = {"schema_version": 1, "stage": str(stage), "architecture": architecture,
              "expected_machine": f"0x{MACHINES[architecture]:04x}", "status": "failed",
              "files": [], "crt_dependencies": [], "errors": []}
    errors, records, images = report["errors"], {}, {}
    try:
        metadata = json.loads(safe_path(stage, "bundle.json").read_text(encoding="utf-8"))
        required = metadata.get("native_required")
        if (not isinstance(required, list) or not required
                or not any(isinstance(p, str) and p.lower().endswith((".dll", ".so")) for p in required)):
            raise ValueError("bundle.json must declare native_required, including native DLLs/parsers")
        report["stack_id"] = metadata.get("stack_id")
    except (OSError, ValueError, AttributeError) as error:
        errors.append(str(error))
        required = []

    def inspect(relative):
        if isinstance(relative, str) and relative in records:
            return images.get(relative)
        try:
            path = safe_path(stage, relative)
            data = path.read_bytes()
            image = PE(data)
            records[relative] = {"path": relative, "bytes": len(data),
                                 "sha256": hashlib.sha256(data).hexdigest(),
                                 "machine": f"0x{image.machine:04x}",
                                 "architecture": ARCHITECTURES.get(image.machine, "unknown"),
                                 "imports": image.imports, "delay_imports": image.delay_imports}
            if image.machine != MACHINES[architecture]:
                errors.append(f"Wrong PE architecture: {relative}: 0x{image.machine:04x}; expected {architecture}")
            images[relative] = image
            return image
        except (OSError, ValueError) as error:
            errors.append(f"{relative!r}: {error}")
            return None

    for relative in ["bin/neovide.exe", "bin/nvim.exe"]:
        inspect(relative)
    for relative in required:
        try:
            path = safe_path(stage, relative)
        except (OSError, ValueError) as error:
            errors.append(f"{relative!r}: {error}")
            continue
        # Ancillary tool EXEs can have an explicitly supported emulation path;
        # their compatibility is separate from the native editor/module ABI.
        if path.suffix.lower() in {".dll", ".so"}:
            inspect(relative)

    # Resolve case-insensitively, as Windows does, but require the frontend's own
    # directory. PATH/System32 on a build machine must not hide an incomplete zip.
    visited = set()

    def close_crt(relative):
        if relative in visited:
            return
        visited.add(relative)
        image = images.get(relative)
        if image is None:
            return
        parent = (stage / relative).parent
        for kind, names in (("import", image.imports), ("delay_import", image.delay_imports)):
            for name in names:
                if not MSVC_CRT.fullmatch(name):
                    continue
                edge = {"from": relative, "name": name, "kind": kind}
                report["crt_dependencies"].append(edge)
                matches = [p for p in parent.iterdir() if p.name.casefold() == name.casefold()]
                if len(matches) != 1:
                    errors.append(f"Missing or ambiguous app-local MSVC CRT: {relative} -> {name}")
                    continue
                dependency = matches[0].relative_to(stage).as_posix()
                edge["path"] = dependency
                if inspect(dependency) is not None:
                    close_crt(dependency)

    close_crt("bin/neovide.exe")
    report["files"] = [records[key] for key in sorted(records)]
    report["status"] = "failed" if errors else "passed"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--architecture", choices=MACHINES, required=True)
    parser.add_argument("--report", type=Path)
    arguments = parser.parse_args()
    report = verify_stage(arguments.stage, arguments.architecture)
    content = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if arguments.report:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(content, encoding="utf-8")
    print(content, end="")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
