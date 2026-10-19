#!/usr/bin/env python3
"""Check bundled fonts and isolated user installation; never install host fonts."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('glow_installer', ROOT / 'portable/scripts/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
PAYLOAD = ROOT / 'portable/payload'


class Fonts(unittest.TestCase):
    def make_installer(self, temporary, mac):
        instance = installer.Installer.__new__(installer.Installer)
        instance.payload = PAYLOAD
        instance.root = temporary / 'stack'
        instance.meta = instance.root / '.installer'
        instance.is_mac = mac
        return instance

    def test_shipped_fonts_and_notices(self):
        for platform, count in (('macos', 6), ('windows', 8), ('linux', 8)):
            with self.subTest(platform=platform):
                fonts = installer.bundled_font_files(PAYLOAD / 'fonts', platform)
                self.assertEqual(len(fonts), count)
                self.assertEqual(sum(p.name.startswith('Noto') for p in fonts), 0 if platform == 'macos' else 2)

    def test_install_for_each_platform_and_preserve_duplicates(self):
        for mac in (True, False):
            with self.subTest(mac=mac), tempfile.TemporaryDirectory(prefix='glow-fonts-') as work:
                temporary = Path(work)
                home = temporary / 'home'
                instance = self.make_installer(temporary, mac)
                with patch.object(Path, 'home', return_value=home), patch.dict('os.environ', {'XDG_DATA_HOME': str(home / 'data')}), patch.object(installer.shutil, 'which', return_value=None):
                    instance.install_fonts()
                    fonts = installer.bundled_font_files(PAYLOAD / 'fonts', 'macos' if mac else 'linux')
                    destination = instance.user_font_directory()
                    self.assertEqual(len(list(destination.glob('*'))), len(fonts))
                    for font in fonts:
                        self.assertEqual(installer.sha(destination / font.name), installer.sha(font))
                    # A second run keeps identical files and preserves a user's replacement.
                    instance.install_fonts()
                    duplicate = destination / fonts[-1].name
                    duplicate.write_bytes(b'user-owned font')
                    with self.assertRaises(installer.InstallError):
                        instance.install_fonts()
                    self.assertEqual(duplicate.read_bytes(), b'user-owned font')

    def test_conflict_preflight_writes_no_other_fonts(self):
        with tempfile.TemporaryDirectory(prefix='glow-font-conflict-') as work:
            temporary = Path(work)
            instance = self.make_installer(temporary, True)
            home = temporary / 'home'
            with patch.object(Path, 'home', return_value=home):
                destination = instance.user_font_directory()
                destination.mkdir(parents=True)
                files = installer.bundled_font_files(PAYLOAD / 'fonts', 'macos')
                (destination / files[-1].name).write_bytes(b'existing font')
                with self.assertRaises(installer.InstallError):
                    instance.install_fonts()
                self.assertEqual(len(list(destination.iterdir())), 1)
                self.assertFalse(instance.root.exists())

    def test_reject_corrupt_payload_before_copy(self):
        with tempfile.TemporaryDirectory(prefix='glow-font-corrupt-') as work:
            temporary = Path(work)
            source = temporary / 'payload/fonts'
            shutil.copytree(PAYLOAD / 'fonts', source)
            metadata = json.loads((source / 'fonts.json').read_text())
            (source / metadata['fonts'][0]['filename']).write_bytes(b'corrupt')
            instance = self.make_installer(temporary, True)
            instance.payload = temporary / 'payload'
            with patch.object(Path, 'home', return_value=temporary / 'home'):
                with self.assertRaises(installer.InstallError):
                    instance.install_fonts()
                self.assertFalse((temporary / 'home').exists())
                self.assertFalse(instance.root.exists())


if __name__ == '__main__':
    unittest.main()
