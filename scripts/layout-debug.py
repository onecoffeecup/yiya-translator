#!/usr/bin/env python3
"""Opt-in layout evidence control and isolated P0 -> P3 regression runner."""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent
DIRECTORY = Path(f"/tmp/yiya-layout-debug-{os.getuid()}")

def private_directory(path):
    path.mkdir(parents=True, mode=0o700, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise ValueError("Layout evidence directory must be owned by you with mode 0700")

def atomic_json(path, data):
    if path.is_symlink():
        raise ValueError("Refusing symlink control file")
    fd, name = tempfile.mkstemp(prefix=".control-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, ensure_ascii=False)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    start = sub.add_parser("start", help="Authorize raw images/OCR/translations for up to 300 seconds in a private directory")
    start.add_argument("--seconds", type=int, default=120)
    start.add_argument("--no-overlay", action="store_true", help="Export only, without a live debug overlay")
    sub.add_parser("stop")
    sub.add_parser("status")
    check = sub.add_parser("check", help="Synthetic, headless production layout and rendering gates; no real API")
    check.add_argument("--output", type=Path)
    check.add_argument("--through", choices=["P0", "P1", "P2", "P3"], default="P3", help="Stop after this gate; later gates run only if earlier ones pass")
    compare = sub.add_parser("compare", help="Compare two exported layout records by stable block ID")
    compare.add_argument("before", type=Path)
    compare.add_argument("after", type=Path)
    args = parser.parse_args()
    if args.command == "start":
        if not 1 <= args.seconds <= 300:
            parser.error("seconds must be 1..300")
        private_directory(DIRECTORY)
        now = time.time()
        atomic_json(DIRECTORY / "control.json", dict(session=str(uuid.uuid4()), issued_at=now,
                    expires_at=now + args.seconds, overlay=not args.no_overlay))
        print(f"Layout diagnostic control armed for {args.seconds}s: {DIRECTORY}")
        print("Default/release apps ignore this file. Requires a developer build with FY_ENABLE_LAYOUT_DEBUG=1.")
        print("Includes captured images, OCR and translations. Limit: 120 frames, 300 layouts, 64 MiB per session. App is not started.")
    elif args.command == "stop":
        (DIRECTORY / "control.json").unlink(missing_ok=True)
        print("Layout diagnostics stopped; saved evidence retained.")
    elif args.command == "status":
        if not DIRECTORY.exists():
            print("Layout diagnostics disabled")
            return 0
        private_directory(DIRECTORY)
        path = DIRECTORY / "control.json"
        if path.is_symlink():
            raise ValueError("Refusing symlink control")
        control = json.loads(path.read_text()) if path.exists() else {}
        active = control.get("issued_at", 0) <= time.time() < control.get("expires_at", 0)
        print(f"Layout control {'armed' if active else 'disabled'}; evidence: {DIRECTORY}")
        print("Control state does not confirm app recording; default/release apps ignore it.")
    elif args.command == "check":
        output = args.output or ROOT / ".build/layout-debug" / ("run-" + uuid.uuid4().hex[:8])
        private_directory(output)
        return subprocess.call(["bash", "scripts/run-layout-debug-tests.sh", str(output.resolve()), args.through], cwd=ROOT)
    else:
        before, after = [json.loads(p.read_text()) for p in (args.before, args.after)]
        old = {b["stable_id"]: b for b in before["blocks"]}
        changes = []
        for index, block in enumerate(after["blocks"]):
            prior = old.pop(block["stable_id"], None)
            if prior is None:
                changes.append(dict(block=index + 1, change="added"))
            else:
                keys = [key for key in ("target_box", "final_frame", "mode", "translation", "actual_render") if prior.get(key) != block.get(key)]
                if keys:
                    changes.append(dict(block=index + 1, changed_fields=keys, position_delta=block.get("position_delta")))
        print(json.dumps(dict(changes=changes, removed=len(old), before_reason=before["update_reason"],
              after_reason=after["update_reason"]), ensure_ascii=False, indent=2))
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Layout diagnostics: {error}")
