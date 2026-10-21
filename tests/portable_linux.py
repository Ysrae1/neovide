#!/usr/bin/env python3
"""Linux core contracts; stdlib Python 3.10+, no Rust build or GUI required."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("linux_native", REPO / "portable/scripts/linux-native.py")
linux = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(linux)


def elf(machine=62, executable_type=3):
    header = bytearray(64)
    header[:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<HH", header, 16, executable_type, machine)
    return bytes(header)


def write(path, content, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    if executable:
        path.chmod(0o755)


class LinuxCore(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="glow-linux-test-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()

    def test_linux_config_removes_macos_settings_and_preserves_font_size(self):
        template = ('# defaults\nneovim-bin = "/opt/homebrew/bin/nvim"\n'
                    'frame = "buttonless"\ntitle-hidden = true\n\n'
                    '[font]\nnormal = ["FiraCode Nerd Font Mono", "PingFang SC"]\nsize = 16.0\n')
        nvim = self.base / "tools 中文 'quoted'/nvim"
        result = linux.linux_config(template, nvim)
        self.assertIn("neovim-bin = " + json.dumps(str(nvim)) + "\n", result)
        self.assertIn('frame = "none"\n', result)
        self.assertNotIn("buttonless", result)
        self.assertNotIn("title-hidden", result)
        self.assertNotIn("PingFang", result)
        self.assertIn('["FiraCode Nerd Font Mono", "Noto Sans Mono CJK SC"]', result)
        self.assertIn("size = 16.0\n", result)

    @unittest.skipUnless(Path("/bin/sh").is_file(), "requires POSIX /bin/sh")
    def test_real_launcher_preserves_arguments_profile_and_relocated_root(self):
        profile = self.base / "profile 中文 'and quotes'"
        write(profile / "bin/nvim", b"#!/bin/sh\nexit 0\n", executable=True)
        (profile / "config/nvim").mkdir(parents=True)
        original = self.base / "original core"
        record_code = ('import json, os, sys; '
                       'print(json.dumps({"argv": sys.argv[1:], "env": {k: os.environ.get(k) '
                       'for k in ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", '
                       '"XDG_CACHE_HOME", "NVIM_APPNAME", "YAZI_CONFIG_HOME", "PATH", '
                       '"NEOVIDE_CONFIG"]}}, ensure_ascii=False))')
        binary = "#!/bin/sh\nexec " + shlex.quote(sys.executable) + " -c " + shlex.quote(record_code) + ' "$@"\n'
        write(original / "lib/neovide", binary.encode(), executable=True)
        write(original / "bin/neovide-glow", linux.launcher(profile).encode(), executable=True)
        write(original / "config/neovide/config.toml", b"# isolated config\n")
        relocated = self.base / "relocated 中文 'core'"
        original.rename(relocated)
        arguments = ["two words", "single'quote", 'double"quote', "中文文件.tex", "", "$HOME; echo no", "--flag=value"]
        result = subprocess.run(["/bin/sh", str(relocated.relative_to(self.base) / "bin/neovide-glow"), *arguments],
                                cwd=self.base, env=dict(os.environ, PATH="/usr/bin:/bin"),
                                text=True, capture_output=True, check=True)
        report = json.loads(result.stdout)
        self.assertEqual(report["argv"], arguments)
        expected = {"XDG_CONFIG_HOME": profile / "config", "XDG_DATA_HOME": profile / "data",
                    "XDG_STATE_HOME": profile / "state", "XDG_CACHE_HOME": profile / "cache",
                    "YAZI_CONFIG_HOME": profile / "config/yazi",
                    "NEOVIDE_CONFIG": relocated / "config/neovide/config.toml"}
        for key, value in expected.items():
            self.assertEqual(report["env"][key], str(value), key)
        self.assertEqual(report["env"]["NVIM_APPNAME"], "nvim")
        self.assertEqual(report["env"]["PATH"], os.pathsep.join(map(str, [profile / "bin", profile / "data/nvim/mason/bin",
                                                                         profile / "runtime/bin"])) + ":/usr/bin:/bin")

    @unittest.skipUnless(Path("/bin/sh").is_file(), "requires POSIX /bin/sh")
    def test_launcher_refuses_missing_profile_before_starting_binary(self):
        root = self.base / "core"
        marker = self.base / "binary-was-started"
        write(root / "bin/neovide-glow", linux.launcher(self.base / "missing profile").encode())
        write(root / "lib/neovide", ("#!/bin/sh\ntouch " + shlex.quote(str(marker)) + "\n").encode(), executable=True)
        result = subprocess.run(["/bin/sh", str(root / "bin/neovide-glow")], text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("profile is unavailable", result.stderr)
        self.assertFalse(marker.exists())

    def test_elf_accepts_linux_64bit_little_endian_x86_and_arm_executables(self):
        path = self.base / "neovide"
        for arch, machine in (("x86_64", 62), ("aarch64", 183)):
            for executable_type in (2, 3):
                with self.subTest(arch=arch, executable_type=executable_type):
                    path.write_bytes(elf(machine, executable_type))
                    linux.check_elf(path, arch)

    def test_elf_rejects_malformed_wrong_arch_and_non_executable_files(self):
        path = self.base / "neovide"
        fixtures = {"empty": b"", "truncated": elf()[:63], "not-elf": b"MZ" + elf()[2:],
                    "elf32": b"\x7fELF\x01" + elf()[5:], "big-endian": elf()[:5] + b"\x02" + elf()[6:],
                    "wrong-machine": elf(183), "relocatable": elf(62, 1), "unknown-machine": elf(0)}
        for name, content in fixtures.items():
            with self.subTest(name=name):
                path.write_bytes(content)
                with self.assertRaises(linux.LinuxError):
                    linux.check_elf(path, "x86_64")

    def packaged_root(self):
        root = self.base / "core"
        contents = {"lib/neovide": elf(), "bin/neovide-glow": b"#!/bin/sh\n",
                    "config/neovide/config.toml": b'frame = "none"\n', "licenses/LICENSE": b"test license\n"}
        for relative, content in contents.items():
            write(root / relative, content)
        receipt = {"schema": 1, "architecture": "x86_64", "gui_verified": False,
                   "files": {relative: hashlib.sha256(content).hexdigest() for relative, content in contents.items()}}
        write(root / "linux-core.json", json.dumps(receipt).encode())
        return root, receipt

    def package(self, root, output):
        with contextlib.redirect_stdout(io.StringIO()):
            linux.package(root, output)

    def test_package_contains_only_receipt_listed_files_and_receipt(self):
        root, receipt = self.packaged_root()
        for relative in ("source/private.rs", "cache/download.bin", "auth.json", "profile/config/private.lua"):
            write(root / relative, b"not part of distribution")
        output = self.base / "out/core.tar.gz"
        self.package(root, output)
        prefix = "neovide-glow-linux-x86_64/"
        with tarfile.open(output, "r:gz") as archive:
            self.assertEqual(set(archive.getnames()), {prefix + name for name in ["linux-core.json", *receipt["files"]]})
            self.assertTrue(all(member.isfile() for member in archive.getmembers()))
            for relative, expected in receipt["files"].items():
                content = archive.extractfile(prefix + relative).read()
                self.assertEqual(hashlib.sha256(content).hexdigest(), expected)
            self.assertEqual(json.loads(archive.extractfile(prefix + "linux-core.json").read()), receipt)

    def test_package_refuses_changed_file_before_creating_archive(self):
        root, _ = self.packaged_root()
        (root / "lib/neovide").write_bytes(b"changed")
        output = self.base / "out/core.tar.gz"
        with self.assertRaisesRegex(linux.LinuxError, "changed"):
            self.package(root, output)
        self.assertFalse(output.exists())

    def test_package_refuses_missing_file_before_creating_archive(self):
        root, _ = self.packaged_root()
        (root / "licenses/LICENSE").unlink()
        output = self.base / "out/core.tar.gz"
        with self.assertRaises(linux.LinuxError):
            self.package(root, output)
        self.assertFalse(output.exists())

    def test_package_refuses_symlink_even_when_target_hash_matches(self):
        root, _ = self.packaged_root()
        target = self.base / "external-license"
        target.write_bytes((root / "licenses/LICENSE").read_bytes())
        (root / "licenses/LICENSE").unlink()
        (root / "licenses/LICENSE").symlink_to(target)
        output = self.base / "core.tar.gz"
        with self.assertRaises(linux.LinuxError):
            self.package(root, output)
        self.assertFalse(output.exists())

    def test_package_preserves_existing_output(self):
        root, _ = self.packaged_root()
        output = self.base / "core.tar.gz"
        output.write_bytes(b"existing user archive")
        with self.assertRaisesRegex(linux.LinuxError, "already exists"):
            self.package(root, output)
        self.assertEqual(output.read_bytes(), b"existing user archive")

    @unittest.skipUnless(shutil.which("git"), "requires git for committed source fixture")
    def test_build_uses_committed_source_and_isolated_target_without_running_rust(self):
        source = self.base / "repo"
        source.mkdir()
        subprocess.run(["git", "init", "-q", source], check=True, capture_output=True)
        manifest = {"neovide": {"rust_toolchain": "1.99.1"}}
        write(source / "portable/manifest.json", json.dumps(manifest).encode())
        write(source / "src/main.rs", b"// committed source\n")
        subprocess.run(["git", "-C", source, "add", "portable/manifest.json", "src/main.rs"], check=True, capture_output=True)
        subprocess.run(["git", "-C", source, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                        "commit", "-qm", "fixture"], check=True, capture_output=True)
        commit, selected_manifest = linux.committed_inputs(source, "HEAD")
        write(source / "src/main.rs", b"// uncommitted user change\n")
        write(source / "untracked-secret", b"private")
        write(source / "portable/manifest.json", b'{"neovide":{"rust_toolchain":"dirty"}}')
        self.assertEqual(linux.committed_inputs(source, "HEAD"), (commit, selected_manifest))
        root = self.base / "isolated core"
        real_run = subprocess.run
        cargo_calls = []

        def intercept(command, **kwargs):
            if command[0] != "cargo":
                return real_run(command, **kwargs)
            cargo_calls.append((command, kwargs))
            target = Path(kwargs["env"]["CARGO_TARGET_DIR"])
            write(target / "x86_64-unknown-linux-gnu/release/neovide", elf())
            return subprocess.CompletedProcess(command, 0)

        with patch.object(linux, "build_checks", return_value=[]), patch.object(linux.subprocess, "run", side_effect=intercept):
            with contextlib.redirect_stdout(io.StringIO()):
                receipt = linux.build(source, commit, root, "x86_64", selected_manifest["neovide"]["rust_toolchain"])
        snapshot = root / "source" / commit
        self.assertEqual((snapshot / "src/main.rs").read_bytes(), b"// committed source\n")
        self.assertFalse((snapshot / "untracked-secret").exists())
        self.assertEqual(json.loads((snapshot / "portable/manifest.json").read_text()), manifest)
        self.assertEqual((source / "src/main.rs").read_bytes(), b"// uncommitted user change\n")
        self.assertEqual(len(cargo_calls), 1)
        command, kwargs = cargo_calls[0]
        self.assertEqual(command, ["cargo", "+1.99.1", "build", "--locked", "--release", "--bin", "neovide", "--target", "x86_64-unknown-linux-gnu"])
        self.assertEqual(kwargs["cwd"], snapshot)
        self.assertEqual(kwargs["env"]["CARGO_TARGET_DIR"], str(root / "build" / commit))
        self.assertFalse((source / "target").exists())
        self.assertEqual(receipt["commit"], commit)
        self.assertEqual(receipt["sha256"], linux.digest(Path(receipt["binary"])))


if __name__ == "__main__":
    unittest.main(verbosity=2)
