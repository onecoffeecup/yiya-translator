#!/usr/bin/env python3
"""Pinned Sparkle dependency, bundle configuration and publisher signing identity."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "resources/updates/sparkle-config.json"


def config():
    return json.loads(CONFIG.read_text())


def distribution():
    # Documents may be managed by a file provider that re-adds Finder metadata.
    # Keep signed vendor binaries in the normal build cache outside that provider.
    cache = Path(os.environ.get("FY_SPARKLE_CACHE_DIR", str(Path.home() / "Library/Caches/com.nanami.fuyi-build")))
    return cache / ("Sparkle-" + config()["sparkle_version"])


def fetch():
    settings = config()
    destination = distribution()
    framework = destination / "Sparkle.framework"
    if not (destination / ".verified-sha256").is_file():
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
            temporary = Path(temporary)
            archive = temporary / "Sparkle.tar.xz"
            subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--silent", "--show-error",
                            settings["download_url"], "--output", str(archive)], check=True)
            if hashlib.sha256(archive.read_bytes()).hexdigest() != settings["sha256"]:
                raise ValueError("Sparkle 下载 SHA-256 不匹配")
            unpacked = temporary / "unpacked"
            unpacked.mkdir()
            subprocess.run(["tar", "-xf", str(archive), "-C", str(unpacked)], check=True)
            subprocess.run(["xattr", "-cr", str(unpacked)], check=True)
            (unpacked / ".verified-sha256").write_text(settings["sha256"])
            if destination.exists():
                raise ValueError("Sparkle 缓存不完整，请检查后移走缓存目录再下载")
            shutil.move(str(unpacked), destination)
    if (destination / ".verified-sha256").read_text().strip() != settings["sha256"]:
        raise ValueError("Sparkle 缓存版本与锁定的校验值不一致")
    info = plistlib.loads((framework / "Resources/Info.plist").read_bytes())
    if info["CFBundleShortVersionString"] != settings["sparkle_version"]:
        raise ValueError("Sparkle framework 版本不匹配")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(framework)], check=True)
    return destination


def private_key_path():
    default = Path.home() / "Library/Application Support/com.nanami.fuyi-publisher/updates/ed25519.key"
    path = Path(os.environ.get("FY_UPDATE_PRIVATE_KEY_FILE", str(default))).expanduser().resolve()
    if path == ROOT or ROOT in path.parents:
        raise ValueError("更新私钥必须保存在源码目录之外")
    return path


def public_key_for_private_file():
    path = private_key_path()
    if path.exists() and (stat.S_IMODE(path.stat().st_mode) != 0o600 or
                          stat.S_IMODE(path.parent.stat().st_mode) != 0o700):
        raise ValueError("更新私钥文件须为 0600，所在目录须为 0700")
    seed = base64.b64decode(path.read_text().strip(), validate=True) if path.exists() else os.urandom(32)
    if len(seed) != 32:
        raise ValueError("更新私钥格式错误（需要 32-byte Ed25519 seed）")
    # Use an existing OpenSSL 3 publisher tool; never pass the seed on a command line.
    candidates = [os.environ.get("FY_OPENSSL"), shutil.which("openssl"),
                  "/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl"]
    public = None
    for candidate in dict.fromkeys(item for item in candidates if item):
        if not Path(candidate).is_file():
            continue
        result = subprocess.run([candidate, "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
                                input=bytes.fromhex("302e020100300506032b657004220420") + seed,
                                capture_output=True)
        if result.returncode == 0 and result.stdout.startswith(bytes.fromhex("302a300506032b6570032100")) and len(result.stdout) == 44:
            public = base64.b64encode(result.stdout[-32:]).decode()
            break
    if not public:
        raise ValueError("发布私钥管理需要支持 Ed25519 的 OpenSSL 3；可通过 FY_OPENSSL 指定已有工具")
    if not path.exists():
        path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
        if stat.S_IMODE(path.parent.stat().st_mode) != 0o700:
            raise ValueError("更新私钥目录须为 0700")
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as output:
            output.write(base64.b64encode(seed).decode() + "\n")
    return public


def require_signing_key():
    if not private_key_path().is_file():
        raise ValueError("缺少维护者更新私钥；在原发布机器配置 FY_UPDATE_PRIVATE_KEY_FILE，勿另生成替代密钥")
    if public_key_for_private_file() != config()["public_key"]:
        raise ValueError("本机更新私钥与应用内公钥不匹配")
    return private_key_path()


def stage(app):
    settings = config()
    if len(base64.b64decode(settings["public_key"], validate=True)) != 32:
        raise ValueError("缺少有效更新公钥")
    contents = app / "Contents"
    framework = contents / "Frameworks/Sparkle.framework"
    framework.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ditto", str(fetch() / "Sparkle.framework"), str(framework)], check=True)
    license_dir = contents / "Resources/updates"
    license_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(distribution() / "LICENSE", license_dir / "Sparkle-LICENSE.txt")
    info_path = contents / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info.update(SUFeedURL=settings["feed_url"], SUPublicEDKey=settings["public_key"],
                SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=False, SUEnableSystemProfiling=False,
                SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True)
    info_path.write_bytes(plistlib.dumps(info, sort_keys=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["fetch", "stage", "init-key", "verify-key"])
    parser.add_argument("app", nargs="?", type=Path)
    args = parser.parse_args()
    if args.command == "fetch":
        print(fetch())
    elif args.command == "stage":
        if not args.app:
            parser.error("stage requires an app bundle path")
        stage(args.app)
    elif args.command == "init-key":
        settings = config()
        if settings["public_key"] and not private_key_path().is_file():
            raise ValueError("已有发布公钥但本机私钥缺失，不允许生成替代身份；请恢复原私钥")
        key = public_key_for_private_file()
        if settings["public_key"] and settings["public_key"] != key:
            raise ValueError("已有发布公钥，不允许自动替换更新身份")
        settings["public_key"] = key
        CONFIG.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + "\n")
        print("更新签名密钥已准备；仅公钥写入源码，私钥留在维护者本机。")
    else:
        require_signing_key()
        print("更新签名身份匹配，权限正确。")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"错误：{error}")
