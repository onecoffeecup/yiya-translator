#!/usr/bin/env python3
"""Reject omitted/duplicate production units and duplicate app entry points."""
import os
import re
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent


class SourceManifestTests(unittest.TestCase):
    def manifest(self, group):
        env = dict(os.environ, ROOT_DIR=str(ROOT), FY_SOURCE_GROUP=group)
        result = subprocess.run(
            ["bash", "-c", 'source "$ROOT_DIR/scripts/lib-sources.sh"; '
             'eval \'printf "%s\\n" "${\'"$FY_SOURCE_GROUP"\'[@]}"\''],
            env=env, check=True, capture_output=True, text=True)
        return [Path(line) for line in result.stdout.splitlines()]

    def test_all_production_units_are_listed_once(self):
        sources = self.manifest("FY_APP_SOURCES")
        self.assertEqual(len(sources), len(set(sources)))
        self.assertEqual(set(sources), set((ROOT / "objc").rglob("*.m")))

    def test_test_link_units_exclude_app_entry_and_updater(self):
        sources = self.manifest("FY_APP_LINK_SOURCES")
        excluded = {ROOT / "objc/LiveCaptionTranslator.m", ROOT / "objc/FYAppUpdater.m"}
        self.assertEqual(len(sources), len(set(sources)))
        self.assertEqual(set(sources), set(self.manifest("FY_APP_SOURCES")) - excluded)

    def test_capture_card_manifest_initialization_reaches_hardware_gate(self):
        # bash -n accepts adjacent array assignments, but Bash fails when it
        # evaluates them. Exercise the entry point without accessing hardware.
        env = dict(os.environ, FY_CAPTURE_CARD_ALLOW_HARDWARE="0")
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/run-capture-card-check.sh"), "inspect"],
            env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 86, result.stdout + result.stderr)
        self.assertIn("BLOCKED:", result.stderr)

    def test_consumers_import_headers_instead_of_app_implementation(self):
        for directory in (ROOT / "tests", ROOT / "tools"):
            for path in directory.rglob("*"):
                if path.suffix in {".m", ".h"}:
                    self.assertIsNone(re.search(r'^\s*#(?:import|include)\s+"[^"\n]+\.m"',
                                               path.read_text(), re.M), str(path))

    def test_application_entry_and_headers_do_not_define_host_implementation(self):
        entry = (ROOT / "objc/LiveCaptionTranslator.m").read_text()
        self.assertNotIn("@implementation", entry)
        self.assertIn("[application run]", entry)
        for path in (ROOT / "objc/app").glob("*.h"):
            self.assertNotIn("@implementation", path.read_text(), str(path))

    def test_presentation_units_do_not_import_application_state(self):
        for path in (ROOT / "objc/presentation").glob("*.[mh]"):
            self.assertNotIn('FYAppDelegate', path.read_text(), str(path))
            self.assertNotIn('forwardingTargetForSelector', path.read_text(), str(path))

    def test_runtime_units_use_explicit_host_contracts(self):
        for path in (ROOT / "objc/runtime").glob("*.[mh]"):
            self.assertNotIn("FYAppDelegate", path.read_text(), str(path))
            self.assertNotIn("forwardingTargetForSelector", path.read_text(), str(path))


if __name__ == "__main__":
    unittest.main(verbosity=2)
