#!/usr/bin/env python3
"""Verify the reviewed, pinned notice corpus and render a portable text notice.

Normal use is offline. --refresh re-downloads the pinned upstream originals and
verifies their hashes; it does not resolve or upgrade project dependencies.
A Cargo.lock update requires a new review of the corpus before packaging.
"""
from __future__ import annotations

import argparse
import base64
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tarfile
import tempfile
import tomllib
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "licenses" / "third-party"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def text_path(digest: str) -> Path:
    if not re.fullmatch(r"[a-f0-9]{64}", digest):
        raise ValueError(f"Invalid notice digest: {digest!r}")
    return CORPUS / "texts" / f"{digest}.txt"


def all_notices(manifest: dict) -> list[dict]:
    return [manifest["skia"]["deps"]] + [
        notice
        for component in manifest["crates"] + manifest["native"]
        for notice in component["notices"]
    ]


def validate(manifest: dict) -> list[str]:
    if manifest.get("schema") != 1:
        raise ValueError("Unsupported notice corpus schema")
    lock_bytes = (ROOT / "Cargo.lock").read_bytes()
    if sha256(lock_bytes) != manifest["cargo_lock_sha256"]:
        raise ValueError("Cargo.lock changed; review and regenerate the dependency notice corpus")
    locked = {
        (p["name"], p["version"], p["checksum"])
        for p in tomllib.loads(lock_bytes.decode())["package"]
        if p.get("source", "").startswith("registry+")
    }
    reviewed = {(p["name"], p["version"], p["checksum"]) for p in manifest["crates"]}
    if locked != reviewed or len(reviewed) != len(manifest["crates"]):
        raise ValueError("The notice index does not exactly cover the locked registry packages")
    for notice in all_notices(manifest):
        path = text_path(notice["sha256"])
        data = path.read_bytes()
        if not data or sha256(data) != notice["sha256"]:
            raise ValueError(f"Missing or modified upstream notice: {path}")
        data.decode("utf-8")
    skia = manifest["skia"]
    if ("skia-bindings", skia["bindings_version"]) not in {(n, v) for n, v, _ in locked}:
        raise ValueError("Skia source notices do not match the locked skia-bindings version")
    deps = text_path(skia["deps"]["sha256"]).read_text()
    expected = set(re.findall(
        r'^\s*[\"\']third_party/externals/([^\"\']+)[\"\']\s*:\s*[\"\']https://[^\"\']+@([a-f0-9]{40})',
        deps, re.MULTILINE,
    ))
    covered = {(c["name"], c["revision"]) for c in manifest["native"] if c["name"] != "Skia"}
    if expected != covered:
        raise ValueError("Native notices do not exactly cover the pinned Skia DEPS externals")
    skia_sources = [c for c in manifest["native"] if c["name"] == "Skia"]
    if len(skia_sources) != 1 or skia_sources[0]["revision"] != skia["revision"]:
        raise ValueError("Skia source notice revision mismatch")
    gaps = []
    for component in manifest["crates"] + manifest["native"]:
        if not component["notices"]:
            reason = component.get("missing_notice")
            if not reason:
                raise ValueError(f"Unexplained missing notices: {component['name']}")
            gaps.append(f"{component['name']} {component.get('version', '')}: {reason}")
    return gaps


def refresh(manifest: dict, cache: Path) -> None:
    """Reproduce the reviewed corpus from hash-checked crates and pinned URLs."""
    cache.mkdir(parents=True, exist_ok=True)

    def download(url: str) -> bytes:
        path = cache / (sha256(url.encode()) + ".source")
        if path.exists():
            return path.read_bytes()
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read()
        path.write_bytes(data)
        return data

    def save(notice: dict, data: bytes) -> None:
        if sha256(data) != notice["sha256"]:
            raise ValueError(f"Upstream source changed: {notice.get('url', notice.get('archive_url'))}")
        text_path(notice["sha256"]).write_bytes(data)

    def crate(component: dict) -> None:
        packaged = [n for n in component["notices"] if "archive_url" in n]
        if not packaged:
            return
        data = download(component["archive_url"])
        if sha256(data) != component["checksum"]:
            raise ValueError(f"Locked crate checksum mismatch: {component['name']}")
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            prefix = f"{component['name']}-{component['version']}/"
            for notice in packaged:
                handle = archive.extractfile(prefix + notice["path"])
                if handle is None:
                    raise ValueError(f"Missing reviewed notice in archive: {notice['path']}")
                save(notice, handle.read())

    def upstream(notice: dict) -> None:
        data = download(notice["url"])
        if notice.get("encoding") == "base64":
            data = base64.b64decode(data)
        save(notice, data)

    # Exceptions propagate; do not publish a partly refreshed corpus as complete.
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        jobs = [pool.submit(crate, c) for c in manifest["crates"]]
        unique = {n["url"]: n for n in all_notices(manifest) if "url" in n}
        jobs += [pool.submit(upstream, n) for n in unique.values()]
        for job in jobs:
            job.result()


def render(manifest: dict, gaps: list[str]) -> str:
    lines = ["Neovide Glow — Rust and native Skia dependency notices", "", manifest["scope"], "",
             f"Cargo.lock SHA-256: {manifest['cargo_lock_sha256']}",
             f"Skia {manifest['skia']['source_tag']} at {manifest['skia']['revision']}", ""]
    if gaps:
        lines += ["KNOWN UPSTREAM NOTICE GAPS — this corpus is not complete:", *gaps, ""]
    lines += ["Dependency index (original notice texts follow; identical texts are shared):", ""]
    originals: dict[str, list[str]] = {}
    for section, components in [("Rust registry packages", manifest["crates"]), ("Native Skia sources", manifest["native"])]:
        lines += [section, "=" * len(section)]
        for component in components:
            version = component.get("version", component.get("revision", ""))
            lines.append(f"{component['name']} {version}")
            if component.get("license"):
                lines.append(f"  Declared terms: {component['license']}")
            if component.get("source_note"):
                lines.append(f"  Source note: {component['source_note']}")
            for notice in component["notices"]:
                digest = notice["sha256"]
                source = notice.get("url", notice.get("archive_url", ""))
                label = f"{component['name']} {version} / {notice['path']}"
                originals.setdefault(digest, []).append(label)
                lines += [f"  {notice['path']} → text {digest}", f"    Source: {source}"]
            if component.get("missing_notice"):
                lines.append(f"  MISSING: {component['missing_notice']}")
        lines.append("")
    for digest, references in originals.items():
        lines += [f"===== Text {digest} =====", *references, "", text_path(digest).read_text(), ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the corpus offline (also done before rendering)")
    parser.add_argument("--require-complete", action="store_true", help="fail when an upstream notice gap is recorded")
    parser.add_argument("--refresh", action="store_true", help="re-fetch and hash-check the pinned originals")
    parser.add_argument("--cache-dir", type=Path, default=ROOT / "target" / "notice-source-cache")
    parser.add_argument("--output", type=Path, help="write a deterministic UTF-8 text notice")
    args = parser.parse_args()
    try:
        manifest = json.loads((CORPUS / "manifest.json").read_text())
        if args.refresh:
            refresh(manifest, args.cache_dir)
        gaps = validate(manifest)
        for gap in gaps:
            print(f"NOTICE GAP: {gap}", file=sys.stderr)
        if args.require_complete and gaps:
            raise ValueError(f"{len(gaps)} upstream notice gap(s) require resolution before a complete-license release")
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False) as handle:
                temporary = Path(handle.name)
                handle.write(render(manifest, gaps).encode())
            temporary.chmod(0o644)
            temporary.replace(args.output)
        print(f"Verified {len(manifest['crates'])} locked registry packages and {len(manifest['native'])} native Skia components; {len(gaps)} known upstream gap(s).")
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print(f"Dependency notices: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
