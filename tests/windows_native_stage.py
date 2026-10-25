#!/usr/bin/env python3
"""Synthetic native-source preparation checks; no Windows processes or installs."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "portable/windows/prepare-native-stage.py"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


stage = load("prepare_native_stage", SCRIPT)
pe = load("stage_pe_fixture", REPO / "tests/windows_native_package.py").pe


class NativeStage(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.source, self.output = self.root / "base", self.root / "prepared"
        self.plugin = "profile/data/nvim/lazy/plugin/build/native.dll"
        self.parser = "profile/data/nvim/lazy/nvim-treesitter/parser/lua.so"
        self.files = {
            "bin/neovide.exe": pe(), "bin/nvim.exe": pe(), "bin/cmatrix-gm.exe": pe(),
            "bin/obsolete-x64.dll": pe(), "share/nvim/runtime/filetype.lua": b"old runtime",
            "share/nvim/runtime/obsolete.lua": b"old runtime file",
            "lib/nvim/old-support.txt": b"old support",
            "config/neovide.toml": b'frame="none"\n',
            "profile/config/nvim/init.lua": b"-- immutable template\n",
            "profile/config/nvim/lazy-lock.json": b'{"plugin":"frozen"}',
            self.plugin: pe(), self.parser: pe(), "fonts/font.ttf": b"font",
            "licenses/notice.txt": b"notice", "runtime/python/python.exe": pe(),
        }
        for name, content in self.files.items():
            self.write(self.source / name, content)
        self.metadata = {"schema_version": 1, "stack_id": "legacy-x64", "distribution": "offline",
                         "neovide_commit": "a" * 40, "frontend_provenance": {"architecture": "x86_64"},
                         "native_gui_acceptance": "old-x64-only",
                         "native_required": [self.plugin, self.parser, "runtime/python/python.exe"],
                         "tool_paths": ["runtime/python"]}
        self.reseal()
        self.inputs = {"schema_version": 1, "architecture": "arm64", "stack_id": "fixture-arm64-stage",
                       "base_seal_sha256": stage.core.digest(self.source / "bundle-sha256.json"),
                       "replace_prefixes": ["bin/", "share/nvim/", "lib/nvim/"], "files": []}
        for name, content in {
            "bin/neovide.exe": pe(machine=0xAA64, imports=["MSVCP140.dll"]),
            "bin/nvim.exe": pe(machine=0xAA64), "bin/cmatrix-gm.exe": pe(machine=0xAA64),
            "bin/msvcp140.dll": pe(machine=0xAA64),
            "share/nvim/runtime/filetype.lua": b"new ARM runtime", "lib/nvim/support.txt": b"new support",
            self.plugin: pe(machine=0xAA64), self.parser: pe(machine=0xAA64),
        }.items():
            self.overlay(name, content)

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def reseal(self):
        self.write(self.source / "bundle.json", json.dumps(self.metadata).encode())
        sealed = {p.relative_to(self.source).as_posix(): stage.core.digest(p)
                  for p in self.source.rglob("*") if p.is_file() and p.name != "bundle-sha256.json"}
        self.write(self.source / "bundle-sha256.json", json.dumps(sealed).encode())

    def overlay(self, name, content):
        source = self.root / "overlay" / name
        self.write(source, content)
        self.inputs["files"].append({"path": name, "source": str(source),
                                    "sha256": stage.core.digest(source), "source_kind": "verified-arm64-fixture"})

    def prepare(self, inputs=None):
        return stage.prepare(self.source, self.output, self.inputs if inputs is None else inputs)

    def rejected(self, text):
        with self.assertRaisesRegex(stage.PreparationError, text):
            self.prepare()
        self.assertFalse((self.output / "bundle-sha256.json").exists(), "Failure must never produce a valid seal")

    def test_native_overlay_seals_relative_provenance_and_preserves_base(self):
        before = {p.relative_to(self.source): p.read_bytes() for p in self.source.rglob("*") if p.is_file()}
        report = self.prepare()
        self.assertEqual(report["state"], "sealed_native_core_source")
        self.assertEqual(report["native_verification"]["status"], "passed")
        metadata = json.loads((self.output / "bundle.json").read_text())
        self.assertEqual(metadata["architecture"], "arm64")
        self.assertEqual(metadata["preparation"], "verified-native-core-source")
        self.assertEqual(metadata["distribution"], "offline")
        for name in ("neovide_commit", "frontend_provenance", "native_gui_acceptance"):
            self.assertNotIn(name, metadata)
        self.assertNotIn(str(self.root), (self.output / "bundle.json").read_text())
        self.assertNotIn("runtime/python/python.exe", metadata["native_required"])
        for name in [self.plugin, self.parser, "bin/cmatrix-gm.exe", "bin/msvcp140.dll"]:
            self.assertIn(name, metadata["native_required"])
        for name in ["bin/obsolete-x64.dll", "share/nvim/runtime/obsolete.lua", "lib/nvim/old-support.txt", "runtime/python"]:
            self.assertFalse((self.output / name).exists())
        seal = json.loads((self.output / "bundle-sha256.json").read_text())
        for name, digest in seal.items():
            self.assertEqual(stage.core.digest(self.output / name), digest)
        for name, content in before.items():
            self.assertEqual((self.source / name).read_bytes(), content)

    def test_unreplaced_old_native_plugin_is_rejected_before_output(self):
        self.inputs["files"] = [f for f in self.inputs["files"] if f["path"] != self.plugin]
        self.rejected("Explicit native replacement")
        self.assertFalse(self.output.exists())

    def test_wrong_base_seal_and_tampered_bundle_are_rejected(self):
        self.inputs["base_seal_sha256"] = "0" * 64
        self.rejected("base seal SHA256")
        self.inputs["base_seal_sha256"] = stage.core.digest(self.source / "bundle-sha256.json")
        self.write(self.source / "bundle.json", b'{"schema_version":1,"stack_id":"changed"}')
        self.rejected("bundle.json")

    def test_tampered_retained_resource_is_rejected(self):
        self.write(self.source / "fonts/font.ttf", b"tampered")
        self.rejected("checksum differs")

    def test_wrong_overlay_hash_or_architecture_cannot_seal(self):
        self.inputs["files"][0]["sha256"] = "0" * 64
        self.rejected("Overlay SHA256")
        entry = self.inputs["files"][0]
        self.write(Path(entry["source"]), pe())
        entry["sha256"] = stage.core.digest(Path(entry["source"]))
        self.rejected("PE architecture differs")

    def test_matrix_and_node_native_architecture_are_checked(self):
        matrix = next(f for f in self.inputs["files"] if f["path"] == "bin/cmatrix-gm.exe")
        self.write(Path(matrix["source"]), pe())
        matrix["sha256"] = stage.core.digest(Path(matrix["source"]))
        self.rejected("bin/cmatrix-gm.exe")
        self.write(Path(matrix["source"]), pe(machine=0xAA64))
        matrix["sha256"] = stage.core.digest(Path(matrix["source"]))
        self.overlay("profile/data/nvim/lazy/plugin/addon.node", pe())
        self.rejected("addon.node")

    def test_missing_crt_fails_native_gate_and_leaves_no_seal(self):
        self.inputs["files"] = [f for f in self.inputs["files"] if f["path"] != "bin/msvcp140.dll"]
        self.rejected("Missing or ambiguous app-local MSVC CRT")
        self.assertTrue((self.output / "bundle.json").exists())

    def test_overlay_paths_reject_traversal_private_and_duplicates(self):
        good = copy.deepcopy(self.inputs)
        for bad in ("../outside.dll", "bin\\outside.dll", "profile/config/nvim/.env", "profile/config/nvim/.git/config"):
            with self.subTest(path=bad):
                self.inputs = copy.deepcopy(good)
                self.inputs["files"][0]["path"] = bad
                self.rejected("Unsafe|Private")
        self.inputs = copy.deepcopy(good)
        self.inputs["files"].append(copy.deepcopy(self.inputs["files"][0]))
        self.rejected("unique")

    def test_absolute_sources_and_nonprivate_origin_labels_required(self):
        original = copy.deepcopy(self.inputs)
        self.inputs["files"][0]["source"] = "relative.exe"
        self.rejected("absolute")
        self.inputs = original
        self.inputs["files"][0]["source_kind"] = "C:\\private\\source.exe"
        self.rejected("origin label")

    def test_source_and_overlay_symlinks_are_rejected(self):
        entry = self.inputs["files"][0]
        path = Path(entry["source"])
        target = self.root / "outside.exe"
        path.rename(target)
        path.symlink_to(target)
        self.rejected("Links")

    def test_existing_output_and_shared_stack_are_preserved(self):
        self.inputs["stack_id"] = "legacy-x64"
        self.rejected("independent stack_id")
        self.inputs["stack_id"] = "fixture-arm64-stage"
        self.output.mkdir()
        (self.output / "keep.txt").write_text("preserved")
        self.rejected("fresh")
        self.assertEqual((self.output / "keep.txt").read_text(), "preserved")

    def test_cli_writes_local_report_and_nonzero_failure(self):
        manifest, report = self.root / "inputs.json", self.root / "report.json"
        manifest.write_text(json.dumps(self.inputs))
        command = [sys.executable, "-I", "-B", str(SCRIPT), "--source", str(self.source),
                   "--destination", str(self.output), "--inputs", str(manifest), "--report", str(report)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(json.loads(report.read_text())["state"], "sealed_native_core_source")
        report.unlink()
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(report.read_text())["state"], "failed")

    def add_sealed_external(self, name, content):
        self.write(self.source / name, content)
        self.reseal()
        self.inputs["base_seal_sha256"] = stage.core.digest(self.source / "bundle-sha256.json")
        self.inputs.setdefault("sealed_external_files", []).append({"path": name, "sha256": stage.core.digest(self.source / name)})

    def test_explicit_copilot_external_assets_keep_multiplatform_bytes_out_of_editor_abi(self):
        prefix = "profile/data/nvim/lazy/copilot.lua/copilot/js/"
        for name, data in [("crypt32.node", pe()), ("compiled/linux/x64/addon.node", b"\x7fELFfixture"),
                           ("bin/win32/x64/rg.exe", pe())]:
            self.add_sealed_external(prefix + name, data)
        report = self.prepare()
        self.assertEqual(len(report["sealed_external_files"]), 3)
        metadata = json.loads((self.output / "bundle.json").read_text())
        for entry in self.inputs["sealed_external_files"]:
            self.assertEqual(stage.core.digest(self.output / entry["path"]), entry["sha256"])
            self.assertNotIn(entry["path"], metadata["native_required"])
        self.assertIn("not native editor ABI", report["external_runtime_assets_acceptance"])

    def test_external_exceptions_cannot_bypass_editor_dll_or_base_hash(self):
        self.inputs["sealed_external_files"] = [{"path": self.plugin, "sha256": stage.core.digest(self.source / self.plugin)}]
        self.rejected("limited to unique Copilot")
        name = "profile/data/nvim/lazy/copilot.lua/copilot/js/crypt32.node"
        self.inputs["sealed_external_files"] = []
        self.add_sealed_external(name, pe())
        self.inputs["sealed_external_files"][0]["sha256"] = "0" * 64
        self.rejected("match the retained base seal")

    def test_test_fixtures_removed_only_by_explicit_prefix_and_undeclared_pe_still_rejected(self):
        name = "profile/data/nvim/lazy/LuaSnip/tests/parsers/json.so"
        self.write(self.source / name, b"\x7fELFfixture")
        self.reseal()
        self.inputs["base_seal_sha256"] = stage.core.digest(self.source / "bundle-sha256.json")
        self.rejected("Explicit native replacement")
        self.inputs["replace_prefixes"].append("profile/data/nvim/lazy/LuaSnip/tests/")
        report = self.prepare()
        self.assertEqual(report["native_verification"]["status"], "passed")
        self.assertFalse((self.output / name).exists())


if __name__ == "__main__":
    unittest.main()
