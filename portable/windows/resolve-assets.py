#!/usr/bin/env python3
"""Maintainer-only: lock native Windows inputs, never run by installed Glow."""
import argparse
import concurrent.futures
import hashlib
import http.client
import json
import re
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUNDLE = HERE.parent


def fetch(url):
    cache = BUNDLE.parent / "target/glow-windows-native-assets"
    cache.mkdir(parents=True, exist_ok=True)
    saved = cache / hashlib.sha256(url.encode()).hexdigest()
    if saved.is_file():
        return saved.read_bytes()
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "neovide-glow-release/1", "Connection": "close"})
            with urllib.request.urlopen(request, timeout=45) as response:
                content = response.read()
            saved.write_bytes(content)
            return content
        except (http.client.IncompleteRead, urllib.error.URLError, TimeoutError, ConnectionError) as error:
            if (isinstance(error, urllib.error.HTTPError) and error.code < 500) or attempt == 2:
                raise
            time.sleep(attempt + 1)


def github_asset(repository, tag, filename, binary, archive_format):
    release = json.loads(fetch(f"https://api.github.com/repos/{repository}/releases/tags/{tag}"))
    asset = next(item for item in release["assets"] if item["name"] == filename)
    digest = asset.get("digest") or ""
    if re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
        checksum, source = digest[7:], "official-github-release-digest"
    else:
        sidecar = next((item for item in release["assets"] if item["name"] == filename + ".sha256"), None)
        if sidecar:
            checksum = fetch(sidecar["browser_download_url"]).decode().split()[0]
            source = "official-release-sha256"
        else:
            checksum = hashlib.sha256(fetch(asset["browser_download_url"])).hexdigest()
            source = "sha256-of-fixed-official-artifact"
    if not re.fullmatch(r"[a-f0-9]{64}", checksum):
        raise ValueError("Invalid official checksum: " + filename)
    return {"filename": filename, "url": asset["browser_download_url"], "sha256": checksum,
            "format": archive_format, "binary": binary, "checksum_source": source,
            "download_size": asset["size"]}


def resolve():
    manifest = json.loads((BUNDLE / "manifest.json").read_text())
    versions = {key: item["version"] for key, item in manifest["assets"].items()}
    specifications = {
        "nvim": ("neovim/neovim", "v" + versions["nvim"], "nvim-win64.zip", "nvim.exe", "zip"),
        "yazi": ("sxyazi/yazi", "v" + versions["yazi"], "yazi-x86_64-pc-windows-msvc.zip", "yazi.exe", "zip"),
        "rg": ("BurntSushi/ripgrep", versions["rg"], f"ripgrep-{versions['rg']}-x86_64-pc-windows-msvc.zip", "rg.exe", "zip"),
        "fd": ("sharkdp/fd", "v" + versions["fd"], f"fd-v{versions['fd']}-x86_64-pc-windows-msvc.zip", "fd.exe", "zip"),
        "fzf": ("junegunn/fzf", "v" + versions["fzf"], f"fzf-{versions['fzf']}-windows_amd64.zip", "fzf.exe", "zip"),
        "lazygit": ("jesseduffield/lazygit", "v" + versions["lazygit"], f"lazygit_{versions['lazygit']}_windows_x86_64.zip", "lazygit.exe", "zip"),
        "uv": ("astral-sh/uv", versions["uv"], "uv-x86_64-pc-windows-msvc.zip", "uv.exe", "zip"),
        "fff": ("dmtrKovalenko/fff", "v" + versions["fff"], "x86_64-pc-windows-msvc.dll", "libfff_nvim.dll", "raw"),
        "tree_sitter": ("tree-sitter/tree-sitter", "v" + versions["tree_sitter"], "tree-sitter-windows-x64.gz", "tree-sitter.exe", "gzip"),
        "git": ("git-for-windows/git", "v2.55.0.windows.5", "PortableGit-2.55.0.5-64-bit.7z.exe", "git.exe", "7zip"),
        "python": ("astral-sh/python-build-standalone", "20240224", "cpython-3.12.2+20240224-x86_64-pc-windows-msvc-shared-install_only.tar.gz", "python.exe", "tar.gz"),
        "java": ("adoptium/temurin21-binaries", "jdk-21.0.12.1+1", "OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip", "java.exe", "zip"),
    }
    def item(pair):
        key, spec = pair
        result = github_asset(*spec)
        result["version"] = versions.get(key, "2.55.0.5" if key == "git" else "3.12.2")
        if key == "python":
            result["version"] = "3.12.2"
        elif key == "java":
            result["version"] = "21.0.12.1+1"
        return key, result
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        assets = dict(pool.map(item, specifications.items()))
    node_version = versions["node"]
    filename = f"node-v{node_version}-win-x64.zip"
    base = f"https://nodejs.org/dist/v{node_version}/"
    checksums = fetch(base + "SHASUMS256.txt").decode()
    checksum = next(line.split()[0] for line in checksums.splitlines() if line.split()[-1] == filename)
    assets["node"] = {"version": node_version, "filename": filename, "url": base + filename,
                      "sha256": checksum, "format": "zip", "binary": "node.exe",
                      "checksum_source": "official-node-shasums256"}
    return {"schema_version": 1, "target": "windows-x64", "base_release": manifest["release_tag"],
            "neovide_commit": manifest["neovide"]["commit"],
            "rust_toolchain": manifest["neovide"]["rust_toolchain"], "assets": assets}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=HERE / "assets.lock.json")
    arguments = parser.parse_args()
    result = resolve()
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("Locked", len(result["assets"]), "native Windows inputs:", arguments.output)
