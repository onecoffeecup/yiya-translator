#!/usr/bin/env python3
"""Exercise the real signed OCR tool with fictional input; never open hardware."""
import os
import hashlib
import json
import shlex
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/run-capture-card-check.sh"
IMAGE = ROOT / "tests/fixtures/replay/assets/english-dialogue.png"
EXPECTED = "Welcome to the test garden"


class CaptureCardOfflineTests(unittest.TestCase):
    def run_check(self, *args, fast=False, force_rebuild=False, open_directory=None):
        env = dict(os.environ, FY_CAPTURE_CARD_ALLOW_HARDWARE="0")
        for key in ("FUYI_DIAG", "FY_CAPTURE_CARD_FAST_OCR", "FY_CAPTURE_CARD_FORCE_REBUILD"):
            env.pop(key, None)
        if fast:
            env["FY_CAPTURE_CARD_FAST_OCR"] = "1"
        if force_rebuild:
            env["FY_CAPTURE_CARD_FORCE_REBUILD"] = "1"
        if open_directory:
            env["PATH"] = str(open_directory) + os.pathsep + env["PATH"]
        return subprocess.run(["bash", str(SCRIPT), *map(str, args)], cwd=ROOT,
                              env=env, capture_output=True, text=True, timeout=120)

    def test_accurate_ocr_and_dialogue_contain_expected_text(self):
        result = self.run_check("offline", IMAGE, EXPECTED)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("识别级别: accurate", result.stdout)
        self.assertIn(f"对白提取: {EXPECTED}", result.stdout)
        self.assertIn("\nPASS\n", result.stdout)

    def test_missing_required_substring_cannot_claim_pass(self):
        result = self.run_check("offline", IMAGE, "FY_SENTINEL_MISSING_CAPTURE_ASSERTION")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("OCR 文本缺少", result.stdout)
        self.assertIn("对白提取缺少", result.stdout)
        self.assertNotIn("\nPASS\n", result.stdout)

    def test_fast_ocr_setting_reaches_vision_tool(self):
        result = self.run_check("offline", IMAGE, EXPECTED, fast=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("识别级别: fast", result.stdout)
        self.assertIn(f"对白提取: {EXPECTED}", result.stdout)

    def test_missing_input_fails_before_tool_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_check("offline", Path(directory) / "missing.png")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("找不到", result.stderr)

    def run_with_wait_failure(self, required, launch=True):
        with tempfile.TemporaryDirectory() as directory:
            wrapper = Path(directory) / "open"
            # Keep real LaunchServices/OCR processing; fail only its wait status.
            wrapper.write_text('#!/bin/bash\n' + ('/usr/bin/open "$@"\n' if launch else '') +
                               'echo "synthetic open wait failure" >&2\nexit 1\n')
            wrapper.chmod(0o700)
            return self.run_check("offline", IMAGE, required, fast=True, open_directory=directory)

    def test_wait_failure_with_completed_real_ocr_report(self):
        result = self.run_with_wait_failure(EXPECTED)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("synthetic open wait failure", result.stderr)
        self.assertIn("识别级别: fast", result.stdout)
        self.assertIn(f"对白提取: {EXPECTED}", result.stdout)
        self.assertIn("\nPASS\n", result.stdout)

    def test_wait_failure_cannot_override_failed_real_ocr_report(self):
        result = self.run_with_wait_failure("FY_SENTINEL_MISSING_CAPTURE_ASSERTION")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("OCR 文本缺少", result.stdout)
        self.assertNotIn("\nPASS\n", result.stdout)

    def test_wait_failure_without_report_cannot_claim_pass(self):
        result = self.run_with_wait_failure(EXPECTED, launch=False)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotIn("\nPASS\n", result.stdout)

    def test_hardware_modes_remain_blocked_without_opt_in(self):
        for mode in ("inspect", "authorize", "authorize-ui", "capture"):
            with self.subTest(mode=mode):
                result = self.run_check(mode)
                self.assertEqual(result.returncode, 86, result.stdout + result.stderr)
                self.assertIn("BLOCKED:", result.stderr)

    def test_parallel_checks_keep_their_own_assertions_and_reports(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            good = pool.submit(self.run_check, "offline", IMAGE, EXPECTED, force_rebuild=True)
            bad = pool.submit(self.run_check, "offline", IMAGE, "FY_SENTINEL_MISSING_CAPTURE_ASSERTION", force_rebuild=True)
            positive, negative = good.result(), bad.result()
        self.assertEqual(positive.returncode, 0, positive.stdout + positive.stderr)
        self.assertIn("\nPASS\n", positive.stdout)
        self.assertEqual(negative.returncode, 1, negative.stdout + negative.stderr)
        self.assertIn("OCR 文本缺少", negative.stdout)
        self.assertNotIn("\nPASS\n", negative.stdout)

    def test_private_launch_copy_keeps_signed_bytes_and_byte_identical_input(self):
        with tempfile.TemporaryDirectory() as directory:
            original_hash = hashlib.sha256(IMAGE.read_bytes()).hexdigest()
            metadata = Path(directory) / "launch.json"
            observer = Path(directory) / "observe.py"
            observer.write_text('''import hashlib, json, os, stat, sys
from pathlib import Path
app = next(Path(arg) for arg in sys.argv[1:] if arg.endswith('.app'))
source = Path(os.environ['FY_EXPECTED_OCR_APP'])
exe = Path('Contents/MacOS/CaptureCardOcrCheck')
image = Path(sys.argv[sys.argv.index('--args')+1])
original = Path(os.environ['FY_EXPECTED_OCR_IMAGE'])
record = dict(private_copy=app != source,
              parent_mode=stat.S_IMODE(app.parent.stat().st_mode),
              same_binary=hashlib.sha256((app/exe).read_bytes()).digest() == hashlib.sha256((source/exe).read_bytes()).digest(),
              input_path=sys.argv[sys.argv.index('--args')+1],
              input_parent=str(image.parent),
              input_mode=stat.S_IMODE(image.stat().st_mode),
              input_parent_mode=stat.S_IMODE(image.parent.stat().st_mode),
              original_input_hash=hashlib.sha256(original.read_bytes()).hexdigest(),
              input_hash=hashlib.sha256(image.read_bytes()).hexdigest(),
              report_parent=str(Path(sys.argv[sys.argv.index('--report')+1]).parent),
              app_parent=str(app.parent))
Path(os.environ['FY_LAUNCH_METADATA']).write_text(json.dumps(record))
''')
            wrapper = Path(directory) / "open"
            wrapper.write_text('#!/bin/bash\npython3 ' + shlex.quote(str(observer)) +
                               ' "$@"\nexec /usr/bin/open "$@"\n')
            wrapper.chmod(0o700)
            env = dict(os.environ, FY_CAPTURE_CARD_ALLOW_HARDWARE="0",
                       FY_LAUNCH_METADATA=str(metadata),
                       FY_EXPECTED_OCR_APP=str(ROOT / ".build/capture-card-check/译芽采集卡离线核对.app"),
                       FY_EXPECTED_OCR_IMAGE=str(IMAGE),
                       PATH=directory + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["bash", str(SCRIPT), "offline", str(IMAGE), EXPECTED],
                                    cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("\nPASS\n", result.stdout)
            record = json.loads(metadata.read_text())
            self.assertTrue(record["private_copy"])
            self.assertEqual(record["parent_mode"], 0o700)
            self.assertTrue(record["same_binary"])
            self.assertNotEqual(record["input_path"], str(IMAGE))
            self.assertEqual(record["input_parent"], str(Path(record["app_parent"]) / "input"))
            self.assertEqual(record["input_parent_mode"], 0o700)
            self.assertEqual(record["input_mode"], 0o600)
            self.assertEqual(record["input_hash"], original_hash)
            self.assertEqual(record["original_input_hash"], original_hash)
            self.assertEqual(hashlib.sha256(IMAGE.read_bytes()).hexdigest(), original_hash)
            self.assertEqual(Path(record["input_path"]).name, IMAGE.name)
            self.assertEqual(record["report_parent"], record["app_parent"])
            self.assertFalse(Path(record["app_parent"]).exists(), "only this run's temporary copy is removed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
