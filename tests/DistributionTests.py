#!/usr/bin/env python3
"""Exercise the public data installer with valid and hostile archives in isolation."""
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile

ROOT = Path(__file__).resolve().parent.parent


class DataInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "source with spaces"
        self.reference = self.root / "resources/learning/reference"
        (self.reference / "licenses").mkdir(parents=True)
        (self.root / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/reference-data.py", self.root / "scripts/reference-data.py")
        manifest = {"jmdict_header_dates": ["2026-10-04"], "sources": []}
        (self.reference / "reference-manifest.json").write_text(json.dumps(manifest))
        (self.reference / "README.txt").write_text("Test fixture attribution\n")
        (self.reference / "licenses/fixture.txt").write_text("Test fixture, not real dictionary data\n")
        with sqlite3.connect(self.reference / "reference.sqlite") as database:
            database.execute("CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT)")
            database.execute("INSERT INTO metadata VALUES('manifest', ?)", (json.dumps(manifest),))
        self.run_cli("create-lock", succeeds=True)
        self.run_cli("pack", succeeds=True)
        self.archive = self.root / "dist/release/fuyi-reference-20261004.zip"
        self.before = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                       for path in self.reference.iterdir() if path.is_file()}

    def run_cli(self, *args, succeeds):
        result = subprocess.run([sys.executable, str(self.root / "scripts/reference-data.py"), *map(str, args)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)
        return result

    def unchanged(self):
        for name, digest in self.before.items():
            self.assertEqual(hashlib.sha256((self.reference / name).read_bytes()).hexdigest(), digest)

    def modified_archive(self, transform):
        destination = self.root / "changed.zip"
        with zipfile.ZipFile(self.archive) as original, zipfile.ZipFile(destination, "w") as changed:
            for info in original.infolist():
                data = original.read(info)
                info, data = transform(info, data)
                if info is not None:
                    changed.writestr(info, data)
        return destination

    def test_valid_install_restores_missing_database(self):
        (self.reference / "reference.sqlite").unlink()
        self.run_cli("install", self.archive, succeeds=True)
        self.unchanged()

    def test_hash_tamper_preserves_existing_data(self):
        def corrupt(info, data):
            if info.filename == "reference/README.txt":
                data = b"X" + data[1:]
            return info, data
        result = self.run_cli("install", self.modified_archive(corrupt), succeeds=False)
        self.assertIn("校验失败", result.stderr)
        self.unchanged()

    def test_path_traversal_rejected_before_any_replace(self):
        destination = self.root / "traversal.zip"
        shutil.copyfile(self.archive, destination)
        with zipfile.ZipFile(destination, "a") as archive:
            archive.writestr("../../escaped.txt", "untrusted")
        self.run_cli("install", destination, succeeds=False)
        self.assertFalse((self.root / "escaped.txt").exists())
        self.unchanged()

    def test_symlink_rejected(self):
        def symlink(info, data):
            if info.filename == "reference/README.txt":
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
            return info, data
        self.run_cli("install", self.modified_archive(symlink), succeeds=False)
        self.unchanged()

    def test_duplicate_entry_rejected(self):
        destination = self.root / "duplicate.zip"
        shutil.copyfile(self.archive, destination)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(destination, "a") as archive:
                archive.writestr("reference/README.txt", "duplicate")
        self.run_cli("install", destination, succeeds=False)
        self.unchanged()

    def test_missing_database_rejected(self):
        def omit(info, data):
            return (None, data) if info.filename.endswith("reference.sqlite") else (info, data)
        self.run_cli("install", self.modified_archive(omit), succeeds=False)
        self.unchanged()


if __name__ == "__main__":
    unittest.main(verbosity=2)
