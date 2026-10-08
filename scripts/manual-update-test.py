#!/usr/bin/env python3
"""Prepare a visible build 13 → 14 Sparkle rehearsal, without publishing an update."""
import argparse
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
import time
import uuid
from urllib.parse import urlsplit
from urllib.request import urlopen
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("sparkle", ROOT / "scripts/sparkle.py")
sparkle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparkle)
NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ARCHIVE = "yiya-manual-build-14.zip"
LATEST = ROOT / ".build/manual-update/latest.json"


def run(*args):
    return subprocess.run(list(map(str, args)), check=True, capture_output=True)


def write_json(path, record):
    path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def serve(root):
    # No directory listing, traversal, or access to the private key/player data.
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            route = urlsplit(self.path).path
            name = {"/appcast.xml": "appcast.xml", "/" + ARCHIVE: ARCHIVE}.get(route)
            asset = root / "public" / name if name else None
            if not asset or not asset.is_file():
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/xml" if name.endswith(".xml") else "application/octet-stream")
            self.send_header("Content-Length", str(asset.stat().st_size))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            try:
                with asset.open("rb") as stream:
                    shutil.copyfileobj(stream, self.wfile)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.timeout = 1
    write_json(root / "server.json", {"pid": os.getpid(), "url": f"http://127.0.0.1:{server.server_port}/",
                                      "started_at": time.time(), "expires_at": time.time() + 7200})
    try:
        deadline = time.monotonic() + 7200
        while time.monotonic() < deadline and not (root / "stop-server").exists():
            server.handle_request()
    finally:
        server.server_close()
        (root / "server-stopped").touch()


def bundle(path, binary, distribution, info):
    contents = path / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Frameworks").mkdir()
    (contents / "Resources").mkdir()
    shutil.copyfile(binary, contents / "MacOS/ManualUpdateHarness")
    os.chmod(contents / "MacOS/ManualUpdateHarness", 0o755)
    run("ditto", "--noextattr", "--noqtn", distribution / "Sparkle.framework", contents / "Frameworks/Sparkle.framework")
    shutil.copyfile(ROOT / "resources/AppIcon.icns", contents / "Resources/AppIcon.icns")
    shutil.copyfile(distribution / "LICENSE", contents / "Resources/Sparkle-LICENSE.txt")
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    run("xattr", "-cr", path)
    run("codesign", "--force", "--sign", "-", "--identifier", info["CFBundleIdentifier"],
        "--requirements", '=designated => identifier "' + info["CFBundleIdentifier"] + '"', path)
    run("codesign", "--verify", "--deep", "--strict", path)


def prepare(open_app):
    distribution = sparkle.fetch()
    token = uuid.uuid4().hex
    root = Path.home() / "Library/Caches/com.nanami.fuyi-build" / ("manual-update-" + token)
    root.mkdir(mode=0o700)
    (root / "public").mkdir()
    folder = Path.home() / "Downloads" / ("译芽更新验收-" + time.strftime("%Y%m%d-%H%M%S") + "-" + token[:4])
    folder.mkdir()
    installed = folder / "译芽更新验收.app"
    key = root / "publisher/ed25519.key"
    os.environ["FY_UPDATE_PRIVATE_KEY_FILE"] = str(key)
    public = sparkle.public_key_for_private_file()
    with (root / "server.log").open("wb") as log:
        process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "serve", "--run", str(root)],
                                   stdout=log, stderr=log, stdin=subprocess.DEVNULL, start_new_session=True)
    try:
        deadline = time.monotonic() + 10
        while not (root / "server.json").exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.1)
        server = json.loads((root / "server.json").read_text())
        base_url = server["url"]
        binary = root / "ManualUpdateHarness"
        run("clang", "-fobjc-arc", "-fmodules", "-mmacosx-version-min=13.0", "-Wno-unused-function",
            "-DFY_TEST_ISOLATED_CREDENTIAL_STORE=1", "-I", ROOT / "objc", "-F", distribution,
            "-framework", "Sparkle", "-framework", "Cocoa", "-lsqlite3", "-Wl,-rpath,@executable_path/../Frameworks",
            ROOT / "tests/ManualUpdateHarness.m", ROOT / "objc/FYAppUpdater.m", "-o", binary)
        info = dict(CFBundleIdentifier="com.nanami.fuyi.manual-update-test." + token,
                    CFBundleName="译芽更新验收", CFBundleDisplayName="译芽更新验收", CFBundleExecutable="ManualUpdateHarness",
                    CFBundlePackageType="APPL", CFBundleIconFile="AppIcon.icns", CFBundleShortVersionString="0.2.1",
                    CFBundleVersion="13", LSMinimumSystemVersion="13.0", NSHighResolutionCapable=True,
                    SUFeedURL=base_url + "appcast.xml", SUPublicEDKey=public,
                    SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUEnableSystemProfiling=False,
                    SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                    NSAppTransportSecurity={"NSAllowsLocalNetworking": True}, FYFixtureRoot=str(root))
        bundle(installed, binary, distribution, info)
        newer = root / "new/译芽更新验收.app"
        bundle(newer, binary, distribution, dict(info, CFBundleVersion="14"))
        data = Path.home() / "Library/Application Support/com.nanami.fuyi.update-lab" / token / "player-data"
        credentials = data / "credentials"
        credentials.mkdir(parents=True, mode=0o700)
        write_json(credentials / "api-key.json", {"version": "0.2.1", "apiKey": "SYNTHETIC-MANUAL-UPDATE-ONLY"})
        os.chmod(credentials / "api-key.json", 0o600)
        write_json(data / "settings.json", {"font_size": 24})
        with sqlite3.connect(data / "learning.sqlite3") as connection:
            connection.execute("create table saved_words(word text)")
            connection.execute("insert into saved_words values ('synthetic saved word')")
        write_json(root / "baseline.json", {"installed_app": str(installed), "data_root": str(data),
            "hashes": {str(path.relative_to(data)): digest(path) for path in data.rglob("*") if path.is_file()}})
        archive = root / "public" / ARCHIVE
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", newer, archive)
        signature = run(distribution / "bin/sign_update", "--ed-key-file", key, archive).stdout.decode().strip()
        rss = ET.Element("rss", version="2.0", attrib={"xmlns:sparkle": NAMESPACE})
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "译芽本机更新验收"
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = "译芽更新验收 0.2.1 · build 14"
        ET.SubElement(item, "sparkle:version").text = "14"
        ET.SubElement(item, "sparkle:shortVersionString").text = "0.2.1"
        ET.SubElement(item, "sparkle:minimumSystemVersion").text = "13.0"
        ET.SubElement(item, "description").text = "本次演练从 build 13 升级到 14。安装并重启后，验收窗口会检查合成 API Key、字体设置及收藏是否保留。"
        enclosure = ET.fromstring('<enclosure xmlns:sparkle="' + NAMESPACE + '" ' + signature + '/>')
        enclosure.set("url", base_url + ARCHIVE)
        enclosure.set("type", "application/octet-stream")
        item.append(enclosure)
        feed = root / "public/appcast.xml"
        feed.write_bytes(ET.tostring(rss, encoding="utf-8", xml_declaration=True))
        run(distribution / "bin/sign_update", "--ed-key-file", key, feed)
        run(distribution / "bin/sign_update", "--verify", "--ed-key-file", key, feed)
        run(distribution / "bin/sign_update", "--verify", "--ed-key-file", key, archive,
            enclosure.get("{" + NAMESPACE + "}edSignature"))
        # Verify the served bytes and the extracted archive, not only staging files.
        for asset in [feed, archive]:
            with urlopen(base_url + asset.name, timeout=10) as response:
                if hashlib.sha256(response.read()).hexdigest() != digest(asset):
                    raise ValueError("Loopback asset differs from the signed file")
        unpacked = root / "archive-check"
        run("ditto", "-x", "-k", archive, unpacked)
        run("codesign", "--verify", "--deep", "--strict", unpacked / "译芽更新验收.app")
        manifest = {"run_root": str(root), "installed_app": str(installed), "folder": str(folder),
                    "data_root": str(data), "bundle_id": info["CFBundleIdentifier"], "from_build": 13, "to_build": 14,
                    "feed_url": base_url + "appcast.xml", "archive_sha256": digest(archive),
                    "server_expires_at": server["expires_at"], "public_update_published": False}
        write_json(root / "manifest.json", manifest)
        LATEST.parent.mkdir(parents=True, exist_ok=True)
        write_json(LATEST, manifest)
        (folder / "测试说明.txt").write_text(
            "直接双击本文件夹内的「译芽更新验收.app」，无需解压。\n"
            "点击「检查测试更新」，在 Sparkle 弹窗中安装更新并重启。\n"
            "成功后窗口显示 build 14 和资料保留结果。\n"
            "这是独立验收应用，测试资料全为合成内容，不替换正式译芽。\n"
            "本机更新服务有效期两小时；停止服务后可重新生成演练。\n", encoding="utf-8")
        if open_app:
            run("open", "-n", installed, "--args", "--check-update")
        print(json.dumps(manifest, ensure_ascii=False, indent=2))
    except BaseException:
        (root / "stop-server").touch()
        raise


def verify(root):
    manifest = json.loads((root / "manifest.json").read_text())
    installed = Path(manifest["installed_app"])
    info = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
    report_path = root / "verification.json"
    if not report_path.exists():
        raise ValueError(f"升级尚未完成：当前 build {info['CFBundleVersion']}，请在验收应用中安装并重启")
    report = json.loads(report_path.read_text())
    if info["CFBundleVersion"] != "14" or not report.get("upgrade_passed"):
        raise ValueError("升级或资料保留检查失败，请查看 verification.json")
    if info["CFBundleIdentifier"] != manifest["bundle_id"] or report["application_path"] != str(installed):
        raise ValueError("升级后的应用身份／路径不符")
    baseline = json.loads((root / "baseline.json").read_text())
    data = Path(manifest["data_root"])
    after = {str(path.relative_to(data)): digest(path) for path in data.rglob("*") if path.is_file()}
    if after != baseline["hashes"] or (data / "credentials").stat().st_mode & 0o777 != 0o700 or \
       (data / "credentials/api-key.json").stat().st_mode & 0o777 != 0o600:
        raise ValueError("合成资料内容／权限改变")
    run("codesign", "--verify", "--deep", "--strict", installed)
    print(json.dumps(report, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "serve", "verify", "stop"])
    parser.add_argument("--open", action="store_true", help="Launch the prepared app and check for updates")
    parser.add_argument("--run", type=Path, help="Run directory; defaults to the most recent rehearsal")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.open)
        return
    root = args.run or Path(json.loads(LATEST.read_text())["run_root"])
    if args.command == "serve":
        serve(root)
    elif args.command == "stop":
        (root / "stop-server").touch()
        print("已请求停止本机更新服务；验收应用和资料保留供检查。")
    else:
        verify(root)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.decode(errors="replace"), file=sys.stderr)
        sys.exit(f"验收失败：{error}")
