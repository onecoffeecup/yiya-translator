#!/usr/bin/env python3
"""Exercise the production release verifier with synthetic Mach-O binaries."""
import importlib.util
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("verify_release", ROOT / "scripts/verify-release.py")
verify_release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify_release)


class ReleaseBinaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="yiya-release-binary-")
        cls.directory = Path(cls.temporary.name)
        source = cls.directory / "synthetic.c"
        source.write_text("int main(void) { return 0; }\n")
        cls.binary = cls.directory / "synthetic"
        object_file = cls.directory / "synthetic.o"
        subprocess.run(["clang", "-c", "-O2", "-g", str(source), "-o", str(object_file)], check=True)
        subprocess.run(["clang", "-g", str(object_file), "-o", str(cls.binary)], check=True)
        cls.dsym = cls.directory / "synthetic.dSYM"
        subprocess.run(["dsymutil", str(cls.binary), "-o", str(cls.dsym)], check=True)
        cls.stripped = cls.directory / "stripped"
        shutil.copyfile(cls.binary, cls.stripped)
        subprocess.run(["strip", "-S", "-x", str(cls.stripped)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_app_verifier_rejects_unstripped_executable(self):
        contents = self.directory / "release/译芽.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        shutil.copyfile(self.binary, contents / "MacOS/LiveCaptionTranslator")
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.nanami.fuyi",
            "CFBundleShortVersionString": (ROOT / "VERSION").read_text().strip(),
        }))
        with self.assertRaisesRegex(ValueError, "可执行文件未 strip"):
            verify_release.main(contents.parent.parent)

    def test_stripped_executable_passes_production_symbol_check(self):
        verify_release.verify_no_debug_map(self.stripped)

    def test_post_dsym_strip_preserves_uuid_and_collected_dwarf(self):
        identifiers = []
        for path in [self.binary, self.stripped, self.dsym]:
            output = subprocess.check_output(["dwarfdump", "--uuid", str(path)], text=True)
            identifiers.append(re.findall(r"UUID: ([0-9A-F-]+) \(([^)]+)\)", output))
        self.assertTrue(identifiers[0])
        self.assertEqual(identifiers[0], identifiers[1])
        self.assertEqual(identifiers[0], identifiers[2])
        dwarf = subprocess.check_output(["dwarfdump", "--debug-info", str(self.dsym)], text=True)
        self.assertIn("DW_TAG_compile_unit", dwarf)


if __name__ == "__main__":
    unittest.main(verbosity=2)
