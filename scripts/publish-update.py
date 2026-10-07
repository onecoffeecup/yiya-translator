#!/usr/bin/env python3
"""Upload verified update assets, then publish the signed feed to GitHub Pages."""
import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "onecoffeecup/yiya-translator"
BRANCH = "gh-pages"
spec = importlib.util.spec_from_file_location("sparkle", ROOT / "scripts/sparkle.py")
sparkle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparkle)


def github(path, method="GET", data=None, missing_ok=False):
    result = subprocess.run(["gh", "api", path, "--method", method] + (["--input", "-"] if data is not None else []),
                            input=json.dumps(data) if data is not None else None,
                            capture_output=True, text=True)
    if result.returncode:
        if missing_ok and "HTTP 404" in result.stderr:
            return None
        raise ValueError("GitHub 操作失败：" + result.stderr.strip())
    return json.loads(result.stdout) if result.stdout.strip() else None


def ensure_pages():
    source = {"branch": BRANCH, "path": "/"}
    pages = github(f"repos/{REPOSITORY}/pages", missing_ok=True)
    if not pages:
        try:
            github(f"repos/{REPOSITORY}/pages", "POST", {"source": source, "build_type": "legacy"})
        except ValueError as error:
            # Pushing gh-pages may enable Pages before the create request reaches GitHub.
            if "HTTP 409" not in str(error):
                raise
            pages = github(f"repos/{REPOSITORY}/pages")
            if pages.get("source") != source or pages.get("build_type") != "legacy":
                raise ValueError("GitHub Pages 已存在，但来源与更新分支不匹配")


def publish_site(site, bootstrap=False):
    feed = site / "appcast.xml"
    subprocess.run([str(sparkle.fetch() / "bin/sign_update"), "--verify", "--ed-key-file",
                    str(sparkle.require_signing_key()), str(feed)], check=True, capture_output=True)
    if bootstrap and ET.parse(feed).findall("./channel/item"):
        raise ValueError("初始化只能发布空清单")
    pages = github(f"repos/{REPOSITORY}/pages", missing_ok=True)
    source = {"branch": BRANCH, "path": "/"}
    if pages and (pages.get("source") != source or pages.get("build_type") != "legacy"):
        raise ValueError("现有 Pages 来源不同，未改动其配置或更新分支")
    reference = github(f"repos/{REPOSITORY}/git/ref/heads/{BRANCH}", missing_ok=True)
    parent = reference["object"]["sha"] if reference else None
    base_tree = None
    if parent:
        base_tree = github(f"repos/{REPOSITORY}/git/commits/{parent}")["tree"]["sha"]
        old = github(f"repos/{REPOSITORY}/contents/appcast.xml?ref={BRANCH}", missing_ok=True)
        if old:
            old_data = base64.b64decode(old["content"])
            if old_data == feed.read_bytes():
                ensure_pages()
                print("线上清单与本次内容一致，无需重复发布。")
                return
            if bootstrap:
                raise ValueError("更新分支已经存在；拒绝用空清单覆盖现有发布")
            namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}version"
            old_builds = [int(item.findtext(namespace, "0")) for item in ET.fromstring(old_data).findall("./channel/item")]
            new_builds = [int(item.findtext(namespace, "0")) for item in ET.parse(feed).findall("./channel/item")]
            if old_builds and (not new_builds or max(new_builds) <= max(old_builds)):
                raise ValueError("拒绝降低或替换已经公布的更新 build")
    tree = []
    for name in ["appcast.xml", ".nojekyll"]:
        content = (site / name).read_bytes()
        blob = github(f"repos/{REPOSITORY}/git/blobs", "POST",
                      {"content": base64.b64encode(content).decode(), "encoding": "base64"})
        tree.append({"path": name, "mode": "100644", "type": "blob", "sha": blob["sha"]})
    tree_data = {"tree": tree}
    if base_tree:
        tree_data["base_tree"] = base_tree
    new_tree = github(f"repos/{REPOSITORY}/git/trees", "POST", tree_data)
    commit = github(f"repos/{REPOSITORY}/git/commits", "POST", {"message": "Publish signed Yiya update feed",
                     "tree": new_tree["sha"], "parents": [parent] if parent else []})
    if parent:
        # Non-forced update prevents racing another publisher.
        github(f"repos/{REPOSITORY}/git/refs/heads/{BRANCH}", "PATCH", {"sha": commit["sha"], "force": False})
    else:
        github(f"repos/{REPOSITORY}/git/refs", "POST", {"ref": "refs/heads/" + BRANCH, "sha": commit["sha"]})
    ensure_pages()
    print("已发布更新清单：" + sparkle.config()["feed_url"] + "（等待 GitHub Pages 部署）")


def publish_release(site):
    subprocess.run([str(sparkle.fetch() / "bin/sign_update"), "--verify", "--ed-key-file",
                    str(sparkle.require_signing_key()), str(site / "appcast.xml")], check=True, capture_output=True)
    metadata = json.loads((site / "release.json").read_text())
    if metadata["repository"] != REPOSITORY:
        raise ValueError("更新附件仓库不匹配")
    if metadata["tag"] not in {"v" + metadata["version"], "v" + metadata["version"] + "-build-" + str(metadata["build"])}:
        raise ValueError("更新清单的 Release 身份不匹配")
    namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}version"
    current = [item for item in ET.parse(site / "appcast.xml").findall("./channel/item")
               if item.findtext(namespace) == str(metadata["build"])]
    if len(current) != 1:
        raise ValueError("已签名清单不包含唯一的目标 build")
    prefix = f"https://github.com/{REPOSITORY}/releases/download/{metadata['tag']}/"
    names = {asset["name"] for asset in metadata["assets"]}
    from urllib.parse import unquote
    for enclosure in current[0].iter("enclosure"):
        url = enclosure.attrib["url"]
        if not url.startswith(prefix) or unquote(url[len(prefix):]) not in names:
            raise ValueError("已签名清单与准备上传的附件不匹配")
    release = github(f"repos/{REPOSITORY}/releases/tags/{metadata['tag']}")
    if release["draft"]:
        raise ValueError("Release 仍是草稿，不能向玩家发布更新清单")
    existing = {asset["name"]: asset for asset in release["assets"]}
    for asset in metadata["assets"]:
        path = site / asset["name"]
        if path.name != asset["name"] or hashlib.sha256(path.read_bytes()).hexdigest() != asset["sha256"]:
            raise ValueError("准备后的更新附件内容改变，请重新准备")
        if asset["name"] not in existing:
            subprocess.run(["gh", "release", "upload", metadata["tag"], str(path), "--repo", REPOSITORY], check=True)
    release = github(f"repos/{REPOSITORY}/releases/tags/{metadata['tag']}")
    existing = {asset["name"]: asset for asset in release["assets"]}
    # Verify what players will download before making the feed visible.
    with tempfile.TemporaryDirectory() as temporary:
        for asset in metadata["assets"]:
            remote = existing[asset["name"]]
            download = Path(temporary) / asset["name"]
            subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--silent", "--show-error",
                            remote["browser_download_url"], "--output", str(download)], check=True)
            if hashlib.sha256(download.read_bytes()).hexdigest() != asset["sha256"]:
                raise ValueError("远端附件 SHA-256 不一致，清单未发布；不会覆盖已有同名附件")
    publish_site(site)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, default=ROOT / ".build/update-publish")
    parser.add_argument("--bootstrap", action="store_true")
    args = parser.parse_args()
    if args.bootstrap:
        publish_site(args.site, bootstrap=True)
    else:
        publish_release(args.site)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, ET.ParseError) as error:
        sys.exit(f"错误：{error}")
