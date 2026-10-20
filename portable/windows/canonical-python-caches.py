#!/usr/bin/env python3
"""Build checked-hash caches with the pending bundle's Python 3.12.2.

Invoke the candidate's runtime/python/python.exe with -I -S -B. This worker
never reads an old cache or imports candidate source modules. Only explicit
py_compile output inside the candidate and the requested QA receipt are written.
"""

import sys

# Defensive even for an invalid invocation; the original -B flag is still
# required below. This changes this process only, never its parent's environment.
sys.dont_write_bytecode = True

import argparse
import hashlib
import importlib.util
import json
import ntpath
import os
import py_compile
import re
import stat


HEX256 = re.compile(r"[0-9a-fA-F]{64}\Z")
INVALID_COMPONENT = re.compile(r'[<>:"\\|?*\x00-\x1f]')
DEVICE_COMPONENT = re.compile(r"(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)", re.I)
REPARSE_POINT = 0x400


def require(condition, message):
    if not condition:
        raise ValueError(message)


def valid_component(component):
    return (
        component not in ("", ".", "..")
        and not INVALID_COMPONENT.search(component)
        and not component.endswith((".", " "))
        and not DEVICE_COMPONENT.match(component)
    )


def absolute_windows_path(value, label):
    """Return a logical absolute Windows path without an extended prefix."""
    value = os.fspath(value).replace("/", "\\")
    if value.startswith("\\\\?\\UNC\\"):
        value = "\\\\" + value[8:]
    elif value.startswith("\\\\?\\"):
        value = value[4:]
    require(not value.startswith("\\\\.\\"), label + " cannot be a device path")
    drive, tail = ntpath.splitdrive(value)
    require(bool(drive) and tail.startswith("\\"), label + " must be explicitly absolute")
    parts = tail[1:].split("\\") if tail != "\\" else []
    require(all(valid_component(part) for part in parts), label + " contains an unsafe component")
    return ntpath.normpath(value)


def extended(path):
    """Use explicit extended-length prefixes for every Windows file operation."""
    if path.startswith("\\\\"):
        return "\\\\?\\UNC\\" + path[2:]
    return "\\\\?\\" + path


def plain_stat(path, directory=None):
    observed = os.lstat(extended(path))
    require(
        not stat.S_ISLNK(observed.st_mode)
        and not (getattr(observed, "st_file_attributes", 0) & REPARSE_POINT),
        "Links and reparse points are forbidden: " + path,
    )
    if directory is True:
        require(stat.S_ISDIR(observed.st_mode), "Expected a directory: " + path)
    elif directory is False:
        require(stat.S_ISREG(observed.st_mode), "Expected a regular file: " + path)
    return observed


def validate_root(path):
    root = absolute_windows_path(path, "root")
    drive, tail = ntpath.splitdrive(root)
    require(drive.upper() == "C:", "Candidate root must be on the local C: drive")
    current = drive + "\\"
    plain_stat(current, directory=True)
    for part in tail[1:].split("\\") if tail != "\\" else []:
        current = ntpath.join(current, part)
        plain_stat(current, directory=True)
    return root


def relative_member(value, label):
    require(isinstance(value, str), label + " must be a string")
    require("\\" not in value and not value.startswith("/"), label + " must use relative forward slashes")
    parts = value.split("/")
    require(len(parts) >= 3 and parts[:2] == ["runtime", "python"], label + " must be under runtime/python")
    require(all(valid_component(part) for part in parts), label + " contains an unsafe component")
    return parts


def member_directory(root, parts, allow_missing_last=False, verified_directories=None):
    if verified_directories is None:
        verified_directories = set()
    current = root
    for index, part in enumerate(parts):
        current = ntpath.join(current, part)
        key = ntpath.normcase(current)
        if key in verified_directories:
            continue
        try:
            plain_stat(current, directory=True)
        except FileNotFoundError:
            if allow_missing_last and index == len(parts) - 1:
                return current, False
            raise
        verified_directories.add(key)
    return current, True


def source_path(root, parts, verified_directories=None):
    parent, unused = member_directory(root, parts[:-1], verified_directories=verified_directories)
    path = ntpath.join(parent, parts[-1])
    plain_stat(path, directory=False)
    return path


def require_missing(path):
    try:
        os.lstat(extended(path))
    except FileNotFoundError:
        return
    raise ValueError("Target cache already exists; it was neither read nor replaced: " + path)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key: " + key)
        result[key] = value
    return result


def cache_observation(path, expected_source_hash):
    digest = hashlib.sha256()
    count = 0
    with open(extended(path), "rb") as source:
        header = source.read(16)
        require(len(header) == 16, "Generated cache has a truncated header")
        require(header[:4] == importlib.util.MAGIC_NUMBER, "Generated cache has the wrong Python magic")
        require(int.from_bytes(header[4:8], "little") == 3, "Generated cache is not checked-hash (flags=3)")
        require(header[8:16] == expected_source_hash, "Generated cache header does not match the verified source")
        digest.update(header)
        count += len(header)
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
            count += len(block)
    return digest.hexdigest(), count


def run(args):
    receipt = {
        "schema": 1,
        "state": "running",
        "python_version": ".".join(str(part) for part in sys.version_info[:3]),
        "cache_tag": sys.implementation.cache_tag,
        "invalidation_mode": "checked_hash",
        "plan_sha256": None,
        "source_hashes_verified": False,
        "files": [],
        "generated_count": 0,
    }
    receipt_path = None
    owns_receipt = False
    current_file = None

    def save():
        # Only this exact, explicitly supplied QA path is written outside root.
        with open(extended(receipt_path), "w", encoding="utf-8", newline="\n") as output:
            json.dump(receipt, output, ensure_ascii=False, indent=2)
            output.write("\n")

    try:
        require(os.name == "nt" and sys.platform == "win32", "Native Windows is required")
        receipt_path = absolute_windows_path(args.receipt, "receipt")
        # Reserve fresh evidence before doing work; never overwrite an older run.
        with open(extended(receipt_path), "x", encoding="utf-8"):
            pass
        owns_receipt = True
        save()
        require(sys.version_info[:3] == (3, 12, 2), "Exactly Python 3.12.2 is required")
        require(sys.implementation.name == "cpython" and sys.implementation.cache_tag == "cpython-312", "Exactly CPython cache tag cpython-312 is required")
        require(sys.flags.isolated == 1 and sys.flags.no_site == 1 and sys.flags.dont_write_bytecode == 1, "Invoke the candidate Python with -I -S -B")
        root = validate_root(args.root)
        receipt["root"] = root
        verified_directories = set()
        executable = source_path(root, ["runtime", "python", "python.exe"], verified_directories)
        require(
            ntpath.normcase(absolute_windows_path(sys.executable, "Python executable")) == ntpath.normcase(executable),
            "This worker must run with the candidate root's runtime/python/python.exe",
        )
        plan_path = absolute_windows_path(args.plan, "plan")
        with open(extended(plan_path), "rb") as source:
            plan_bytes = source.read()
        receipt["plan_sha256"] = hashlib.sha256(plan_bytes).hexdigest()
        plan = json.loads(plan_bytes.decode("utf-8-sig"), object_pairs_hook=unique_object)
        require(isinstance(plan, dict) and type(plan.get("schema")) is int and plan["schema"] == 1, "Expected plan schema 1")
        require(isinstance(plan.get("entries"), list), "Plan entries must be an array")
        planned = []
        destinations = set()
        verified_sources = {}
        for entry in plan["entries"]:
            require(isinstance(entry, dict), "Each plan entry must be an object")
            current_file = entry.get("file")
            cache_parts = relative_member(current_file, "cache file")
            source_parts = relative_member(entry.get("source"), "source")
            optimize = entry.get("optimize")
            require(type(optimize) is int and optimize in (0, 1, 2), "optimize must be 0, 1 or 2")
            expected_sha = entry.get("source_sha256")
            previous_sha = entry.get("previous_sealed_sha256")
            require(isinstance(expected_sha, str) and HEX256.fullmatch(expected_sha), "source_sha256 must contain 64 hexadecimal digits")
            require("previous_sealed_sha256" in entry and (previous_sha is None or isinstance(previous_sha, str) and HEX256.fullmatch(previous_sha)), "previous_sealed_sha256 must be null or a SHA256")
            source = source_path(root, source_parts, verified_directories)
            expected_cache = importlib.util.cache_from_source(source, optimization="" if optimize == 0 else str(optimize))
            expected_relative = ntpath.relpath(expected_cache, root).replace("\\", "/")
            require(current_file == expected_relative, "Cache and source are not the matching PEP 3147 paths")
            require(source_parts[-1].endswith(".py"), "The compile source must be a .py file")
            cache_parent, unused = member_directory(root, cache_parts[:-1], allow_missing_last=True,
                                                     verified_directories=verified_directories)
            cache = ntpath.join(cache_parent, cache_parts[-1])
            key = ntpath.normcase(cache)
            require(key not in destinations, "Duplicate cache destination")
            destinations.add(key)
            require_missing(cache)
            source_key = ntpath.normcase(source)
            if source_key not in verified_sources:
                with open(extended(source), "rb") as input_file:
                    contents = input_file.read()
                verified_sources[source_key] = (hashlib.sha256(contents).hexdigest(), importlib.util.source_hash(contents))
            actual_sha, source_hash = verified_sources[source_key]
            require(actual_sha.lower() == expected_sha.lower(), "Actual source SHA256 differs from plan")
            planned.append((dict(entry), source_parts, cache_parts, source_hash))
        receipt["source_hashes_verified"] = True
        receipt["planned_count"] = len(planned)
        save()
        # The private candidate is exclusively owned, with no parallel writers.
        # Validate every directory once per phase rather than once per cache.
        verified_directories.clear()
        root = validate_root(root)
        for entry, source_parts, cache_parts, source_hash in planned:
            current_file = entry["file"]
            # The source file and target absence are still checked per cache.
            source = source_path(root, source_parts, verified_directories)
            cache_parent, present = member_directory(root, cache_parts[:-1], allow_missing_last=True,
                                                      verified_directories=verified_directories)
            if not present:
                os.mkdir(extended(cache_parent))
            member_directory(root, cache_parts[:-1], verified_directories=verified_directories)
            cache = ntpath.join(cache_parent, cache_parts[-1])
            require_missing(cache)
            py_compile.compile(
                extended(source),
                cfile=extended(cache),
                dfile="/".join(source_parts[2:]),
                doraise=True,
                optimize=entry["optimize"],
                invalidation_mode=py_compile.PycInvalidationMode.CHECKED_HASH,
            )
            plain_stat(cache, directory=False)
            digest, count = cache_observation(cache, source_hash)
            receipt["files"].append(dict(entry, sha256=digest, bytes=count))
            receipt["generated_count"] = len(receipt["files"])
            if receipt["generated_count"] % 64 == 0:
                save()
        current_file = None
        receipt["state"] = "passed"
        save()
        return 0
    except BaseException as error:
        receipt.update(state="failed", failed_file=current_file, error=type(error).__name__ + ": " + str(error))
        if owns_receipt:
            try:
                save()
            except BaseException as receipt_error:
                print("Cannot save failure receipt: " + str(receipt_error), file=sys.stderr)
        print(json.dumps({"state": "failed", "file": current_file, "error": receipt["error"]}, ensure_ascii=False), file=sys.stderr)
        return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--receipt", required=True)
    return run(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
