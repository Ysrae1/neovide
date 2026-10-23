#!/usr/bin/env python3
"""Core-stage contract: synthetic sealed files only; no Windows/download/install."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import struct
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("core_package", REPO / "portable/windows/core-package.py")
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


class CorePackage(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "sealed"
        self.destination = self.root / "new-core"
        self.source.mkdir()
        self.here = self.root / "portable/windows"
        self.payload = self.here.parent / "payload"
        files = {
            "bin/neovide.exe": b"frontend", "bin/nvim.exe": b"nvim", "bin/vcruntime140.dll": b"crt",
            "bin/cmatrix-gm.exe": b"matrix", "share/nvim/runtime/filetype.lua": b"runtime",
            "config/neovide.toml": b'frame = "full"\nwsl = false\n[font]\nsize = 12.5\n', "profile/config/nvim/init.lua": b"old config",
            "profile/config/nvim/lazy-lock.json": b'{"plugin":"frozen"}',
            "profile/config/yazi/init.lua": b"yazi", "profile/data/nvim/lazy/plugin/build/native.dll": b"native",
            "runtime/python/python.exe": b"python" * 800, "runtime/node/node.exe": b"node" * 800,
            "runtime/java/bin/java.exe": b"java" * 800, "tools/git/cmd/git.exe": b"git" * 800,
            "profile/data/nvim/mason/huge-language-runtime.dat": b"mason" * 800,
            "profile/data/nvim/codex-acp/node_modules/huge.exe": b"codex" * 800,
            "fonts/font.ttf": b"font", "licenses/notice.txt": b"license", "Glow.exe": b"old launcher",
        }
        for path, content in files.items():
            self.write(self.source / path, content)
        self.metadata = {"schema_version": 1, "stack_id": "old-offline", "neovide_commit": "b" * 40,
                         "native_required": ["bin/nvim.exe", "runtime/python/python.exe",
                                             "profile/data/nvim/lazy/plugin/build/native.dll"], "tool_paths": ["runtime/python"]}
        self.write(self.source / "bundle.json", json.dumps(self.metadata).encode())
        self.checksums = {path.relative_to(self.source).as_posix(): core.digest(path)
                          for path in self.source.rglob("*") if path.is_file()}
        self.write(self.source / "bundle-sha256.json", json.dumps(self.checksums).encode())
        self.original = {path: (self.source / path).read_bytes() for path in self.checksums}
        for path, content in {
            "nvim/init.lua": b"-- current defaults\n", "nvim/lazy-lock.json": files["profile/config/nvim/lazy-lock.json"],
            "nvim/lua/config/media/runtime/requirements.txt": b"pynvim==0.6.0\n",
            "yazi/init.lua": b"current yazi", "requirements-latex.lock": b"pylatexenc==2.11\n",
            "codex-acp/package.json": b'{"name":"fixture"}', "codex-acp/package-lock.json": b'{"lockfileVersion":3}',
        }.items():
            self.write(self.payload / path, content)
        for path in ["runtime/WindowsInit.lua", "Setup-Dependencies.ps1", "dependencies.json", "WebView2.ps1", "Dependency-Helpers.ps1", "system-assets.lock.json", "Setup-LaTeX.ps1", "Setup-Notebook.ps1", "setup-notebook.py", "Setup-ACP.ps1", "tex/Install-TinyTeX.ps1", "tex/Fontconfig.ps1", "tex/fixture.tex", "tex/asset-lock.json"]:
            self.write(self.here / path, b"test input")
        self.launcher = self.root / "new-launcher.exe"
        self.launcher.write_bytes(b"compiled current launcher")
        self.write(self.root / "licenses/third-party/manifest.json", b'{"fixture":"reviewed notices"}')
        self.write(self.root / "scripts/generate-third-party-notices.py", 'import pathlib,sys\np=pathlib.Path(sys.argv[-1]);p.parent.mkdir(parents=True,exist_ok=True);p.write_text("reviewed Rust and native dependency notices — 中文")\n'.encode("utf-8"))
        self.mock = patch.object(core, "HERE", self.here)
        self.mock.start()

    def tearDown(self):
        self.mock.stop()
        self.temporary.cleanup()

    @staticmethod
    def write(path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def build(self, stack="new-core", **kwargs):
        return core.build(self.source, self.destination, self.launcher, stack, **kwargs)

    def frontend(self, machine=0x8664):
        content = bytearray(512)
        content[:2] = b"MZ"
        struct.pack_into("<I", content, 0x3C, 0x80)
        content[0x80:0x84] = b"PE\0\0"
        struct.pack_into("<H", content, 0x84, machine)
        struct.pack_into("<H", content, 0x98, 0x20B)
        path = self.root / "new-frontend.exe"
        path.write_bytes(content)
        return path

    def test_smaller_core_and_unchanged_source(self):
        report = self.build()
        self.assertLess(report["core_bytes"], report["source_bytes"])
        self.assertEqual(report["source_stack"], "old-offline")
        self.assertEqual(report["retained"]["plugins"]["plugin"]["native_bytes"], len(b"native"))
        self.assertEqual(report["retained"]["plugins"]["plugin"]["download_cache_bytes"], 0)
        self.assertIn("runtime", report["omitted"]["components"])
        for path, contents in self.original.items():
            self.assertEqual((self.source / path).read_bytes(), contents)
        for directory in ["runtime/python", "runtime/node", "runtime/java", "tools", "profile/data/nvim/mason", "profile/data/nvim/codex-acp"]:
            self.assertFalse((self.destination / directory).exists(), directory)
        self.assertTrue((self.destination / "profile/data/nvim/lazy/plugin/build/native.dll").is_file())
        self.assertEqual((self.destination / "licenses/THIRD-PARTY-NOTICES.txt").read_text(encoding="utf-8"), "reviewed Rust and native dependency notices — 中文")
        self.assertEqual((self.destination / "licenses/THIRD-PARTY-NOTICES.json").read_bytes(), (self.root / "licenses/third-party/manifest.json").read_bytes())
        self.assertEqual((self.destination / "Glow.exe").read_bytes(), self.launcher.read_bytes())
        self.assertEqual((self.destination / "config/neovide.toml").read_text(), 'frame = "none"\nwsl = false\n[font]\nsize = 12.5\n')
        self.assertIn("current defaults", (self.destination / "profile/config/nvim/init.lua").read_text())
        self.assertTrue((self.destination / "profile/config/nvim/init.lua").read_text().startswith("if vim.env.NEOVIDE_GLOW_INIT"))
        metadata = json.loads((self.destination / "bundle.json").read_text())
        self.assertEqual(metadata["distribution"], "core")
        self.assertEqual(metadata["tool_paths"], [])
        self.assertNotIn("runtime/python/python.exe", metadata["native_required"])
        for path, checksum in json.loads((self.destination / "bundle-sha256.json").read_text()).items():
            self.assertEqual(core.digest(self.destination / path), checksum)

    def test_changed_source_is_rejected_before_copy(self):
        (self.source / "bin/nvim.exe").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.build()
        self.assertFalse(self.destination.exists())

    def test_missing_frame_is_added_at_root_without_changing_font_settings(self):
        import tomllib
        config = self.source / "config/neovide.toml"
        content = 'wsl = false\n[font]\nsize = 12.5\n'
        config.write_text(content)
        self.checksums["config/neovide.toml"] = core.digest(config)
        (self.source / "bundle-sha256.json").write_text(json.dumps(self.checksums))
        self.build()
        result = tomllib.loads((self.destination / "config/neovide.toml").read_text())
        self.assertEqual(result, {"frame": "none", "wsl": False, "font": {"size": 12.5}})
        self.assertEqual(config.read_text(), content)

    def test_changed_plugin_lock_requires_native_rebuild(self):
        (self.payload / "nvim/lazy-lock.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "different plugin lock"):
            self.build()
        self.assertFalse(self.destination.exists())

    def test_never_adopt_existing_output_or_profile(self):
        with self.assertRaisesRegex(ValueError, "new stack"):
            self.build("old-offline")
        self.destination.mkdir()
        (self.destination / "user-file").write_text("preserved")
        with self.assertRaisesRegex(ValueError, "fresh"):
            self.build()
        self.assertEqual((self.destination / "user-file").read_text(), "preserved")

    def test_links_and_escaping_checksum_keys_rejected(self):
        target = self.source / "bin/nvim.exe"
        target.unlink()
        target.symlink_to(self.launcher)
        with self.assertRaisesRegex(ValueError, "Links"):
            self.build()
        target.unlink()
        target.write_bytes(b"nvim")
        self.checksums["../outside"] = "bad"
        (self.source / "bundle-sha256.json").write_text(json.dumps(self.checksums))
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.build()

    def test_explicit_frontend_records_provenance_and_preserves_stage(self):
        frontend = self.frontend()
        checksum = core.digest(frontend)
        report = self.build(frontend=frontend, frontend_sha256=checksum,
                            frontend_source_state="dirty", frontend_source_commit="a" * 40,
                            frontend_source_fingerprint="d" * 64)
        metadata = json.loads((self.destination / "bundle.json").read_text())
        self.assertEqual((self.destination / "bin/neovide.exe").read_bytes(), frontend.read_bytes())
        self.assertEqual((self.source / "bin/neovide.exe").read_bytes(), b"frontend")
        self.assertNotIn("neovide_commit", metadata)
        self.assertEqual(metadata["dependency_stage_neovide_commit"], "b" * 40)
        self.assertEqual(metadata["frontend_provenance"]["source_state"], "dirty")
        self.assertEqual(metadata["frontend_provenance"]["sha256"], checksum)
        self.assertEqual(report["frontend"], metadata["frontend_provenance"])
        self.assertNotIn(str(frontend), json.dumps(metadata))

    def test_frontend_override_requires_matching_hash_and_x64_pe(self):
        frontend = self.frontend()
        with self.assertRaisesRegex(ValueError, "expected SHA256"):
            self.build(frontend=frontend)
        with self.assertRaisesRegex(ValueError, "differs"):
            self.build(frontend=frontend, frontend_sha256="0" * 64)
        with self.assertRaisesRegex(ValueError, "requires a source commit"):
            self.build(frontend=frontend, frontend_sha256=core.digest(frontend), frontend_source_state="clean")
        frontend = self.frontend(machine=0xAA64)
        with self.assertRaisesRegex(ValueError, "x64"):
            self.build(frontend=frontend, frontend_sha256=core.digest(frontend))
        self.assertFalse(self.destination.exists())


if __name__ == "__main__":
    unittest.main()
