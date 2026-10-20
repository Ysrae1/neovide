#!/usr/bin/env python3
"""Exercise Mason relocation on fixtures; execute private Python entry points."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("relocate_mason", ROOT / "portable/windows/relocate-mason.py")
relocator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(relocator)


class Relocation(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="glow-mason-relocate-")
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.stage = self.work / "stage"
        self.mason = self.stage / "profile/data/nvim/mason"
        (self.stage / "runtime/python").mkdir(parents=True)
        (self.stage / "runtime/python/python.exe").write_bytes(b"fixture interpreter")
        shutil.copy2(ROOT / "portable/windows/runtime/mason_tool.py", self.stage / "runtime/mason_tool.py")
        self.old_root = r"D:\worker\bundle\profile\data\nvim-data\mason\packages"

    def package(self, name, source, links):
        package = self.mason / "packages" / name
        package.mkdir(parents=True)
        receipt = {"schema_version": "1.1", "primary_source": {"id": source, "type": "registry+v1"}, "links": {"bin": links}}
        (package / "mason-receipt.json").write_text(json.dumps(receipt))
        for command, relative in links.items():
            output = self.mason / "bin" / (command if command.endswith(".cmd") else command + ".cmd")
            output.parent.mkdir(parents=True, exist_ok=True)
            absolute = self.old_root + "\\" + name + "\\" + relative.replace("/", "\\")
            output.write_text('@echo off\n"' + absolute + '" %*\n')
        return package

    def distribution(self, package, name, version, entries=""):
        site = package / "venv/Lib/site-packages"
        info = site / (name.replace("-", "_") + "-" + version + ".dist-info")
        info.mkdir(parents=True)
        (info / "METADATA").write_text(f"Metadata-Version: 2.1\nName: {name}\nVersion: {version}\n")
        (info / "entry_points.txt").write_text("[console_scripts]\n" + entries)
        return site

    @staticmethod
    def distlib(path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"MZfixture interpreter shebang D:\\worker\\bundle\\stage\\runtime\\python\\python.exe\n")
        with zipfile.ZipFile(path, "a") as zipped:
            zipped.writestr("__main__.py", "# unused distlib entry point\n")

    def test_private_python_entry_survives_profile_and_install_moves(self):
        package = self.package("black", "pkg:pypi/black@25.1.0", {"black.cmd": "venv/Scripts/black.exe"})
        site = self.distribution(package, "black", "25.1.0", "black = glow_fixture:main\n")
        (site / "glow_fixture.py").write_text("import json,os,sys\ndef main():\n print(json.dumps({'args':sys.argv[1:],'private':os.environ['PYTHONPATH']}));return 7\n")
        self.distlib(package / "venv/Scripts/black.exe")
        (package / "venv/Scripts/python.exe").write_bytes(b"old venv python")
        (package / "venv/pyvenv.cfg").write_text("home = D:\\worker\\bundle\\stage\\runtime\\python\n")
        result = relocator.relocate(self.stage)
        self.assertEqual(result["commands"][0]["kind"], "python")
        self.assertFalse((package / "venv/Scripts/black.exe").exists())
        self.assertFalse((package / "venv/pyvenv.cfg").exists())
        wrapper = (self.mason / "bin/black.cmd").read_text()
        self.assertIn(r"%~dp0..\packages\black", wrapper)
        self.assertIn("--entry \"black\" -- %*", wrapper)
        self.assertNotIn("D:\\worker", wrapper)
        moved = self.work / "moved install's 中文"
        shutil.move(self.stage, moved)
        moved_package = moved / "profile/data/nvim/mason/packages/black"
        run = subprocess.run([sys.executable, str(moved / "runtime/mason_tool.py"), "--package", str(moved_package),
                              "--entry", "black", "--", "a file's 文.py", "--package", "literal"],
                             capture_output=True, text=True, timeout=10)
        self.assertEqual(run.returncode, 7, run.stderr)
        output = json.loads(run.stdout)
        self.assertEqual(output["args"], ["a file's 文.py", "--package", "literal"])
        self.assertEqual(Path(output["private"]), (moved_package / "venv/Lib/site-packages").resolve())
        receipt = json.loads((moved_package / "mason-receipt.json").read_text())
        self.assertEqual(receipt["links"]["bin"]["black.cmd"], "venv/Scripts/black.cmd")
        self.assertEqual(receipt["primary_source"]["id"], "pkg:pypi/black@25.1.0")

    def test_debugpy_module_and_native_ruff(self):
        debug = self.package("debugpy", "pkg:pypi/debugpy@1.8.12", {"debugpy.cmd": "debugpy.cmd"})
        site = self.distribution(debug, "debugpy", "1.8.12")
        module = site / "debugpy"
        module.mkdir()
        (module / "__init__.py").write_text("")
        (module / "__main__.py").write_text("import json,sys\nprint(json.dumps(sys.argv[1:]))\nraise SystemExit(4)\n")
        (debug / "debugpy.cmd").write_text('@echo off\n"D:\\worker\\bundle\\profile\\data\\nvim-data\\mason\\packages\\debugpy\\venv\\Scripts\\python" -m debugpy %*\n')
        ruff = self.package("ruff", "pkg:pypi/ruff@0.9.6", {"ruff.cmd": "venv/Scripts/ruff.exe"})
        self.distribution(ruff, "ruff", "0.9.6")
        native = ruff / "venv/Scripts/ruff.exe"
        native.parent.mkdir(parents=True)
        native.write_bytes(b"MZnative Rust image")
        result = relocator.relocate(self.stage)
        self.assertEqual({item["command"]: item["kind"] for item in result["commands"]}, {"debugpy.cmd": "python", "ruff.cmd": "native"})
        self.assertTrue(native.exists())
        run = subprocess.run([sys.executable, str(self.stage / "runtime/mason_tool.py"), "--package", str(debug),
                              "--module", "debugpy", "--", "--listen", "12345"], capture_output=True, text=True, timeout=10)
        self.assertEqual(run.returncode, 4, run.stderr)
        self.assertEqual(json.loads(run.stdout), ["--listen", "12345"])

    def test_distlib_stripped_py_suffix_uses_original_metadata_name(self):
        package = self.package("clang-format", "pkg:pypi/clang-format@19.1.7", {"clang-format-diff.py.cmd": "venv/Scripts/clang-format-diff.exe"})
        self.distribution(package, "clang-format", "19.1.7", "clang-format-diff.py = fixture:main\n")
        self.distlib(package / "venv/Scripts/clang-format-diff.exe")
        result = relocator.relocate(self.stage)
        self.assertEqual(result["commands"][0]["entry"], "clang-format-diff.py")
        self.assertIn('--entry "clang-format-diff.py"', (self.mason / "bin/clang-format-diff.py.cmd").read_text())

    def test_node_absolute_shim_becomes_relative(self):
        package = self.package("pyright", "pkg:npm/pyright@1.1.414", {"pyright.cmd": "node_modules/.bin/pyright.cmd"})
        target = package / "node_modules/.bin/pyright.cmd"
        target.parent.mkdir(parents=True)
        target.write_text('@echo off\nnode "' + self.old_root + r'\pyright\node_modules\pyright\index.js' + '" %*\n')
        relocator.relocate(self.stage)
        self.assertIn(r'%~dp0..\..\node_modules\pyright\index.js', target.read_text())
        self.assertNotIn("D:\\worker", target.read_text())
        self.assertIn(r'%~dp0..\packages\pyright\node_modules\.bin\pyright.cmd', (self.mason / "bin/pyright.cmd").read_text())

    def test_unresolved_powershell_and_escaping_targets_are_rejected(self):
        package = self.package("tool", "pkg:npm/tool@1", {"tool.cmd": "tool.cmd"})
        (package / "tool.cmd").write_text("@echo off\nnode relative.js %*\n")
        (package / "tool.ps1").write_text("& '" + self.old_root + "\\tool\\old.js'\n")
        with self.assertRaises(relocator.RelocationError):
            relocator.relocate(self.stage)
        with self.assertRaises(relocator.RelocationError):
            relocator.relocate(self.stage)
        (package / "tool.ps1").unlink()
        receipt = json.loads((package / "mason-receipt.json").read_text())
        receipt["links"]["bin"] = {"escape.cmd": "../../outside.exe"}
        (package / "mason-receipt.json").write_text(json.dumps(receipt))
        with self.assertRaises(relocator.RelocationError):
            relocator.relocate(self.stage)

    def test_runtime_rejects_global_entry_and_wrong_pinned_version(self):
        package = self.package("black", "pkg:pypi/black@25.1.0", {})
        self.distribution(package, "black", "25.1.0")
        command = [sys.executable, str(self.stage / "runtime/mason_tool.py"), "--package", str(package), "--entry", "pip"]
        run = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(run.returncode, 1)
        self.assertIn("missing or ambiguous", run.stderr)
        receipt = json.loads((package / "mason-receipt.json").read_text())
        receipt["primary_source"]["id"] = "pkg:pypi/black@99.0.0"
        (package / "mason-receipt.json").write_text(json.dumps(receipt))
        run = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(run.returncode, 1)
        self.assertIn("missing or ambiguous", run.stderr)


if __name__ == "__main__":
    unittest.main()
