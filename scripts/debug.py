#!/usr/bin/env python3
"""Local Debug entrypoint: deterministic headless regression, Replay and JSONL analysis."""
import argparse
from collections import Counter
import datetime
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests/fixtures/replay"
spec = importlib.util.spec_from_file_location("acceptance", ROOT / "scripts/run-acceptance.py")
acceptance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acceptance)
ACTION_FIELDS = {
    "frame": {"text", "blocks", "image", "video", "video_ms", "capture_failed", "ocr_error"},
    "tick": set(), "advance": set(), "release": {"request"}, "window": {"window_id"},
    "mode": {"mode"}, "disconnect": set(), "connect": set(), "restart": set(),
    "cache_probe": set(), "translate": {"text"},
}
EXPECT_KEYS = {"requests", "sources", "captions", "inline", "errors", "in_flight", "pending",
               "cancel_calls", "ocr_calls", "mode", "reasons", "drops", "events", "direct_results",
               "has_reason", "caption_contains"}


def number(value, label, minimum=0, maximum=299000):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not minimum <= value <= maximum:
        raise ValueError(f"{label}: expected finite number in {minimum}..{maximum}")


def validate(path):
    """Validate all operations before the native runner can start. No values in errors."""
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or data.get("schema_version") != 1 or data.get("draft"):
        raise ValueError("Replay must be a finalized schema_version=1 object")
    if set(data) - {"schema_version", "name", "mode", "source", "stable", "auto_fit", "auto_mode",
                    "scope", "language", "trace_disabled", "responses", "steps", "notes", "callback_timeout_ms", "known_gap"}:
        raise ValueError("Unknown scenario fields")
    if not isinstance(data.get("name"), str) or not data["name"] or len(data["name"]) > 100:
        raise ValueError("Scenario needs a name of 1..100 characters")
    if "known_gap" in data:
        gap = data["known_gap"]
        if not isinstance(gap, dict) or set(gap) != {"step", "message", "expected", "actual"}:
            raise ValueError("known_gap must identify the exact expected failure")
    if data.get("mode", "dialogue") not in {"dialogue", "ui"} or data.get("source", "window") not in {"window", "capture_card"}:
        raise ValueError("Unsupported mode/source")
    if data.get("language", "ja") not in {"ja", "en"}:
        raise ValueError("Unsupported language")
    for key in ("stable", "auto_fit", "auto_mode", "trace_disabled"):
        if key in data and not isinstance(data[key], bool):
            raise ValueError(f"{key}: expected boolean")
    if "scope" in data:
        box(data["scope"])
    if "callback_timeout_ms" in data:
        number(data["callback_timeout_ms"], "callback_timeout_ms", 1, 30000)
    responses = data.get("responses")
    if not isinstance(responses, list) or len(responses) > 1000:
        raise ValueError("responses: expected bounded list")
    for response in responses:
        if not isinstance(response, dict) or set(response) - {"source", "translation", "status", "raw_body", "error_code", "hold", "release_at_ms"}:
            raise ValueError("Invalid response fields")
        for key in ("source", "translation", "raw_body"):
            if key in response and not isinstance(response[key], str):
                raise ValueError(f"response {key}: expected string")
        if "status" in response:
            number(response["status"], "status", 100, 599)
        if "error_code" in response:
            number(response["error_code"], "error_code", -99999, 99999)
        if "release_at_ms" in response:
            number(response["release_at_ms"], "release_at_ms")
        if "hold" in response and not isinstance(response["hold"], bool):
            raise ValueError("hold: expected boolean")
    steps = data.get("steps")
    if not isinstance(steps, list) or not 1 <= len(steps) <= 1000:
        raise ValueError("steps: expected 1..1000 steps")
    previous, assertions = -1, 0
    for index, step in enumerate(steps):
        if not isinstance(step, dict) or step.get("action") not in ACTION_FIELDS:
            raise ValueError(f"step {index}: unknown action")
        action = step["action"]
        if set(step) - (ACTION_FIELDS[action] | {"at_ms", "action", "expect"}):
            raise ValueError(f"step {index}: unknown fields")
        number(step.get("at_ms"), f"step {index} at_ms")
        if step["at_ms"] < previous:
            raise ValueError(f"step {index}: virtual time must not go backwards")
        previous = step["at_ms"]
        expected = step.get("expect", {})
        if not isinstance(expected, dict) or set(expected) - EXPECT_KEYS:
            raise ValueError(f"step {index}: invalid expectation keys")
        assertions += len(expected)
        if action == "release":
            number(step.get("request"), "request index", 0, max(len(responses)-1, 0))
            if not isinstance(step["request"], int):
                raise ValueError("request index must be an integer")
        if action == "window":
            number(step.get("window_id"), "window_id", 1, 2**32-1)
        if action == "mode" and step.get("mode") not in {"ui", "dialogue"}:
            raise ValueError("mode action needs a mode")
        if action == "translate" and not isinstance(step.get("text"), str):
            raise ValueError("translate action needs text")
        if action == "frame":
            if "capture_failed" in step and not isinstance(step["capture_failed"], bool):
                raise ValueError("capture_failed: expected boolean")
            if "ocr_error" in step:
                number(step["ocr_error"], "ocr_error", -99999, 99999)
            for key in ("text", "image", "video"):
                if key in step and not isinstance(step[key], str):
                    raise ValueError(f"frame {key}: expected string")
            for key in ("image", "video"):
                if key in step:
                    media = (path.parent / step[key]).resolve()
                    allowed = {".png", ".jpg", ".jpeg", ".tiff", ".bmp"} if key == "image" else {".mp4", ".mov", ".m4v"}
                    if not media.is_file() or media.suffix.lower() not in allowed:
                        raise ValueError(f"frame {key}: missing or unsupported local media")
            if "image" in step and "video" in step:
                raise ValueError("frame: choose image or video")
            if "video" in step:
                number(step.get("video_ms"), "video_ms", 0, 86400000)
            if "blocks" in step:
                if not isinstance(step["blocks"], list):
                    raise ValueError("blocks: expected list")
                for block in step["blocks"]:
                    if not isinstance(block, dict) or set(block) != {"text", "box"} or not isinstance(block["text"], str):
                        raise ValueError("block needs text and normalized box")
                    box(block["box"])
    if not assertions:
        raise ValueError("Replay needs at least one explicit product assertion")
    return data


def box(values):
    if not isinstance(values, list) or len(values) != 4:
        raise ValueError("box/scope: expected [x,y,w,h]")
    for value in values:
        number(value, "box/scope", 0, 1)
    if values[2] <= 0 or values[3] <= 0 or values[0]+values[2] > 1.000001 or values[1]+values[3] > 1.000001:
        raise ValueError("box/scope must fit in normalized frame")


def hashes(paths):
    result = acceptance.source_hashes()
    for path in paths:
        result[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        scenario = json.loads(path.read_text())
        for step in scenario.get("steps", []):
            for key in ("image", "video"):
                if key in step:
                    media = (path.parent / step[key]).resolve()
                    result[str(media)] = hashlib.sha256(media.read_bytes()).hexdigest()
    return result


def run(args):
    paths = [args.scenario.resolve()] if args.command == "replay" else sorted(FIXTURES.glob("*.json")) + sorted((FIXTURES / "known-gaps").glob("*.json"))
    for path in paths:
        validate(path)
    if not paths:
        raise ValueError("No Replay scenarios found")
    base = ROOT / ".build/debug"
    base.mkdir(parents=True, exist_ok=True)
    with (base / "runner.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Another Debug runner is active")
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        output = base / f"{stamp}-{uuid.uuid4().hex[:6]}"
        output.mkdir(mode=0o700)
        before = hashes(paths)
        report = dict(schema_version=1, scope="headless", real_api_calls=0, device="not_run", ui="not_run", product_acceptance="not_run",
                      outcome="running", source_hashes=before, results=[])
        env = os.environ.copy()
        for key in ("FY_TEST_ALLOW_UI", "FY_TEST_COMPILE_ONLY", "FUYI_DIAG", "FY_INLINE_REPLAY_PATH"):
            env.pop(key, None)

        def save():
            private_json(output / "summary.json", report)
            lines = ["Debug scope: headless; real API calls=0; device/UI=NOT RUN", f"Outcome: {report['outcome']}"]
            lines += [f"{r['suite']}: {r['status']}" for r in report["results"]]
            for record in report["results"]:
                if record.get("failure"):
                    lines.append(json.dumps(record["failure"], ensure_ascii=False))
            (output / "summary.txt").write_text("\n".join(lines)+"\n")
            (output / "summary.txt").chmod(0o600)

        def execute(name, command, announce=True):
            if hashes(paths) != before:
                raise ValueError("Sources or fixture media changed during Debug run")
            record = dict(suite=name, command=command, log=str(output / f"{name}.log"))
            record.update(acceptance.execute(command, Path(record["log"]), env, args.timeout))
            Path(record["log"]).chmod(0o600)
            report["results"].append(record)
            save()
            if announce:
                print(f"{name}: {record['status']}", flush=True)
            return record

        print(f"Report: {output}", flush=True)
        save()
        try:
            if args.command == "check" and not getattr(args, "replay_only", False):
                steps = [("DebugInfrastructureTests", [sys.executable, "tests/DebugInfrastructureTests.py"]),
                         ("TestIsolationTests", ["bash", "scripts/run-isolation-tests.sh"]),
                         ("RuntimeDiagnosticsTests", ["bash", "scripts/run-diagnostics-tests.sh"]),
                         ("ModuleTests", ["bash", "scripts/run-module-tests.sh"]),
                         ("TranslationTraceTests", ["bash", "scripts/run-translation-trace-tests.sh"]),
                         ("DialogueGrammarTests", ["bash", "scripts/run-dialogue-grammar-tests.sh"])]
                for name, command in steps:
                    if execute(name, command)["status"] != "passed":
                        report["outcome"] = "failed"
                        return 1
            if execute("ReplayBuild", ["bash", "scripts/run-replay-tests.sh", "--build-only"])["status"] != "passed":
                report["outcome"] = "failed"
                return 1
            if args.command == "check" and execute("ReplayFailureReportingTests", [sys.executable, "tests/ReplayFailureReportingTests.py"])["status"] != "passed":
                report["outcome"] = "failed"
                return 1
            known_gaps = 0
            for index, path in enumerate(paths):
                scenario = validate(path)
                known = scenario.get("known_gap") if args.command == "check" else None
                if known:
                    known_gaps += 1
                baseline = None
                for repeat in range(args.repeat):
                    name = f"Replay-{index:02d}-{repeat+1}"
                    result_path = output / f"{name}.json"
                    record = execute(name, [str(ROOT / ".build/replay/ReplayTests"), str(path), str(result_path)], announce=False)
                    if result_path.exists():
                        native = json.loads(result_path.read_text())
                        record.update(scenario=native["scenario"], failure=native["failure"], assertions=native["assertions"], result=str(result_path), trace=native["trace_path"])
                        if known and native["status"] == "failed" and record["exit_code"] == 1 and native["failure"] == known:
                            record["status"] = "known_gap_reproduced"
                        elif known:
                            record.update(status="failed", failure={"message": "Known gap changed; investigate and promote resolved scenario to normal regressions"})
                        elif native["status"] != "passed":
                            record["status"] = "failed"
                        if baseline is not None and native["checkpoints"] != baseline:
                            record.update(status="failed", failure={"message": "Repeated input produced different checkpoints"})
                        baseline = native["checkpoints"]
                    else:
                        record.update(status="failed", failure={"message": "Native Replay did not produce a report"})
                    print(f"{native.get('scenario', name) if result_path.exists() else name}: {record['status']}", flush=True)
                    if record["status"] not in {"passed", "known_gap_reproduced"}:
                        report["outcome"] = "failed"
                        return 1
                    save()
            report["source_unchanged"] = hashes(paths) == before
            report["known_product_gaps"] = known_gaps
            report["outcome"] = ("baseline_passed_with_known_gaps" if known_gaps else "passed") if report["source_unchanged"] else "failed"
            return 0 if report["source_unchanged"] else 1
        except (OSError, ValueError, json.JSONDecodeError) as error:
            report["outcome"] = "incomplete"
            report["runner_error"] = type(error).__name__
            raise
        finally:
            save()
            print(f"Outcome: {report['outcome']}; summary: {output / 'summary.txt'}", flush=True)


def private_json(path, value):
    # Atomic private report updates; never follow symlinks or mutate hard links.
    data = json.dumps(value, ensure_ascii=False, indent=2)+"\n"
    if path.is_symlink():
        raise ValueError("Refusing symlink output")
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".debug-report-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def read_events(path):
    with path.open() as source:
        for index, line in enumerate(source, 1):
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                raise ValueError(f"Invalid JSONL at line {index}") from None
            if not isinstance(event, dict):
                raise ValueError(f"Expected JSON object at line {index}")
            yield event


def analyze(path):
    events = list(read_events(path))
    names = Counter(e.get("event", "unknown") for e in events)
    requests = [e for e in events if e.get("event") == "request_submit"]
    completed = {e.get("http_task_id") or e.get("request_id") for e in events if e.get("event") == "request_complete"}
    signatures = Counter(hashlib.sha256(e.get("source", "").encode()).hexdigest() for e in requests)
    return dict(events=len(events), counts=dict(names), cycles=len({e.get("cycle") for e in events if e.get("cycle")}),
                submissions=len(requests), unfinished_submissions=sum((e.get("http_task_id") or e.get("request_id")) not in completed for e in requests),
                repeated_source_submissions=sum(count-1 for count in signatures.values() if count > 1),
                busy_skips=sum(e.get("reason") == "task_busy" for e in events),
                stale_drops=sum(e.get("event") in {"caption_drop", "inline_drop"} for e in events),
                truncated_records=sum(bool(e.get("text_truncated") or e.get("lines_truncated")) for e in events),
                note="Metadata only. Repeated submissions, drops and unfinished requests are clues, not proven bugs; bounded logs may be incomplete.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("check", "replay"):
        command = commands.add_parser(name)
        command.add_argument("--timeout", type=int, default=180, help="Per build/test step wall-clock deadline")
        command.add_argument("--repeat", type=int, default=2, help="Replay repetitions compared for determinism")
        if name == "replay":
            command.add_argument("scenario", type=Path)
        else:
            command.add_argument("--replay-only", action="store_true", help="Only Replay and known gaps; used by existing full runners")
    trace = commands.add_parser("trace", help="Summarize JSONL without displaying dialogue")
    trace.add_argument("log", type=Path)
    convert = commands.add_parser("import-trace", help="Create private draft; add mock responses and expectations before Replay")
    convert.add_argument("log", type=Path)
    convert.add_argument("output", type=Path)
    convert.add_argument("--stage", default="modal_scoped", choices=["vision_raw", "modal_scoped", "inline_grouped"])
    args = parser.parse_args()
    if args.command in {"check", "replay"}:
        if args.timeout < 1 or not 1 <= args.repeat <= 10:
            parser.error("timeout must be positive; repeat must be 1..10")
        return run(args)
    if args.command == "trace":
        print(json.dumps(analyze(args.log), ensure_ascii=False, indent=2))
        return 0
    if args.output.exists():
        parser.error("Output already exists; choose a new private draft path")
    frames = [e for e in read_events(args.log) if e.get("event") == "ocr" and e.get("stage") == args.stage]
    if not frames or any(e.get("lines_truncated") or any(line.get("truncated") for line in e.get("ocr_lines", [])) for e in frames):
        parser.error("No frames at selected stage, or truncated input; cannot create a faithful draft")
    steps = [dict(at_ms=index*500, action="frame", blocks=[dict(text=line.get("text", ""),
              box=[line.get(k, 0) for k in ("x", "y", "w", "h")]) for line in frame.get("ocr_lines", [])], expect={})
             for index, frame in enumerate(frames)]
    private_json(args.output, dict(schema_version=1, name="Imported trace draft", draft=True,
                 mode="dialogue", source="window", responses=[], steps=steps,
                 notes="Choose mode/source, timings and mocks; add assertions, remove draft. Postprocessed stages cannot recover upstream missing observations."))
    print("Private draft saved. Add mock responses and explicit expectations before Replay.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        sys.exit(f"Debug error: {error}")
