#!/usr/bin/env python3
"""将已确认的「译芽 / Yiya！」图标导出为 macOS App 图标。

用法：python3 scripts/make-icon.py（macOS，使用系统 sips 和 iconutil）
源图：resources/AppIcon.png
产物：resources/AppIcon.icns 与 resources/AppIcon.iconset/

仅导出尺寸与格式，保留源图的嫩芽、像素气泡文字和透明边缘。
"""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT_DIR = Path(__file__).resolve().parent.parent
RESOURCES_DIR = ROOT_DIR / "resources"
SOURCE_PATH = RESOURCES_DIR / "AppIcon.png"
ICONSET_DIR = RESOURCES_DIR / "AppIcon.iconset"
ICNS_PATH = RESOURCES_DIR / "AppIcon.icns"

ICONSET_ENTRIES = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def main() -> int:
    if not SOURCE_PATH.is_file():
        raise SystemExit(f"缺少已确认的图标源图：{SOURCE_PATH}")

    # 完成全部导出后再替换，避免工具失败时覆盖已有可用图标。
    with tempfile.TemporaryDirectory(prefix=".AppIcon-", dir=RESOURCES_DIR) as temporary:
        staging_dir = Path(temporary)
        staging_iconset = staging_dir / "AppIcon.iconset"
        staging_iconset.mkdir()
        for size, name in ICONSET_ENTRIES:
            subprocess.run(
                ["sips", "-z", str(size), str(size), str(SOURCE_PATH),
                 "--out", str(staging_iconset / name)],
                check=True, stdout=subprocess.DEVNULL,
            )
        staging_icns = staging_dir / "AppIcon.icns"
        subprocess.run(
            ["iconutil", "-c", "icns", str(staging_iconset), "-o", str(staging_icns)],
            check=True,
        )
        if ICONSET_DIR.is_dir():
            shutil.rmtree(ICONSET_DIR)
        shutil.move(str(staging_iconset), str(ICONSET_DIR))
        staging_icns.replace(ICNS_PATH)

    print(f"生成 {ICNS_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
