#!/usr/bin/env python3
"""Native-stage gate: synthetic PE images only, no Windows, download or install."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "portable/windows/verify-native.py"
SPEC = importlib.util.spec_from_file_location("verify_native", SCRIPT)
native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(native)


def pe(machine=0x8664, imports=(), delay_imports=(), delay_rva=True):
    """One mapped section with real import descriptor/name layouts, no code."""
    data = bytearray(0x1200)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<HH", data, 0x84, machine, 1)
    struct.pack_into("<H", data, 0x94, 240)
    optional = 0x98
    struct.pack_into("<H", data, optional, 0x20B)
    image_base = 0x400000
    struct.pack_into("<Q", data, optional + 24, image_base)
    struct.pack_into("<I", data, optional + 60, 0x200)
    struct.pack_into("<I", data, optional + 108, 16)
    section = optional + 240
    data[section:section + 8] = b".rdata\0\0"
    struct.pack_into("<IIII", data, section + 8, 0x1000, 0x1000, 0x1000, 0x200)
    name_offset = 0x600
    for directory, start, stride, names in ((1, 0x200, 20, imports), (13, 0x400, 32, delay_imports)):
        if not names:
            continue
        struct.pack_into("<II", data, optional + 112 + directory * 8,
                         0x1000 + start - 0x200, stride * (len(names) + 1))
        for index, name in enumerate(names):
            encoded = name.encode("ascii") + b"\0"
            data[name_offset:name_offset + len(encoded)] = encoded
            name_rva = 0x1000 + name_offset - 0x200
            if directory == 1:
                struct.pack_into("<IIIII", data, start + stride * index, 1, 0, 0, name_rva, 1)
            else:
                address = name_rva if delay_rva else name_rva + image_base
                struct.pack_into("<IIIIIIII", data, start + stride * index,
                                 int(delay_rva), address, 0, 0, 0, 0, 0, 0)
            name_offset += len(encoded)
    return bytes(data)


class NativePackage(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.stage = self.root / "stage"
        self.stage.mkdir()
        self.plugin = "profile/data/nvim/lazy/plugin/build/native.dll"
        self.metadata = {"stack_id": "隔离测试", "native_required": [self.plugin]}
        self.write("bundle.json", json.dumps(self.metadata, ensure_ascii=False).encode("utf-8"))
        self.write("bin/neovide.exe", pe(imports=["KERNEL32.dll", "MSVCP140.dll"]))
        self.write("bin/nvim.exe", pe())
        self.write(self.plugin, pe())
        self.write("bin/msvcp140.dll", pe(imports=["VCRUNTIME140.dll", "api-ms-win-crt-runtime-l1-1-0.dll"]))
        self.write("bin/vcruntime140.dll", pe(delay_imports=["VCRUNTIME140_1.dll"]))
        self.write("bin/vcruntime140_1.dll", pe(imports=["ucrtbase.dll", "KERNEL32.dll"]))

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, name, data):
        path = self.stage / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def verify(self, architecture="x64"):
        return native.verify_stage(self.stage, architecture)

    def assert_failed(self, text):
        report = self.verify()
        self.assertEqual(report["status"], "failed", report)
        self.assertIn(text, "\n".join(report["errors"]))
        return report

    def test_x64_closes_recursive_crt_and_records_hashes(self):
        report = self.verify()
        self.assertEqual(report["status"], "passed", report["errors"])
        self.assertEqual(report["stack_id"], "隔离测试")
        self.assertEqual(len(report["files"]), 6)
        self.assertEqual(len(report["crt_dependencies"]), 3)
        for record in report["files"]:
            self.assertEqual(record["sha256"], hashlib.sha256((self.stage / record["path"]).read_bytes()).hexdigest())
        self.assertEqual(report["crt_dependencies"][-1]["kind"], "delay_import")

    def test_native_arm64_has_its_own_architecture_result(self):
        for path in self.stage.rglob("*"):
            if path.is_file() and path.suffix in {".exe", ".dll"}:
                data = bytearray(path.read_bytes())
                struct.pack_into("<H", data, 0x84, 0xAA64)
                path.write_bytes(data)
        report = self.verify("arm64")
        self.assertEqual(report["status"], "passed", report["errors"])
        self.assertTrue(all(record["machine"] == "0xaa64" for record in report["files"]))

    def test_auxiliary_exe_does_not_imply_native_editor_abi(self):
        self.write("runtime/python/python.exe", pe(machine=0xAA64))
        self.metadata["native_required"].append("runtime/python/python.exe")
        self.write("bundle.json", json.dumps(self.metadata).encode())
        self.assertEqual(self.verify()["status"], "passed")

    def test_missing_direct_crt_is_not_satisfied_by_other_directory(self):
        original = self.stage / "bin/msvcp140.dll"
        self.write("other/MSVCP140.dll", original.read_bytes())
        original.unlink()
        self.assert_failed("MSVCP140.dll")

    def test_missing_recursive_delay_crt_fails(self):
        (self.stage / "bin/vcruntime140_1.dll").unlink()
        self.assert_failed("VCRUNTIME140_1.dll")

    def test_frontend_delay_imports_are_checked(self):
        self.write("bin/neovide.exe", pe(delay_imports=["VCRUNTIME140_1.dll"]))
        (self.stage / "bin/vcruntime140_1.dll").unlink()
        self.assert_failed("VCRUNTIME140_1.dll")

    def test_legacy_delay_import_virtual_addresses(self):
        self.write("bin/neovide.exe", pe(delay_imports=["MSVCP140.dll"], delay_rva=False))
        self.assertEqual(self.verify()["status"], "passed")

    def test_wrong_architecture_in_each_required_kind(self):
        for relative in ("bin/neovide.exe", "bin/nvim.exe", self.plugin, "bin/vcruntime140_1.dll"):
            with self.subTest(path=relative):
                original = (self.stage / relative).read_bytes()
                data = bytearray(original)
                struct.pack_into("<H", data, 0x84, 0xAA64)
                self.write(relative, data)
                self.assert_failed("Wrong PE architecture: " + relative)
                self.write(relative, original)

    def test_parser_so_is_also_checked_as_pe(self):
        parser = "profile/data/nvim/lazy/nvim-treesitter/parser/lua.so"
        self.write(parser, pe(machine=0xAA64))
        self.metadata["native_required"].append(parser)
        self.write("bundle.json", json.dumps(self.metadata).encode())
        self.assert_failed("Wrong PE architecture: " + parser)

    def test_only_frontend_snapshot_is_not_a_complete_stage(self):
        (self.stage / "bundle.json").unlink()
        (self.stage / "bin/nvim.exe").unlink()
        report = self.assert_failed("bundle.json")
        self.assertTrue(any("bin/nvim.exe" in error for error in report["errors"]))

    def test_missing_native_declaration_is_rejected(self):
        self.metadata["native_required"] = ["bin/neovide.exe", "bin/nvim.exe"]
        self.write("bundle.json", json.dumps(self.metadata).encode())
        self.assert_failed("including native DLLs/parsers")

    def test_manifest_paths_cannot_escape_or_use_windows_separators(self):
        for relative in ("../outside.dll", "/outside.dll", "C:/outside.dll", "bin\\outside.dll", "bin/../outside.dll"):
            with self.subTest(path=relative):
                self.metadata["native_required"] = [self.plugin, relative]
                self.write("bundle.json", json.dumps(self.metadata).encode())
                self.assert_failed("Unsafe native payload path")

    def test_crt_symlink_cannot_supply_external_bytes(self):
        target = self.root / "outside.dll"
        path = self.stage / "bin/msvcp140.dll"
        target.write_bytes(path.read_bytes())
        path.unlink()
        path.symlink_to(target)
        self.assert_failed("Links are not permitted")

    def test_native_parent_symlink_cannot_supply_external_bytes(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "native.dll").write_bytes(pe())
        (self.stage / "linked").symlink_to(outside, target_is_directory=True)
        self.metadata["native_required"].append("linked/native.dll")
        self.write("bundle.json", json.dumps(self.metadata).encode())
        self.assert_failed("Links are not permitted")

    def test_import_names_cannot_escape_directory(self):
        self.write("bin/neovide.exe", pe(imports=["../MSVCP140.dll"]))
        self.assert_failed("Unsafe PE import name")

    def test_truncated_pe_or_unmapped_import_directory_fails(self):
        self.write("bin/nvim.exe", b"MZ")
        self.assert_failed("missing MZ header")
        self.write("bin/nvim.exe", pe())
        data = bytearray(pe(imports=["MSVCP140.dll"]))
        struct.pack_into("<I", data, 0x98 + 112 + 8, 0xFFFF0000)
        self.write("bin/neovide.exe", data)
        self.assert_failed("PE RVA is unmapped")

    def test_cli_report_and_nonzero_failure_are_machine_readable(self):
        report_path = self.root / "report.json"
        for expected in (0, 1):
            result = subprocess.run([sys.executable, "-I", "-B", str(SCRIPT), "--stage", str(self.stage),
                                     "--architecture", "x64", "--report", str(report_path)],
                                    capture_output=True, text=True, encoding="utf-8", timeout=15)
            self.assertEqual(result.returncode, expected, result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report, json.loads(result.stdout))
            if expected == 0:
                (self.stage / "bin/nvim.exe").unlink()


if __name__ == "__main__":
    unittest.main()
