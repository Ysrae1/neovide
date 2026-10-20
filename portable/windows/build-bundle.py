#!/usr/bin/env python3
"""Build-worker entry: prepare a fully native offline payload before ISCC runs.

This is deliberately separate from the frozen Mac/WSL installer. Installed users
never run this script, pip, npm, a compiler, or a dependency downloader.
"""
import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PORTABLE = HERE.parent
REPO = PORTABLE.parent
sys.path.insert(0, str(PORTABLE / "scripts"))
from install import Installer, InstallError, bundled_font_files, read_json, sha, write_json


class WindowsBundle(Installer):
    def __init__(self, work, frontend, stack_id):
        self.root = work.resolve()
        self.stage = self.root / "stage"
        self.profile = self.root / "profile"
        self.cache = self.root / "downloads"
        self.meta = self.root / "records"
        self.bundle, self.payload = PORTABLE, PORTABLE / "payload"
        self.manifest = read_json(PORTABLE / "manifest.json")
        self.lock = read_json(HERE / "assets.lock.json")
        self.target, self.is_mac, self.native_ext = "windows-x64", False, "dll"
        self.stack_id, self.frontend = stack_id, frontend.resolve()
        self.profile_data = self.profile / "data/nvim-data"
        self.plugins_manifest = self.payload / "plugins.json"
        self.plugins = read_json(self.plugins_manifest)["plugins"]
        self.env = dict(os.environ)
        self.env.update({
            "XDG_CONFIG_HOME": str(self.profile / "config"),
            "XDG_DATA_HOME": str(self.profile / "data"),
            "XDG_STATE_HOME": str(self.profile / "state"),
            "XDG_CACHE_HOME": str(self.profile / "cache"),
            "NVIM_APPNAME": "nvim", "NEOVIDE_BUNDLE_PLATFORM": "windows-x64",
            "NEOVIDE_GLOW_ROOT": str(self.stage),
            "NEOVIDE_GLOW_INIT": str(self.stage / "runtime/lua/WindowsInit.lua"),
            "NEOVIDE_GLOW_PYTHON": str(self.stage / "runtime/python/python.exe"),
            "GLOW_PYTHON": str(self.stage / "runtime/python/python.exe"),
            "GLOW_LATEX2TEXT": str(self.stage / "bin/latex2text.exe"),
            "YAZI_FILE_ONE": str(self.stage / "tools/git/usr/bin/file.exe"),
            "UV_PYTHON_DOWNLOADS": "never", "UV_CACHE_DIR": str(self.root / "cache/uv"),
            "npm_config_cache": str(self.root / "cache/npm"), "PYTHONNOUSERSITE": "1", "PYTHONUTF8": "1",
            "GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "core.longpaths", "GIT_CONFIG_VALUE_0": "true",
            "GIT_CONFIG_KEY_1": "core.autocrlf", "GIT_CONFIG_VALUE_1": "false",
            "JAVA_HOME": str(self.stage / "runtime/java"),
        })
        self.env.pop("VIM", None)
        self.env.pop("VIMRUNTIME", None)
        paths = [self.stage / relative for relative in (
            "bin", "runtime/python", "runtime/python/Scripts", "runtime/node",
            "runtime/java/bin", "tools/git/cmd")]
        # Portable Git's usr/bin/link.exe is the POSIX hard-link utility. Keep it
        # off the compiler PATH so MSVC finds its own linker; Yazi uses the
        # absolute YAZI_FILE_ONE path and still gets its adjacent MSYS DLLs.
        paths.extend(self.stage / "tools" / name for name in ("yazi", "rg", "fd", "fzf", "lazygit", "uv", "tree_sitter"))
        paths.append(self.profile_data / "mason/bin")
        self.env["PATH"] = os.pathsep.join([*map(str, paths), self.env.get("PATH", "")])
        self.required = []
        self.root.mkdir(parents=True, exist_ok=True)
        identity = {"schema_version": 1, "stack_id": stack_id, "asset_lock": sha(HERE / "assets.lock.json")}
        marker = self.root / "windows-build.json"
        if marker.exists() and read_json(marker) != identity:
            raise InstallError("Use a fresh build directory for changed release inputs.")
        write_json(marker, identity)

    def run(self, args, cwd=None, capture=False, env=None):
        command = list(map(str, args))
        if command[0].lower().endswith((".cmd", ".bat")):
            command = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", subprocess.list2cmdline(command)]
        return super().run(command, cwd=cwd, capture=capture, env=env)

    def entry(self, key):
        if key in self.lock["assets"]:
            entry = self.lock["assets"][key]
            return {"version": entry["version"]}, entry
        return super().entry(key)

    def unpack(self, key):
        tool, entry = self.entry(key)
        if entry["format"] != "7zip":
            return super().unpack(key)
        destination = self.root / "vendor" / key / (tool["version"] + "-" + self.target)
        marker = destination / ".artifact.json"
        if marker.is_file():
            if read_json(marker).get("sha256") != entry["sha256"]:
                raise InstallError("The existing extracted tool uses a different asset lock.")
            return destination
        if destination.exists():
            raise InstallError("Existing incomplete vendor extraction was preserved: " + str(destination))
        archive = self.download(entry)
        listing = self.run(["7z", "l", "-slt", archive], capture=True)
        members = listing.split("----------", 1)[-1]
        for line in members.splitlines():
            if line.startswith("Path = "):
                relative = line[7:].replace("\\", "/")
                if relative.startswith("/") or ":" in relative or ".." in relative.split("/"):
                    raise InstallError("Unsafe member in the locked 7-Zip input.")
            if line.startswith(("Symbolic Link = ", "Hard Link = ")):
                raise InstallError("Links are not allowed in the locked native tool input.")
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".git-extract-", dir=destination.parent) as temporary:
            source = Path(temporary) / "files"
            self.run(["7z", "x", "-y", "-o" + str(source), archive])
            write_json(source / ".artifact.json", {"sha256": entry["sha256"], "url": entry["url"]})
            source.rename(destination)
        return destination

    @staticmethod
    def copy(source, destination):
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, destination, dirs_exist_ok=True)
        else:
            shutil.copy2(source, destination)

    def need(self, relative):
        path = self.stage / relative
        if not path.is_file():
            raise InstallError("Missing precompiled runtime component: " + relative)
        self.required.append(relative)

    def tools(self):
        nvim = self.locate(self.unpack("nvim"), "nvim.exe").parent.parent
        for name in ("bin", "share", "lib"):
            if (nvim / name).exists():
                self.copy(nvim / name, self.stage / name)
        self.copy(self.frontend, self.stage / "bin/neovide.exe")
        for key in ("yazi", "rg", "fd", "fzf", "lazygit", "uv", "tree_sitter"):
            _, entry = self.entry(key)
            source = self.unpack(key)
            destination = self.stage / "tools" / key
            self.copy(source, destination)
            executable = self.locate(destination, entry["binary"])
            if executable.parent != destination:
                # Retain notices and adjacent DLLs while flattening the tool root.
                for child in executable.parent.iterdir():
                    self.copy(child, destination / child.name)
            self.need(str((destination / entry["binary"]).relative_to(self.stage)))
        git = self.unpack("git")
        self.copy(git, self.stage / "tools/git")
        self.need("tools/git/cmd/git.exe")
        self.need("tools/git/usr/bin/file.exe")
        self.copy(self.locate(self.unpack("python"), "python.exe").parent, self.stage / "runtime/python")
        self.copy(self.locate(self.unpack("node"), "node.exe").parent, self.stage / "runtime/node")
        self.copy(self.locate(self.unpack("java"), "java.exe").parent.parent, self.stage / "runtime/java")
        self.copy(self.payload / "nvim", self.profile / "config/nvim")
        self.copy(self.payload / "yazi", self.profile / "config/yazi")
        init = self.profile / "config/nvim/init.lua"
        guard = 'if vim.env.NEOVIDE_GLOW_INIT then dofile(vim.env.NEOVIDE_GLOW_INIT) end\n'
        if not init.read_text(encoding="utf-8").startswith(guard):
            init.write_text(guard + init.read_text(encoding="utf-8"), encoding="utf-8")
        self.copy(HERE / "runtime/WindowsInit.lua", self.stage / "runtime/lua/WindowsInit.lua")
        self.copy(HERE / "runtime/tool.py", self.stage / "runtime/tool.py")
        self.copy(HERE / "runtime/mason_tool.py", self.stage / "runtime/mason_tool.py")
        self.copy(self.payload / "windows-icon.ico", self.stage / "neovide.ico")
        for font in bundled_font_files(self.payload / "fonts", "windows"):
            self.copy(font, self.stage / "fonts" / font.name)
        self.copy(self.payload / "fonts/licenses", self.stage / "licenses/fonts")
        self.copy(PORTABLE / "licenses", self.stage / "licenses/stack")
        self.copy(REPO / "LICENSE", self.stage / "licenses/Neovide-MIT.txt")
        self.copy(HERE / "matrix", self.stage / "source/cmatrix-windows")
        self.copy(self.payload / "patches/cmatrix-unimatrix.patch", self.stage / "source/cmatrix-unimatrix.patch")
        config = (self.payload / "neovide/config.toml").read_text(encoding="utf-8")
        lines = []
        for line in config.splitlines():
            if re.match(r"\s*(neovim-bin|frame|title-hidden|wsl|icon|system-[\w-]+)\s*=", line):
                continue
            lines.append(line.replace("PingFang SC", "Noto Sans Mono CJK SC"))
        path = self.stage / "config/neovide.toml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('frame = "full"\nwsl = false\n' + "\n".join(lines) + "\n", encoding="utf-8")
        self.need("bin/nvim.exe")
        self.need("bin/neovide.exe")
        self.need("runtime/python/python.exe")
        self.need("runtime/node/node.exe")
        self.need("runtime/java/bin/java.exe")

    def python_dependencies(self):
        python = self.stage / "runtime/python/python.exe"
        self.run([python, "-m", "pip", "install", "--disable-pip-version-check", "--no-warn-script-location",
                  "-r", self.payload / "nvim/lua/config/media/runtime/requirements.txt"])
        self.run([python, "-m", "pip", "install", "--disable-pip-version-check", "--require-hashes",
                  "-r", self.payload / "requirements-latex.lock"])
        self.run([python, "-c", "import pynvim,jupyter_client,jupytext,nbformat,PIL,matplotlib,pylatexenc;print('Bundled Python imports passed')"])
        packages = self.run([python, "-m", "pip", "list", "--format=json", "--disable-pip-version-check"], capture=True)
        write_json(self.root / "records/python-packages.json", json.loads(packages))

    def native_plugins(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(self.checkout, self.plugins))
        toolchain = self.lock["rust_toolchain"]
        for plugin in self.plugins:
            path = self.profile_data / "lazy" / plugin["name"]
            action = plugin.get("build_action", "none")
            if action == "fff":
                _, entry = self.entry("fff")
                self.copy(self.download(entry), path / "target/release/libfff_nvim.dll")
            elif action == "avante":
                for package in ("tokenizers", "templates", "repo-map", "html2md"):
                    env = dict(self.env)
                    env.pop("CARGO_TARGET_DIR", None)
                    self.run(["cargo", "+" + toolchain, "build", "--release", "--locked", "--features=luajit", "-p", "avante-" + package], cwd=path, env=env)
                    name = "avante_" + package.replace("-", "_") + ".dll"
                    self.copy(path / "target/release" / name, path / "build" / name)
            elif action == "telescope-fzf-native":
                self.run(["cmake", "-S", path, "-B", path / "build", "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release"])
                self.run(["cmake", "--build", path / "build", "--config", "Release"])
                # The pinned Lua loader names this library libfzf.dll on Windows.
                if not (path / "build/libfzf.dll").is_file():
                    raise InstallError("Telescope Windows DLL was not produced.")
            elif action == "luasnip":
                # Keep optional JS regexp support explicit. This source must be
                # compiled against the bundled Neovim LuaJIT ABI, never macOS .so.
                script = HERE / "build-luasnip.ps1"
                if not script.is_file():
                    raise InstallError("Windows LuaSnip ABI build entry is not implemented; refusing an incomplete installer.")
                self.run(["powershell", "-NoProfile", "-File", script, "-Source", path, "-Neovim", self.stage])

    def auxiliary(self):
        acp = self.profile_data / "codex-acp"
        self.copy(self.payload / "codex-acp", acp)
        self.run([self.stage / "runtime/node/npm.cmd", "ci", "--no-audit", "--no-fund"], cwd=acp)
        commands = {}
        for command, package in (("codex-acp", "@agentclientprotocol/codex-acp"), ("codex", "@openai/codex")):
            directory = acp / "node_modules" / package
            metadata = read_json(directory / "package.json")
            binary = metadata["bin"]
            script = binary if isinstance(binary, str) else binary[command]
            relative = "profile/data/nvim/codex-acp/node_modules/" + package + "/" + script
            commands[command] = {"runtime": "node", "script": relative}
        write_json(self.stage / "runtime/tool-commands.json", commands)

    def bootstrap(self, phase):
        env = dict(self.env)
        env.update({"NEOVIDE_BUNDLE_PAYLOAD": str(self.payload), "NVIM_BUNDLE_PHASE": phase})
        self.run([self.stage / "bin/nvim.exe", "--headless", "-u", "NONE", "-l", HERE / "bootstrap.lua"], env=env)

    def assemble(self):
        self.copy(self.profile / "config", self.stage / "profile/config")
        data = self.stage / "profile/data/nvim"
        data.mkdir(parents=True, exist_ok=True)
        credential_names = {"auth.json", "credentials.json", ".credentials.json", ".env"}
        omitted_fixtures = []
        for name in ("lazy", "codex-acp", "mason"):
            source = self.profile_data / name
            if not source.is_dir():
                raise InstallError("Offline profile is incomplete: " + name)

            def ignore_build_artifacts(directory, entries):
                ignored = set(shutil.ignore_patterns(".git", "__pycache__", "*.pyc")(directory, entries))
                if name == "lazy" and Path(directory).parent == source:
                    ignored.add("target")
                relative = Path(directory).relative_to(source)
                if name == "lazy" and len(relative.parts) >= 2 and relative.parts[1] in {
                    "spec", "test", "tests", "testdata", "fixtures"
                }:
                    for entry in entries:
                        if entry.casefold() in credential_names:
                            ignored.add(entry)
                            omitted_fixtures.append((Path("profile/data/nvim/lazy") / relative / entry).as_posix())
                return ignored

            shutil.copytree(source, data / name, dirs_exist_ok=True,
                            ignore=ignore_build_artifacts)
        for plugin in self.plugins:
            if plugin.get("build_action") == "fff":
                self.copy(self.profile_data / "lazy" / plugin["name"] / "target/release/libfff_nvim.dll",
                          data / "lazy" / plugin["name"] / "target/release/libfff_nvim.dll")
        self.need("bin/cmatrix-gm.exe")
        self.need("bin/jupytext.exe")
        self.need("bin/latex2text.exe")
        for relative in ("bin/nvim.exe", "bin/neovide.exe", "runtime/python/python.exe", "runtime/node/node.exe",
                         "runtime/java/bin/java.exe", "tools/git/cmd/git.exe", "tools/git/usr/bin/file.exe"):
            self.need(relative)
        for key in ("yazi", "rg", "fd", "fzf", "lazygit", "uv", "tree_sitter"):
            self.need("tools/" + key + "/" + self.entry(key)[1]["binary"])
        self.need("profile/data/nvim/lazy/LuaSnip/deps/luasnip-jsregexp.so")
        self.need("profile/data/nvim/lazy/fff/target/release/libfff_nvim.dll")
        for name in ("tokenizers", "templates", "repo_map", "html2md"):
            self.need("profile/data/nvim/lazy/avante.nvim/build/avante_" + name + ".dll")
        self.need("profile/data/nvim/lazy/telescope-fzf-native.nvim/build/libfzf.dll")
        for language in read_json(self.payload / "treesitter.json")["parsers"]:
            self.need("profile/data/nvim/lazy/nvim-treesitter/parser/" + language + ".so")
        self.run([sys.executable, HERE / "relocate-mason.py", "--stage", self.stage])
        for path in self.stage.rglob("*"):
            if path.is_symlink() or path.name.casefold() in credential_names or any(
                part.casefold() in {".git", ".codex"} for part in path.relative_to(self.stage).parts
            ):
                raise InstallError("Unexpected mutable/private/link content in stage: " + str(path.relative_to(self.stage)))
        write_json(self.meta / "omitted-test-fixtures.json", {"paths": sorted(omitted_fixtures),
                   "reason": "Credential-like test fixtures are not needed by installed plugins."})
        write_json(self.stage / "bundle.json", {"schema_version": 1, "stack_id": self.stack_id,
            "neovide_commit": self.lock["neovide_commit"], "native_required": sorted(set(self.required)),
            "tool_paths": ["runtime/python", "runtime/python/Scripts", "runtime/node", "runtime/java/bin", "tools/git/cmd", "tools/git/usr/bin",
                           *["tools/" + name for name in ("yazi", "rg", "fd", "fzf", "lazygit", "uv", "tree_sitter")]]})
        checksums = {str(p.relative_to(self.stage)).replace("\\", "/"): sha(p)
                     for p in sorted(self.stage.rglob("*")) if p.is_file()}
        write_json(self.stage / "bundle-sha256.json", checksums)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--frontend", type=Path, required=True)
    parser.add_argument("--stack-id", default="glow-windows-native-20261020-preview1")
    parser.add_argument("--phase", choices=("prepare", "native", "languages", "assemble"), required=True)
    args = parser.parse_args()
    if sys.platform != "win32":
        parser.error("Build this payload on the Windows release worker; there is no WSL fallback.")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,100}", args.stack_id):
        parser.error("Invalid stack identifier.")
    bundle = WindowsBundle(args.work, args.frontend, args.stack_id)
    if args.phase == "prepare":
        bundle.tools()
        bundle.python_dependencies()
    elif args.phase == "native":
        bundle.native_plugins()
        bundle.auxiliary()
    elif args.phase == "languages":
        bundle.bootstrap("parsers")
        bundle.bootstrap("mason")
    else:
        bundle.assemble()
    print("Windows offline build phase completed:", args.phase)


if __name__ == "__main__":
    main()
