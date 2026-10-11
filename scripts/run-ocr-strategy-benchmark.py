#!/usr/bin/env python3
"""Opt-in synthetic Vision experiment; never capture a screen or open hardware."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import unicodedata
import uuid
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent


def normalized(text):
    return "".join(unicodedata.normalize("NFKC", text).split())


def edit_distance(left, right):
    row = list(range(len(right) + 1))
    for i, a in enumerate(left, 1):
        updated = [i]
        for j, b in enumerate(right, 1):
            updated.append(min(updated[-1] + 1, row[j] + 1, row[j - 1] + (a != b)))
        row = updated
    return row[-1]


def overlaps_line(truth, recognized):
    x, y, w, h = truth
    a, b, c, d = recognized
    overlap = max(0, min(x+w, a+c)-max(x, a)) * max(0, min(y+h, b+d)-max(y, b))
    # Geometry-based missing-line signal, independent of recognized spelling.
    # A broad merged observation can cover several lines; CER still sees its text.
    return overlap / max(w*h, 1e-12) >= .20


def summarize(raw):
    corpus = {case["name"]: case for case in raw["corpus"]}
    details = []
    for name, case in corpus.items():
        expected = normalized("\n".join(line["text"] for line in case["truth"]))
        for mode in raw["modes"]:
            runs = [run for run in raw["runs"] if run["case"] == name and run["mode"] == mode]
            if len(runs) != raw["repeats"] or any(run["error_code"] for run in runs):
                raise ValueError(f"Incomplete or failed run: {name}/{mode}")
            errors = [edit_distance(expected, normalized(run["text"])) for run in runs]
            missing = [sum(not any(overlaps_line(line["box"], block["box"]) for block in run["blocks"])
                           for line in case["truth"]) for run in runs]
            details.append(dict(case=name, mode=mode, characters=len(expected), lines=len(case["truth"]),
                                errors=statistics.median(errors), missing_lines=statistics.median(missing),
                                elapsed_ms=statistics.median(run["elapsed_ms"] for run in runs),
                                request_count=statistics.median(len(run["requests"]) for run in runs),
                                text_variants=len({normalized(run["text"]) for run in runs})))
    totals = []
    for mode in raw["modes"]:
        rows = [row for row in details if row["mode"] == mode]
        errors, characters = sum(row["errors"] for row in rows), sum(row["characters"] for row in rows)
        missing, lines = sum(row["missing_lines"] for row in rows), sum(row["lines"] for row in rows)
        totals.append(dict(mode=mode, errors=errors, characters=characters, cer=errors/characters,
                           missing_lines=missing, lines=lines, missing_line_rate=missing/lines,
                           exact_images=sum(row["errors"] == 0 for row in rows), images=len(rows),
                           mean_frame_ms=statistics.mean(row["elapsed_ms"] for row in rows),
                           mean_requests=statistics.mean(row["request_count"] for row in rows)))
    return dict(totals=totals, details=details)


def hashes(paths):
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repeat", type=int, default=3, choices=range(1, 21))
    parser.add_argument("--corpus", choices=("clean", "stress", "all"), default="all")
    args = parser.parse_args()
    # Verify metric primitives independently of OCR answers.
    assert edit_distance("庭の花", "庭の花") == 0
    assert edit_distance("庭の花", "庭の華") == 1
    assert edit_distance("庭の花", "") == 3
    assert edit_distance("", "花") == 1
    assert normalized("Ａ １\n庭　花") == "A1庭花"
    assert overlaps_line([.1,.2,.3,.1], [.1,.2,.3,.1])
    assert not overlaps_line([.1,.2,.3,.1], [.1,.7,.3,.1])
    os.umask(0o077)
    directory = ROOT / ".build/ocr-strategy-benchmark" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:6])
    directory.mkdir(parents=True)
    env = dict(os.environ, ROOT_DIR=str(ROOT))
    env.pop("FUYI_DIAG", None)
    source_result = subprocess.run(["bash", "-c", 'source "$ROOT_DIR/scripts/lib-sources.sh"; printf "%s\\n" "${FY_OCR_SOURCES[@]}"'],
                                   check=True, capture_output=True, text=True, env=env)
    sources = [Path(line) for line in source_result.stdout.splitlines()]
    tracked = sources + [ROOT / "objc/FYOCRManager.h", ROOT / "scripts/lib-sources.sh", ROOT / "tests/OCRStrategyBenchmark.m", Path(__file__)]
    before = hashes(tracked)
    bundle = directory / "OCRStrategyBenchmark.app"
    executable = bundle / "Contents/MacOS/OCRStrategyBenchmark"
    executable.parent.mkdir(parents=True)
    command = ["clang", "-O2", "-fobjc-arc", "-fmodules", "-mmacosx-version-min=13.0", "-Wall", "-Wextra",
               "-DFY_ENABLE_LAYOUT_DEBUG=0", "-Wno-unused-parameter", "-I", str(ROOT / "objc"), str(ROOT / "tests/OCRStrategyBenchmark.m"),
               *map(str, sources), "-framework", "Cocoa", "-framework", "CoreText", "-framework", "Vision",
               "-framework", "ImageIO", "-o", str(executable)]
    print(f"Report: {directory}", flush=True)
    with (directory / "build.log").open("w") as log:
        subprocess.run(command, check=True, stdout=log, stderr=log, timeout=120)
    import plistlib
    with (bundle / "Contents/Info.plist").open("wb") as stream:
        plistlib.dump(dict(CFBundleExecutable="OCRStrategyBenchmark", CFBundleIdentifier="com.nanami.yiya.ocr-strategy-benchmark",
                          CFBundleName="OCRStrategyBenchmark", CFBundlePackageType="APPL", LSUIElement=True,
                          CFBundleShortVersionString="1.0", CFBundleVersion="1"), stream)
    subprocess.run(["xattr", "-cr", str(bundle)], check=True, timeout=30)
    with (directory / "sign.log").open("w") as log:
        subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True, stdout=log, stderr=log, timeout=30)
    with (directory / "launch.log").open("w") as log:
        subprocess.run(["open", "-W", "-n", str(bundle), "--args", str(directory), str(args.repeat), args.corpus],
                       check=True, stdout=log, stderr=log, timeout=480)
    raw = json.loads((directory / "raw.json").read_text())
    result = summarize(raw)
    result.update(schema_version=1, command=["python3", "scripts/run-ocr-strategy-benchmark.py", "--repeat", str(args.repeat), "--corpus", args.corpus],
                  corpus_kind=raw["corpus_kind"],
                  compiler_command=command, architecture=platform.machine(), os=raw["os"], repeats=raw["repeats"],
                  source_hashes=before, source_unchanged=(before == hashes(tracked)),
                  image_hashes={path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in directory.glob("*.png")},
                  git_head=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip())
    if not result["source_unchanged"]:
        raise RuntimeError("Experiment sources changed during run; rerun before comparing")
    (directory / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    table = ["mode\tCER\tmissing lines\texact images\tmean frame ms\tmean requests"]
    for row in result["totals"]:
        table.append(f'{row["mode"]}\t{row["cer"]:.2%}\t{row["missing_lines"]}/{row["lines"]}\t{row["exact_images"]}/{row["images"]}\t{row["mean_frame_ms"]:.1f}\t{row["mean_requests"]:.2f}')
    table.append("source_unchanged=true")
    (directory / "summary.txt").write_text("\n".join(table) + "\n")
    print("\n".join(table), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
