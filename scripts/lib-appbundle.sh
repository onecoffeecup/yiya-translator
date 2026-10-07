#!/usr/bin/env bash
# 译芽 App bundle 组装逻辑（package-app.sh 与 release-app.sh 共用，避免两份 Info.plist 走偏）
#
# 提供函数：
#   fy_read_version               → 打印版本号（来自仓库根目录 VERSION）
#   fy_read_build_number          → 打印构建号（git 提交数，单调递增，便于以后做更新检查）
#   fy_stage_app <目标.app 路径>   → 用 .build/release 的产物组装完整 bundle

set -euo pipefail

FY_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FY_BUNDLE_ID="com.nanami.fuyi"
FY_APP_NAME="译芽"
FY_EXECUTABLE_NAME="LiveCaptionTranslator"
FY_MIN_MACOS="13.0"

fy_read_version() {
  local version_file="$FY_ROOT_DIR/VERSION"
  if [ ! -f "$version_file" ]; then
    echo "缺少 $version_file" >&2
    return 1
  fi
  local version
  version="$(tr -d '[:space:]' < "$version_file")"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION 必须是三段数字版本号" >&2
    return 1
  fi
  echo "$version"
}

fy_read_build_number() {
  if [ -n "${FY_BUILD_NUMBER:-}" ]; then
    if [[ ! "$FY_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
      echo "FY_BUILD_NUMBER 必须是正整数" >&2
      return 1
    fi
    echo "$FY_BUILD_NUMBER"
    return
  fi
  local count
  count="$(git -C "$FY_ROOT_DIR" rev-list --count HEAD 2>/dev/null || true)"
  if [ -z "$count" ]; then
    count=1
  fi
  echo "$count"
}

fy_stage_app() {
  local app_dir="$1"
  local version build_number

  version="$(fy_read_version)"
  build_number="$(fy_read_build_number)"

  local binary="$FY_ROOT_DIR/.build/release/LiveCaptionTranslator"
  if [ ! -f "$binary" ]; then
    echo "找不到可执行文件 ${binary}，请先运行 scripts/build-app.sh" >&2
    return 1
  fi

  local contents_dir="$app_dir/Contents"
  local macos_dir="$contents_dir/MacOS"
  local resources_dir="$contents_dir/Resources"

  rm -rf "$app_dir"
  mkdir -p "$macos_dir" "$resources_dir/learning"

  cp "$binary" "$macos_dir/$FY_EXECUTABLE_NAME"
  mkdir -p "$resources_dir/ui/pixel-adventure/art-v3"
  cp "$FY_ROOT_DIR/resources/ui/pixel-adventure/art-v3/art-atlas.png" "$resources_dir/ui/pixel-adventure/art-v3/"

  mkdir -p "$resources_dir/ui/yiya/art"
  cp "$FY_ROOT_DIR/resources/ui/yiya/art/ui-reference-atlas.png" "$resources_dir/ui/yiya/art/"
  cp "$FY_ROOT_DIR/resources/ui/yiya/art/sakura-cat-v1.png" "$resources_dir/ui/yiya/art/"

  cp "$FY_ROOT_DIR/resources/learning/grammar-catalog.json" "$resources_dir/learning/"
  cp "$FY_ROOT_DIR/resources/learning/source-manifest.json" "$resources_dir/learning/"
  cp "$FY_ROOT_DIR/resources/learning/LICENSE-NOTES.txt" "$resources_dir/learning/"
  python3 "$FY_ROOT_DIR/scripts/reference-data.py" stage "$resources_dir/learning/reference" > /dev/null
  cp "$FY_ROOT_DIR/LICENSE" "$resources_dir/LICENSE.txt"
  cp "$FY_ROOT_DIR/THIRD_PARTY_NOTICES.md" "$resources_dir/THIRD_PARTY_NOTICES.md"

  if [ -f "$FY_ROOT_DIR/resources/AppIcon.icns" ]; then
    cp "$FY_ROOT_DIR/resources/AppIcon.icns" "$resources_dir/AppIcon.icns"
  else
    echo "提示：resources/AppIcon.icns 不存在，将使用系统默认图标。可运行 scripts/make-icon.sh 生成。" >&2
  fi

  cat > "$contents_dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$FY_EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$FY_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$FY_APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$FY_APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$build_number</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$FY_MIN_MACOS</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSCameraUsageDescription</key>
  <string>「采集卡」识别输入源需要访问你选择的采集卡设备，仅用于在本机读取游戏画面做文字识别。不录制、不保存、不上传视频，也不使用麦克风；默认不访问内置或手机摄像头。</string>
</dict>
</plist>
PLIST

  printf 'APPL????' > "$contents_dir/PkgInfo"
  python3 "$FY_ROOT_DIR/scripts/sparkle.py" stage "$app_dir"

  echo "$app_dir"
}
