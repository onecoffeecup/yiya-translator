#!/usr/bin/env python3
"""Prepare signed Sparkle updates locally. Publishing is a separate command."""
import argparse
from copy import deepcopy
import hashlib
import html
import importlib.util
import json
from pathlib import Path
import plistlib
import posixpath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("sparkle", ROOT / "scripts/sparkle.py")
sparkle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparkle)
NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
REPOSITORY = "onecoffeecup/yiya-translator"
ET.register_namespace("sparkle", NAMESPACE)


def archive_info(archive):
    with zipfile.ZipFile(archive) as contents:
        # ditto writes UTF-8 names without the ZIP UTF-8 flag on some macOS releases.
        # Python otherwise decodes those names as CP437; keep the original ZipInfo for reads.
        def filename(entry):
            if entry.flag_bits & 0x800:
                return entry.filename
            try:
                return entry.filename.encode("cp437").decode("utf-8")
            except (UnicodeError, ValueError):
                return entry.filename
        entries = [(filename(entry), entry) for entry in contents.infolist()]
        names = [name for name, entry in entries]
        if len(names) != len(set(names)):
            raise ValueError("更新压缩包包含重复路径")
        for name in names:
            path = Path(name)
            if path.is_absolute() or ".." in path.parts or path.name in {"api-key.json", "ed25519.key"}:
                raise ValueError("更新压缩包包含禁止分发的路径")
            if path.parts and path.parts[0] not in {"译芽.app", "__MACOSX"}:
                raise ValueError("更新压缩包只能包含译芽.app")
        for name, entry in entries:
            if stat.S_ISLNK(entry.external_attr >> 16):
                target = contents.read(entry).decode("utf-8")
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                if target.startswith("/") or not resolved.startswith("译芽.app/"):
                    raise ValueError("更新压缩包的符号链接指向应用之外")
        metadata = dict(entries)["译芽.app/Contents/Info.plist"]
        info = plistlib.loads(contents.read(metadata))
    settings = sparkle.config()
    if info.get("CFBundleIdentifier") != "com.nanami.fuyi":
        raise ValueError("更新包的应用身份不匹配")
    for field, value in [("SUFeedURL", settings["feed_url"]), ("SUPublicEDKey", settings["public_key"]),
                         ("SURequireSignedFeed", True), ("SUVerifyUpdateBeforeExtraction", True)]:
        if info.get(field) != value:
            raise ValueError("更新包的地址、公钥或签名策略与配置不匹配")
    build = str(info.get("CFBundleVersion", ""))
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("更新 build 必须为正整数")
    return info


def sign_feed(feed, tool, key):
    subprocess.run([str(tool), "--ed-key-file", str(key), str(feed)], check=True, capture_output=True)
    subprocess.run([str(tool), "--verify", "--ed-key-file", str(key), str(feed)], check=True, capture_output=True)


def validate_tag(tag, info):
    version = info["CFBundleShortVersionString"]
    if tag not in {"v" + version, "v" + version + "-build-" + str(info["CFBundleVersion"])}:
        raise ValueError("Release 标签必须与更新包的应用版本／build 一致")


def preserve_published_history(feed, published, build):
    generated = ET.parse(feed)
    channel = generated.find("./channel")
    current = [item for item in channel.findall("item")
               if item.findtext(f"{{{NAMESPACE}}}version") == build]
    if len(current) != 1:
        raise ValueError("更新清单未生成唯一的当前 build")
    history = published.findall("./channel/item")
    published_builds = {item.findtext(f"{{{NAMESPACE}}}version") for item in history}
    # generate_appcast can rewrite historical URLs using the new release prefix.
    # Restore the signed online entries, and omit drafts discovered in the local archive cache.
    for item in channel.findall("item"):
        channel.remove(item)
    deltas = current[0].find(f"{{{NAMESPACE}}}deltas")
    if deltas is not None:
        for enclosure in list(deltas):
            if enclosure.get(f"{{{NAMESPACE}}}deltaFrom") not in published_builds:
                deltas.remove(enclosure)
        if not len(deltas):
            current[0].remove(deltas)
    channel.append(current[0])
    channel.extend(deepcopy(history))
    ET.indent(generated, space="    ")
    generated.write(feed, encoding="utf-8", xml_declaration=True)


def prepare(archive, tag, notes, output):
    info = archive_info(archive)
    validate_tag(tag, info)
    with tempfile.TemporaryDirectory(prefix="yiya-update-verify-") as temporary:
        subprocess.run(["ditto", "-x", "-k", str(archive), temporary], check=True)
        app = Path(temporary) / "译芽.app"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        if plistlib.loads((app / "Contents/Info.plist").read_bytes()) != info:
            raise ValueError("解压后的更新应用身份与压缩包记录不一致")
    key = sparkle.require_signing_key()
    tools = sparkle.fetch() / "bin"
    archives = ROOT / "dist/updates/archives"
    archives.mkdir(parents=True, exist_ok=True)
    # Every archive has an immutable build-specific filename, including same-version fixes.
    filename = f"yiya-{info['CFBundleShortVersionString']}-build-{info['CFBundleVersion']}-update.zip"
    target = archives / filename
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() != digest:
        raise ValueError("同一 build 的更新包已存在且内容不同，请递增 build 后重新构建")
    if archive.resolve() != target.resolve():
        shutil.copyfile(archive, target)
    feed = archives / "appcast.xml"
    # Read the actually published history, so unshipped local drafts never enter the feed.
    downloaded = archives / "published-appcast.xml"
    subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--silent", "--show-error",
                    sparkle.config()["feed_url"], "--output", str(downloaded)], check=True)
    subprocess.run([str(tools / "sign_update"), "--verify", "--ed-key-file", str(key), str(downloaded)],
                   check=True, capture_output=True)
    published = ET.parse(downloaded)
    builds = [int(item.findtext(f"{{{NAMESPACE}}}version", "0")) for item in published.findall("./channel/item")]
    if builds and int(info["CFBundleVersion"]) <= max(builds):
        raise ValueError("发布 build 必须高于线上更新清单，请设置 FY_BUILD_NUMBER 后重新构建")
    shutil.copyfile(downloaded, feed)
    downloaded.unlink()
    # Generate the requested update, then restore the actually published history.
    if notes:
        target.with_suffix(".txt").write_text(notes.read_text())
    subprocess.run([str(tools / "generate_appcast"), "--ed-key-file", str(key),
                    "--versions", str(info["CFBundleVersion"]), "--maximum-deltas", "3",
                    "--embed-release-notes", "--download-url-prefix",
                    f"https://github.com/{REPOSITORY}/releases/download/{tag}/",
                    "--link", f"https://github.com/{REPOSITORY}/releases", str(archives)], check=True)
    preserve_published_history(feed, published, str(info["CFBundleVersion"]))
    sign_feed(feed, tools / "sign_update", key)
    current = [item for item in ET.parse(feed).findall("./channel/item")
               if item.findtext(f"{{{NAMESPACE}}}version") == str(info["CFBundleVersion"])]
    if len(current) != 1:
        raise ValueError("更新清单未生成唯一的当前 build")
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(feed, output / "appcast.xml")
    assets = []
    for enclosure in current[0].iter("enclosure"):
        url = enclosure.attrib["url"]
        prefix = f"https://github.com/{REPOSITORY}/releases/download/{tag}/"
        if not url.startswith(prefix):
            raise ValueError("新更新包下载地址与 Release 不匹配")
        from urllib.parse import unquote
        name = unquote(url[len(prefix):])
        if Path(name).name != name or not (archives / name).is_file():
            raise ValueError("更新清单引用了不存在的更新附件")
        path = archives / name
        asset_digest = hashlib.sha256(path.read_bytes()).hexdigest()
        shutil.copyfile(path, output / name)
        checksum = output / (name + ".sha256")
        checksum.write_text(f"{asset_digest}  {name}\n")
        assets.extend([{"name": name, "sha256": asset_digest},
                       {"name": checksum.name, "sha256": hashlib.sha256(checksum.read_bytes()).hexdigest()}])
    (output / "release.json").write_text(json.dumps({"repository": REPOSITORY, "tag": tag,
        "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"], "assets": assets}, indent=2) + "\n")
    (output / ".nojekyll").touch()
    print(f"已准备带签名的更新清单与 {len(assets)} 个附件：{output}")


def bootstrap(output):
    output.mkdir(parents=True, exist_ok=True)
    feed = output / "appcast.xml"
    feed.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="{NAMESPACE}">
  <channel>
    <title>译芽更新</title>
    <link>{html.escape(sparkle.config()['feed_url'])}</link>
    <description>译芽应用内更新清单</description>
    <language>zh-CN</language>
  </channel>
</rss>
''')
    sign_feed(feed, sparkle.fetch() / "bin/sign_update", sparkle.require_signing_key())
    (output / ".nojekyll").touch()
    print(f"已生成带签名的空清单（不提供任何应用更新）：{feed}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootstrap", action="store_true", help="prepare an empty signed feed for initial Pages setup")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--tag")
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/update-publish")
    args = parser.parse_args()
    if args.bootstrap:
        if args.archive or args.tag:
            parser.error("bootstrap cannot include a release")
        bootstrap(args.output)
    else:
        if not args.archive or not args.tag:
            parser.error("--archive and --tag are required")
        prepare(args.archive, args.tag, args.notes, args.output)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile, ET.ParseError) as error:
        sys.exit(f"错误：{error}")
