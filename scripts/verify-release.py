#!/usr/bin/env python3
"""Check an unpacked release against source and the reviewed reference snapshot."""
import importlib.util
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("reference_data", ROOT / "scripts/reference-data.py")
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def main(directory):
    app = directory / "译芽.app"
    contents = app / "Contents"
    version = (ROOT / "VERSION").read_text().strip()
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    if info["CFBundleIdentifier"] != "com.nanami.fuyi" or info["CFBundleShortVersionString"] != version:
        raise ValueError("App 身份或版本与源码不匹配")
    binary = contents / "MacOS/LiveCaptionTranslator"
    import json
    updates = json.loads((ROOT / "resources/updates/sparkle-config.json").read_text())
    if info.get("SUFeedURL") != updates["feed_url"] or info.get("SUPublicEDKey") != updates["public_key"]:
        raise ValueError("更新地址或公钥与源码不匹配")
    if not info.get("SUVerifyUpdateBeforeExtraction") or not info.get("SURequireSignedFeed"):
        raise ValueError("更新包或清单签名检查未启用")
    framework = contents / "Frameworks/Sparkle.framework"
    framework_info = plistlib.loads((framework / "Resources/Info.plist").read_bytes())
    if framework_info["CFBundleShortVersionString"] != updates["sparkle_version"]:
        raise ValueError("Sparkle 版本与锁定配置不一致")
    if not (contents / "Resources/updates/Sparkle-LICENSE.txt").is_file():
        raise ValueError("缺少 Sparkle 许可说明")
    if any(contents.rglob("api-key.json")) or any(contents.rglob("ed25519.key")):
        raise ValueError("应用包含有禁止分发的凭据文件")
    unsigned = ROOT / ".build/release/LiveCaptionTranslator"
    # 签名会改变二进制字节，比较 Mach-O UUID 验证来自同一次链接。
    def uuids(path):
        output = subprocess.check_output(["dwarfdump", "--uuid", str(path)], text=True)
        identifiers = re.findall(r"^UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)", output, flags=re.MULTILINE)
        if not identifiers:
            raise ValueError("没有找到可执行文件的 Mach-O UUID")
        return sorted(identifiers)
    if uuids(binary) != uuids(unsigned):
        raise ValueError("发布包二进制与本次构建不一致")
    reference.verify(contents / "Resources/learning/reference", reference.load_lock())
    for name in ["grammar-catalog.json", "source-manifest.json", "LICENSE-NOTES.txt"]:
        if (contents / "Resources/learning" / name).read_bytes() != (ROOT / "resources/learning" / name).read_bytes():
            raise ValueError(f"发布资料与源码不一致：{name}")
    for name in ["ui-reference-atlas.png", "sakura-cat-v1.png"]:
        asset = Path("ui/yiya/art") / name
        if (contents / "Resources" / asset).read_bytes() != (ROOT / "resources" / asset).read_bytes():
            raise ValueError(f"译芽视觉素材缺失或过期：{name}")
    documents = {"首次打开说明.txt": "docs/首次打开说明.md", "API-Key配置教程.txt": "docs/API-Key配置教程.md",
                 "首次安装验收.txt": "docs/首次安装验收.md", "先读我.txt": "docs/发布说明.md",
                 "LICENSE.txt": "LICENSE", "THIRD_PARTY_NOTICES.md": "THIRD_PARTY_NOTICES.md"}
    for name, source in documents.items():
        if (directory / name).read_bytes() != (ROOT / source).read_bytes():
            raise ValueError(f"发布文档缺失或过期：{name}")
    for name in ["LICENSE.txt", "THIRD_PARTY_NOTICES.md"]:
        if (contents / "Resources" / name).read_bytes() != (directory / name).read_bytes():
            raise ValueError(f"App 内许可文件不匹配：{name}")
    print("发布包内容通过：本次构建、版本、完整词典、来源许可及首次使用文档。")


if __name__ == "__main__":
    try:
        main(Path(sys.argv[1]))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"错误：{error}")
