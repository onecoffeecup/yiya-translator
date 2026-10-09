#!/usr/bin/env python3
"""Exercise the real signed OCR tool with fictional input; never open hardware."""
import os
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
    def run_check(self, *args, fast=False, force_rebuild=False):
        env = dict(os.environ, FY_CAPTURE_CARD_ALLOW_HARDWARE="0")
        for key in ("FUYI_DIAG", "FY_CAPTURE_CARD_FAST_OCR", "FY_CAPTURE_CARD_FORCE_REBUILD"):
            env.pop(key, None)
        if fast:
            env["FY_CAPTURE_CARD_FAST_OCR"] = "1"
        if force_rebuild:
            env["FY_CAPTURE_CARD_FORCE_REBUILD"] = "1"
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
