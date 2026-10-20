#!/usr/bin/env python3
"""Check relocatable Python command dispatch without installed dependencies."""

from contextlib import redirect_stderr
import importlib.util
import io
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("glow_windows_tool", ROOT / "portable/windows/runtime/tool.py")
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)


class Entry:
    def __init__(self, function):
        self.function = function

    def load(self):
        return self.function


class Dispatch(unittest.TestCase):
    def test_arguments_and_exit_code(self):
        previous = sys.argv
        seen = []
        entry = Entry(lambda: seen.extend(sys.argv) or 7)
        with patch.object(tool.metadata, "entry_points", return_value=[entry]) as discover:
            self.assertEqual(tool.main(["--entry", "jupytext", "a file's 文.ipynb", "--to", "py:percent"]), 7)
        self.assertIs(sys.argv, previous)
        self.assertEqual(seen, ["jupytext", "a file's 文.ipynb", "--to", "py:percent"])
        discover.assert_called_once_with(group="console_scripts", name="jupytext")

    def test_console_system_exit_preserved(self):
        previous = sys.argv

        def exits():
            raise SystemExit(3)

        with patch.object(tool.metadata, "entry_points", return_value=[Entry(exits)]):
            with self.assertRaises(SystemExit) as result:
                tool.main(["--entry", "latex2text", "--help"])
        self.assertEqual(result.exception.code, 3)
        self.assertIs(sys.argv, previous)

    def test_missing_ambiguous_and_invalid_entry(self):
        with redirect_stderr(io.StringIO()):
            self.assertEqual(tool.main([]), 2)
            for entries in ([], [Entry(lambda: 0), Entry(lambda: 0)]):
                with patch.object(tool.metadata, "entry_points", return_value=entries):
                    self.assertEqual(tool.main(["--entry", "missing"]), 1)


if __name__ == "__main__":
    unittest.main()
