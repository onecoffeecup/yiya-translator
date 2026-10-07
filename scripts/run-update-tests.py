#!/usr/bin/env python3
"""Real Sparkle install/relaunch and signature rejection using temporary fixture apps."""
import argparse
import fcntl
import functools
import hashlib
import http.server
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("sparkle", ROOT / "scripts/sparkle.py")
sparkle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparkle)
NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, capture_output=True, **kwargs)


def bundle(path, binary, framework, info):
    contents = path / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Frameworks").mkdir()
    shutil.copyfile(binary, contents / "MacOS/UpdateHarness")
    os.chmod(contents / "MacOS/UpdateHarness", 0o755)
    run("ditto", "--noextattr", "--noqtn", framework, contents / "Frameworks/Sparkle.framework")
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    run("xattr", "-cr", path)
    run("codesign", "--force", "--sign", "-", "--identifier", info["CFBundleIdentifier"],
        "--requirements", '=designated => identifier "' + info["CFBundleIdentifier"] + '"', path)
    run("codesign", "--verify", "--deep", "--strict", path)


def case(mode, base, binary, distribution, key, public, server_url):
    root = base / mode
    root.mkdir()
    identifier = "com.nanami.fuyi.update-test." + uuid.uuid4().hex
    application = root / "installed/UpdateHarness.app"
    info = dict(CFBundleIdentifier=identifier, CFBundleName="译芽更新测试", CFBundleExecutable="UpdateHarness",
                CFBundlePackageType="APPL", CFBundleShortVersionString="0.2.1", CFBundleVersion="1",
                LSMinimumSystemVersion="13.0", LSUIElement=True,
                SUFeedURL=server_url + mode + "/appcast.xml", SUPublicEDKey=public,
                SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUEnableSystemProfiling=False,
                SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                NSAppTransportSecurity={"NSAllowsLocalNetworking": True},
                FYFixtureRoot=str(root), FYFixtureMode=mode)
    bundle(application, binary, distribution / "Sparkle.framework", info)
    # Synthetic external user data. These are unrelated to the real application support directory.
    data = root / "player-data"
    credentials = data / "credentials"
    credentials.mkdir(parents=True, mode=0o700)
    (credentials / "api-key.json").write_text(json.dumps({"version": "0.2.1", "key": "SYNTHETIC-UPDATE-TEST"}))
    os.chmod(credentials / "api-key.json", 0o600)
    (data / "settings.json").write_text('{"font_size":24}')
    with sqlite3.connect(data / "learning.sqlite3") as connection:
        connection.execute("create table saved_words(word text)")
        connection.execute("insert into saved_words values ('synthetic saved word')")
    before = {str(path.relative_to(data)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in data.rglob("*") if path.is_file()}
    if mode == "empty-feed":
        feed = root / "appcast.xml"
        feed.write_text('<rss version="2.0"><channel><title>Empty signed update feed</title></channel></rss>')
        run(distribution / "bin/sign_update", "--ed-key-file", key, feed)
    elif mode != "menu":
        newer = root / "new/UpdateHarness.app"
        bundle(newer, binary, distribution / "Sparkle.framework", dict(info, CFBundleVersion="2"))
        archive = root / "update.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", newer, archive)
        signature = run(distribution / "bin/sign_update", "--ed-key-file", key, archive).stdout.decode().strip()
        rss = ET.Element("rss", version="2.0", attrib={"xmlns:sparkle": NAMESPACE})
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "Isolated update test"
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "sparkle:version").text = "2"
        ET.SubElement(item, "sparkle:shortVersionString").text = "0.2.1"
        ET.SubElement(item, "sparkle:minimumSystemVersion").text = "13.0"
        enclosure = ET.fromstring('<enclosure xmlns:sparkle="' + NAMESPACE + '" ' + signature + '/>')
        enclosure.set("url", server_url + mode + "/update.zip")
        enclosure.set("type", "application/octet-stream")
        item.append(enclosure)
        feed = root / "appcast.xml"
        feed.write_bytes(ET.tostring(rss, encoding="utf-8", xml_declaration=True))
        run(distribution / "bin/sign_update", "--ed-key-file", key, feed)
        if mode == "tampered-feed":
            feed.write_bytes(feed.read_bytes().replace(b"Isolated update test", b"Tampered update test"))
        elif mode == "tampered-archive":
            with archive.open("ab") as changed:
                changed.write(b"tampered after signing")
    log_path = root / "process.log"
    with log_path.open("wb") as log:
        process = subprocess.Popen([str(application / "Contents/MacOS/UpdateHarness")], stdout=log, stderr=log)
        deadline = time.monotonic() + 75
        success_marker = root / ("menu-passed" if mode == "menu" else ("up-to-date" if mode == "empty-feed" else "relaunched"))
        while time.monotonic() < deadline and not success_marker.exists() and not (root / "failure").exists():
            if process.poll() is not None and mode != "valid":
                break
            time.sleep(0.1)
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    installed = plistlib.loads((application / "Contents/Info.plist").read_bytes())
    failure = (root / "failure").read_text() if (root / "failure").exists() else ""
    if mode in {"valid", "menu", "empty-feed"}:
        if not success_marker.exists():
            raise ValueError(f"{mode}: install/menu did not finish: {failure or log_path.read_text(errors='replace')[-3000:]}")
        if mode == "valid" and installed["CFBundleVersion"] != "2":
            raise ValueError("New build not installed")
        if mode == "valid":
            run("codesign", "--verify", "--deep", "--strict", application)
    else:
        if not failure or installed["CFBundleVersion"] != "1" or success_marker.exists():
            raise ValueError(f"{mode}: tampered update was not rejected: {failure}")
        # Sparkle announces its extraction/validation UI phase before validation finishes.
        # Rejecting the signed archive must preserve the installed bundle and never relaunch it.
    after = {str(path.relative_to(data)): hashlib.sha256(path.read_bytes()).hexdigest()
             for path in data.rglob("*") if path.is_file()}
    if before != after or (credentials / "api-key.json").stat().st_mode & 0o777 != 0o600:
        raise ValueError(f"{mode}: synthetic user data changed")
    print(f"PASS {mode}: build {installed['CFBundleVersion']}, external credentials/settings/learning data preserved", flush=True)
    return {"case": mode, "build": installed["CFBundleVersion"], "user_data_unchanged": True,
            "relaunch": mode == "valid" and success_marker.exists(), "rejected": bool(failure)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compile-only", action="store_true")
    args = parser.parse_args()
    compile_only = args.compile_only or os.environ.get("FY_TEST_COMPILE_ONLY") == "1"
    if not compile_only and os.environ.get("FY_TEST_ALLOW_UI") != "1":
        sys.exit("BLOCKED: reserve the desktop and set FY_TEST_ALLOW_UI=1 for installer/relaunch checks")
    lock_dir = ROOT / ".build/acceptance"
    lock_dir.mkdir(parents=True, exist_ok=True)
    with (lock_dir / "runner.lock").open("w") as lock:
        # run-acceptance owns this lock while launching direct child steps.
        parent_reserved = os.environ.get("FY_TEST_PARENT_RUNNER_PID") == str(os.getppid())
        if not compile_only and not parent_reserved:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        distribution = sparkle.fetch()
        with tempfile.TemporaryDirectory(prefix="yiya-update-check-") as temporary:
            base = Path(temporary)
            key = base / "publisher/ed25519.key"
            os.environ["FY_UPDATE_PRIVATE_KEY_FILE"] = str(key)
            public = sparkle.public_key_for_private_file()
            binary = base / "UpdateHarness"
            run("clang", "-fobjc-arc", "-fmodules", "-mmacosx-version-min=13.0", "-I", ROOT / "objc",
                "-F", distribution, "-framework", "Sparkle", "-framework", "Cocoa",
                "-Wl,-rpath,@executable_path/../Frameworks", ROOT / "tests/UpdateInstallerHarness.m",
                ROOT / "objc/FYAppUpdater.m", "-o", binary)
            if compile_only:
                print("COMPILED_ONLY: UpdateInstallerTests (install/relaunch checks NOT RUN)")
                return
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(base)))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                records = [case(mode, base, binary, distribution, key, public,
                                f"http://127.0.0.1:{server.server_port}/")
                           for mode in ["menu", "empty-feed", "valid", "tampered-feed", "tampered-archive"]]
                output = ROOT / ".build/update-checks"
                output.mkdir(parents=True, exist_ok=True)
                (output / "summary.json").write_text(json.dumps(records, indent=2) + "\n")
            finally:
                server.shutdown()
                server.server_close()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr.decode(errors="replace") if error.stderr else "", file=sys.stderr)
        sys.exit(f"Update checks failed: {error}")
