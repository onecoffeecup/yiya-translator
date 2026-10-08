#!/usr/bin/env python3
"""Run a deliberately wrong assertion through the native pipeline and inspect failure evidence."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ReplayFailureReportingTests(unittest.TestCase):
    def test_product_assertion_failure_has_expected_actual_and_nonzero_exit(self):
        with tempfile.TemporaryDirectory(prefix="yiya-replay-failure-") as directory:
            root = Path(directory)
            scenario = json.loads((ROOT / "tests/fixtures/replay/stationary-dialogue.json").read_text())
            scenario["steps"][0]["expect"] = {"requests": 99}
            fixture, output = root / "fixture.json", root / "report.json"
            fixture.write_text(json.dumps(scenario))
            run = subprocess.run([str(ROOT / ".build/replay/ReplayTests"), str(fixture), str(output)],
                                 cwd=ROOT, capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 1)
            result = json.loads(output.read_text())
            self.assertEqual(result["status"], "failed")
            self.assertEqual(result["failure"]["step"], 0)
            self.assertEqual(result["failure"]["expected"], 99)
            self.assertEqual(result["failure"]["actual"], 0)
            self.assertTrue(result["checkpoints"])
            self.assertNotIn("REPLAY_SYNTHETIC_CREDENTIAL", output.read_text())
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main(verbosity=2)
