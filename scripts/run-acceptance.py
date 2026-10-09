#!/usr/bin/env python3
"""Prepare by default: pure checks + UI compilation. --ui explicitly reserves desktop use."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent


def test_suites():
    # Keep the existing run-checks.sh as the single suite inventory.
    text = (ROOT / "scripts/run-checks.sh").read_text()
    match = re.search(r"^for suite in ([A-Za-z0-9 ]+); do$", text, re.MULTILINE)
    if not match:
        raise ValueError("Cannot verify run-checks.sh suite inventory; refusing to guess")
    suites = match.group(1).split()
    if len(suites) != len(set(suites)) or not all((ROOT / "tests" / f"{s}.m").is_file() for s in suites):
        raise ValueError("Duplicate or missing suite")
    if not {"ChatPresentationTests", "ChatClipboardTests"}.issubset(suites):
        raise ValueError("Required chat suites missing")
    return suites


def source_hashes():
    paths = []
    for folder in ("objc", "tests", "scripts"):
        paths.extend(p for p in (ROOT / folder).rglob("*") if p.is_file() and
                     p.suffix in {".h", ".m", ".inc", ".sh", ".py", ".json"})
    paths.extend(p for p in (ROOT / "tests/fixtures/replay/assets").glob("*") if p.is_file())
    paths.extend(p for p in (ROOT / "tests/fixtures/layout/assets").glob("*") if p.is_file())
    paths.extend(ROOT / name for name in ("AGENTS.md", "DEBUG_WORKFLOW.md") if (ROOT / name).is_file())
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def execute(command, log, env, timeout):
    started = time.monotonic()
    with log.open("w") as output:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
            state = "passed" if code == 0 else ("blocked" if code == 86 else "failed")
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
            state = "timeout" if isinstance(error, subprocess.TimeoutExpired) else "interrupted"
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            code = process.returncode
    lines = log.read_text(errors="replace").splitlines()
    if state == "passed" and any(line.startswith("Outcome: baseline_passed_with_known_gaps") for line in lines):
        state = "passed_with_known_gaps"
    first = next((line for line in lines if re.search(r"error:|FAIL:|HARNESS ERROR|TEST_ISOLATION_BLOCKED|^FAILED", line)), None)
    return dict(status=state, exit_code=code, seconds=round(time.monotonic()-started, 2),
                first_failure=first if state != "passed" else None,
                temporary_roots=[line.split("=", 1)[1] for line in lines if line.startswith("TEST_ISOLATION_ROOT=")])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ui", action="store_true", help="Run UI/clipboard suites; reserve the desktop first")
    parser.add_argument("--timeout", type=int, default=180, help="Per-step seconds, including compilation")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    base = ROOT / ".build/acceptance"
    base.mkdir(parents=True, exist_ok=True)
    with (base / "runner.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error("Another acceptance runner is active")
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        output = base / f"{stamp}-{uuid.uuid4().hex[:6]}"
        output.mkdir()
        suites = test_suites()
        steps = [("SourceManifestTests", [sys.executable, "tests/SourceManifestTests.py"], False),
                 ("CaptureCardOfflineTests", [sys.executable, "tests/CaptureCardOfflineTests.py"], False),
                 ("TestIsolationTests", ["bash", "scripts/run-isolation-tests.sh"], False),
                 ("ReferenceData", [sys.executable, "scripts/reference-data.py", "check"], False),
                 ("RuntimeDiagnosticsTests", ["bash", "scripts/run-diagnostics-tests.sh"], False),
                 ("DistributionTests", [sys.executable, "tests/DistributionTests.py"], False),
                 ("UpdateDistributionTests", [sys.executable, "tests/UpdateDistributionTests.py"], False),
                 ("UpdateInstallerTests", [sys.executable, "scripts/run-update-tests.py"], True),
                 ("ModuleTests", ["bash", "scripts/run-module-tests.sh"], False),
                 ("ReplayRegressionTests", [sys.executable, "scripts/debug.py", "check", "--replay-only"], False),
                 ("LearningTests", ["bash", "scripts/run-learning-tests.sh"], False),
                 ("LearningStoreResilienceTests", ["bash", "scripts/run-learning-resilience-tests.sh"], False),
                 ("DialogueGrammarTests", ["bash", "scripts/run-dialogue-grammar-tests.sh"], False),
                 ("InlineTranslationTests", ["bash", "scripts/run-tests.sh"], True)]
        steps.extend((s, ["bash", "scripts/run-learning-app-tests.sh", s, str(output / s)], True) for s in suites)
        before = source_hashes()
        report = dict(mode="ui" if args.ui else "prepare", source_hashes=before,
                      results=[dict(suite=s, command=c, ui=ui, status="not_run", exit_code=None,
                                    log=str(output / f"{s}.log")) for s, c, ui in steps])

        def save():
            (output / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n")
            rows = [f"Mode: {report['mode']}", "UI compiled_only means NOT RUN."]
            rows += [f"{r['suite']}: {r['status']} (exit={r['exit_code']})" for r in report["results"]]
            (output / "summary.txt").write_text("\n".join(rows)+"\n")

        save()
        print(f"Report: {output}", flush=True)
        failed = False
        for record in report["results"]:
            if source_hashes() != before:
                record.update(status="blocked", first_failure="Sources changed during this run; preserve evidence and retry a stable version")
                failed = True
                break
            env = os.environ.copy()
            env["FY_TEST_PARENT_RUNNER_PID"] = str(os.getpid())
            env.pop("FY_TEST_ALLOW_UI", None)
            env.pop("FY_TEST_COMPILE_ONLY", None)
            if record["ui"]:
                env["FY_TEST_ALLOW_UI" if args.ui else "FY_TEST_COMPILE_ONLY"] = "1"
            record.update(status="running")
            save()
            result = execute(record["command"], Path(record["log"]), env, args.timeout)
            if result["status"] == "passed" and record["ui"] and not args.ui:
                result["status"] = "compiled_only"
            record.update(result)
            print(f"{record['suite']}: {record['status']}", flush=True)
            save()
            if record["status"] not in ("passed", "passed_with_known_gaps", "compiled_only"):
                failed = True
                if record.get("first_failure"):
                    print(record["first_failure"], flush=True)
                break
        report["source_unchanged"] = source_hashes() == before
        if not report["source_unchanged"]:
            failed = True
        report["outcome"] = "incomplete" if failed else ("passed" if args.ui else "prepared_ui_not_run")
        if not failed and any(r["status"] == "passed_with_known_gaps" for r in report["results"]):
            report["outcome"] += "_with_known_gaps"
        save()
        print(f"Outcome: {report['outcome']}; summary: {output / 'summary.json'}")
        return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
