#!/usr/bin/env python3
"""Runner boundary regressions: reject unsafe/incomplete Replay and report evidence accurately."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("debug", ROOT / "scripts/debug.py")
debug = importlib.util.module_from_spec(spec)
spec.loader.exec_module(debug)


class DebugInfrastructureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "fixture.json"
        self.base = json.loads((debug.FIXTURES / "stationary-dialogue.json").read_text())

    def validate(self, data):
        self.path.write_text(json.dumps(data))
        return debug.validate(self.path)

    def test_repository_scenarios_have_real_assertions(self):
        for path in debug.FIXTURES.glob("*.json"):
            with self.subTest(path=path.name):
                debug.validate(path)

    def test_missing_assertions_and_draft_cannot_claim_pass(self):
        for data in (dict(self.base, draft=True), dict(self.base, steps=[dict(step, expect={}) for step in self.base["steps"]])):
            with self.assertRaises(ValueError):
                self.validate(data)

    def test_bad_time_and_unknown_operations_rejected_before_native_run(self):
        for change in ({"at_ms": -1}, {"at_ms": float("nan")}, {"action": "network"}, {"token": "SYNTHETIC_SECRET"}, {"expect": {"requestz": 1}}):
            data = copy.deepcopy(self.base)
            data["steps"][0].update(change)
            with self.assertRaises(ValueError):
                self.validate(data)
        data = copy.deepcopy(self.base)
        data["steps"][2]["at_ms"] = 10
        with self.assertRaises(ValueError):
            self.validate(data)

    def test_invalid_coordinates_and_response_index_rejected(self):
        data = copy.deepcopy(self.base)
        data["steps"][0]["blocks"] = [{"text": "fictional", "box": [0, 0, 2, 1]}]
        with self.assertRaises(ValueError):
            self.validate(data)
        data["steps"][0] = {"at_ms": 0, "action": "release", "request": 99, "expect": {"requests": 0}}
        with self.assertRaises(ValueError):
            self.validate(data)

    def test_media_must_be_existing_local_input(self):
        data = copy.deepcopy(self.base)
        data["steps"][0]["image"] = "https://example.invalid/screen.png"
        with self.assertRaises(ValueError):
            self.validate(data)
        data["steps"][0]["image"] = str(self.path)
        with self.assertRaises(ValueError):
            self.validate(data)

    def test_analyzer_distinguishes_physical_batch_tasks_and_hides_text(self):
        events = [dict(event="request_submit", request_id="batch", http_task_id=t, source="SYNTHETIC_PRIVATE_DIALOGUE", cycle="cycle") for t in ("short", "long")]
        events += [dict(event="request_complete", request_id="batch", http_task_id="short"),
                   dict(event="skip", reason="task_busy"), dict(event="caption_drop", reason="window_changed")]
        log = Path(self.temp.name) / "events.jsonl"
        log.write_text("\n".join(json.dumps(e) for e in events))
        report = debug.analyze(log)
        self.assertEqual(report["unfinished_submissions"], 1)
        self.assertEqual(report["repeated_source_submissions"], 1)
        self.assertEqual(report["busy_skips"], 1)
        self.assertNotIn("SYNTHETIC_PRIVATE_DIALOGUE", json.dumps(report))

    def test_partial_jsonl_reports_line_without_echoing_private_contents(self):
        log = Path(self.temp.name) / "events.jsonl"
        log.write_text('{}\n{"source":"SYNTHETIC_PRIVATE')
        with self.assertRaisesRegex(ValueError, "line 2") as error:
            debug.analyze(log)
        self.assertNotIn("SYNTHETIC_PRIVATE", str(error.exception))

    def test_private_output_refuses_symlink(self):
        target = Path(self.temp.name) / "target"
        target.write_text("keep")
        link = Path(self.temp.name) / "link"
        link.symlink_to(target)
        with self.assertRaises(ValueError):
            debug.private_json(link, {"test": 1})
        self.assertEqual(target.read_text(), "keep")
        report = Path(self.temp.name) / "report.json"
        debug.private_json(report, {"test": 1})
        self.assertEqual(report.stat().st_mode & 0o777, 0o600)

    def test_process_timeout_and_isolation_exit_are_not_reported_as_passes(self):
        log = Path(self.temp.name) / "child.log"
        result = debug.acceptance.execute([sys.executable, "-c", "import time; time.sleep(30)"], log, {}, .1)
        self.assertEqual(result["status"], "timeout")
        self.assertNotEqual(result["exit_code"], 0)
        result = debug.acceptance.execute([sys.executable, "-c", "raise SystemExit(86)"], log, {}, 5)
        self.assertEqual(result["status"], "blocked")


if __name__ == "__main__":
    unittest.main(verbosity=2)
