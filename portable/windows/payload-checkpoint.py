#!/usr/bin/env python3
"""Preserve a sealed, fully built CI payload; never read an installed user profile."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile

TESTS = "passed_release_locked_x86_64_pc_windows_msvc"
SEAL = "bundle-sha256.json"


class Invalid(ValueError):
    pass


def require(condition, code):
    if not condition:
        raise Invalid(code)

def node(path):
    info = path.lstat()
    require(not stat.S_ISLNK(info.st_mode) and not getattr(info, "st_file_attributes", 0) & 0x400, "links_forbidden")
    return info

def digest(path):
    node(path)
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def read(path):
    node(path)
    with path.open(encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), "invalid_metadata_object")
    return value

def names(mapping):
    require(isinstance(mapping, dict), "invalid_digest_map")
    require(len({str(k).casefold() for k in mapping}) == len(mapping), "case_collision")
    for name, checksum in mapping.items():
        require(isinstance(name, str) and name and "\\" not in name and ":" not in name
                and not name.startswith("/") and all(p not in ("", ".", "..") for p in name.split("/"))
                and PurePosixPath(name).as_posix() == name, "invalid_relative_path")
        require(isinstance(checksum, str) and re.fullmatch(r"[0-9a-f]{64}", checksum), "invalid_digest")

def tree(root):
    node(root)
    require(root.is_dir(), "missing_directory")
    files = {}
    for path in root.rglob("*"):
        info = node(path)
        if stat.S_ISREG(info.st_mode):
            files[path.relative_to(root).as_posix()] = digest(path)
        else:
            require(stat.S_ISDIR(info.st_mode), "unsupported_file_type")
    names(files)
    return files

def sealed(stage, commit):
    actual = tree(stage)
    expected = read(stage / SEAL)
    names(expected)
    expected.pop(SEAL, None)
    require(actual.pop(SEAL, None) is not None, "missing_stage_seal")
    require(actual == expected, "stage_digest_mismatch")
    require(read(stage / "bundle.json").get("neovide_commit") == commit, "stage_commit_mismatch")
    return len(actual)

def empty_target(path):
    if os.path.lexists(path):
        require(stat.S_ISDIR(node(path).st_mode) and not any(path.iterdir()), "target_not_empty")

def publish_copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".glow-checkpoint-", dir=destination.parent))
    try:
        shutil.copytree(source, temporary, dirs_exist_ok=True)
        empty_target(destination)
        if destination.exists():
            destination.rmdir()
        temporary.rename(destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("save", "restore"))
    for option in ("cache", "stage", "records", "asset-lock"):
        parser.add_argument("--" + option, type=Path, required=True)
    parser.add_argument("--key", required=True)
    args = parser.parse_args()
    try:
        require(0 < len(args.key) <= 512, "invalid_key")
        paths = [p.resolve() for p in (args.cache, args.stage, args.records)]
        require(all(not a.is_relative_to(b) and not b.is_relative_to(a)
                    for index, a in enumerate(paths) for b in paths[index + 1:]), "overlapping_paths")
        commit = read(args.asset_lock).get("neovide_commit")
        require(isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{40}", commit), "invalid_locked_commit")
        identity = dict(schema_version=1, key=args.key, asset_lock_sha256=digest(args.asset_lock),
                        neovide_commit=commit, windows_rust_unit_tests=TESTS)
        if args.mode == "save":
            require(not os.path.lexists(args.cache), "existing_cache_preserved")
            count = sealed(args.stage, commit)
            record_digests = tree(args.records)
            args.cache.parent.mkdir(parents=True, exist_ok=True)
            temporary = Path(tempfile.mkdtemp(prefix=".glow-checkpoint-", dir=args.cache.parent))
            try:
                shutil.copytree(args.stage, temporary / "stage")
                shutil.copytree(args.records, temporary / "records")
                sealed(temporary / "stage", commit)
                require(tree(temporary / "records") == record_digests, "records_changed_during_copy")
                metadata = dict(identity, records_sha256=record_digests)
                if os.environ.get("GITHUB_REPOSITORY") and os.environ.get("GITHUB_RUN_ID"):
                    metadata["producer_run_url"] = (os.environ.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
                        + "/" + os.environ["GITHUB_REPOSITORY"] + "/actions/runs/" + os.environ["GITHUB_RUN_ID"])
                (temporary / "checkpoint.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
                require(not os.path.lexists(args.cache), "existing_cache_preserved")
                temporary.rename(args.cache)
            finally:
                if temporary.exists():
                    shutil.rmtree(temporary)
        else:
            node(args.cache)
            require({p.name for p in args.cache.iterdir()} == {"checkpoint.json", "stage", "records"}, "invalid_cache_layout")
            metadata = read(args.cache / "checkpoint.json")
            require(type(metadata.get("schema_version")) is int, "invalid_schema")
            require(all(metadata.get(k) == v for k, v in identity.items()), "checkpoint_identity_mismatch")
            count = sealed(args.cache / "stage", commit)
            require(tree(args.cache / "records") == metadata.get("records_sha256"), "records_digest_mismatch")
            empty_target(args.stage)
            empty_target(args.records)
            publish_copy(args.cache / "stage", args.stage)
            publish_copy(args.cache / "records", args.records)
        print(json.dumps(dict(status="ok", mode=args.mode, stage_files=count, neovide_commit=commit)))
        return 0
    except (OSError, ValueError, TypeError) as error:
        print(json.dumps(dict(status="error", reason=str(error) if isinstance(error, Invalid) else "invalid_or_unavailable_input")))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
