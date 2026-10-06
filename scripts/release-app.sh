#!/usr/bin/env bash
# 生成可分发（免费签名路线）的发布包。
#
# 用法：
#   scripts/release-app.sh              # 双架构构建 + 打包
#   scripts/release-app.sh --no-build   # 复用已有产物，只重新组装打包
#   ARCHS=arm64 scripts/release-app.sh  # 只做 Apple Silicon 包
#
# 产物：
#   dist/release/译芽-<版本>.zip         给用户下载的压缩包
#   dist/release/译芽-<版本>.zip.sha256  校验值
#
# 说明：本脚本使用 ad-hoc 签名并写入稳定的 designated requirement。
# 固定身份有助于保留权限，但不同系统/签名变化后仍可能重新要求授权。
# 未经过 Developer ID 签名及公证，首次打开见 docs/首次打开说明.md。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/lib-appbundle.sh"

DO_BUILD=1
for arg in "$@"; do
  case "$arg" in
    --no-build) DO_BUILD=0 ;;
    *) echo "未知参数：$arg" >&2; exit 2 ;;
  esac
done

VERSION="$(fy_read_version)"
BUILD_NUMBER="$(fy_read_build_number)"
RELEASE_DIR="$ROOT_DIR/dist/release"
# 项目位于文件提供方目录时，签名后也可能被重新附加 Finder 元数据。
# 在系统临时目录组装和签名，最终只把 zip 移回 dist。
STAGE_BASE="$(mktemp -d)"
STAGE_DIR="$STAGE_BASE/译芽-$VERSION"
STAGE_APP="$STAGE_DIR/译芽.app"
ZIP_PATH="$RELEASE_DIR/译芽-$VERSION.zip"
VERIFY_DIR=""
TEMP_ZIP=""
cleanup() {
  rm -rf "$STAGE_BASE"
  if [ -n "$VERIFY_DIR" ]; then rm -rf "$VERIFY_DIR"; fi
  if [ -n "$TEMP_ZIP" ]; then rm -f "$TEMP_ZIP"; fi
}
trap cleanup EXIT

echo "==> 发布 译芽 $VERSION (build $BUILD_NUMBER)"

if [ "$DO_BUILD" -eq 1 ]; then
  ARCHS="${ARCHS:-arm64 x86_64}" "$ROOT_DIR/scripts/build-app.sh"
else
  echo "==> 跳过构建（--no-build）"
fi

echo "==> 组装 bundle"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
fy_stage_app "$STAGE_APP" > /dev/null
cp "$ROOT_DIR/docs/首次打开说明.md" "$STAGE_DIR/首次打开说明.txt"
cp "$ROOT_DIR/docs/API-Key配置教程.md" "$STAGE_DIR/API-Key配置教程.txt"
cp "$ROOT_DIR/docs/首次安装验收.md" "$STAGE_DIR/首次安装验收.txt"
cp "$ROOT_DIR/docs/发布说明.md" "$STAGE_DIR/先读我.txt"
cp "$ROOT_DIR/LICENSE" "$STAGE_DIR/LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$STAGE_DIR/THIRD_PARTY_NOTICES.md"

# 组装目录可能由文件提供方附加元数据；签名前清理自己的暂存产物。
xattr -cr "$STAGE_DIR"

echo "==> ad-hoc 签名（稳定 designated requirement）"
codesign \
  --force \
  --sign - \
  --identifier "$FY_BUNDLE_ID" \
  --requirements "=designated => identifier \"$FY_BUNDLE_ID\"" \
  "$STAGE_APP"

codesign --verify --strict "$STAGE_APP"

echo "==> 校验"
echo "    架构：$(lipo -archs "$STAGE_APP/Contents/MacOS/$FY_EXECUTABLE_NAME")"
# 注意：Info.plist 绑定与资源封条信息只在 -dvvv 详细度下输出，默认详细度看不到
SIGN_INFO="$(codesign -dvvv "$STAGE_APP" 2>&1)"
echo "    标识：$(echo "$SIGN_INFO" | awk -F= '/^Identifier=/{print $2}')"
echo "    签名：$(echo "$SIGN_INFO" | awk -F= '/^Signature=/{print $2}')"

if echo "$SIGN_INFO" | grep -q 'Info.plist=not bound'; then
  echo "    错误：Info.plist 未绑定进签名。" >&2
  exit 1
fi
if ! echo "$SIGN_INFO" | grep -q '^Sealed Resources'; then
  echo "    错误：资源未封条，签名不完整。" >&2
  exit 1
fi
echo "    $(echo "$SIGN_INFO" | grep '^Sealed Resources')"

mkdir -p "$RELEASE_DIR"
if [ -e "$ZIP_PATH" ]; then
  BACKUP_DIR="$ROOT_DIR/.build/release-backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  cp "$ZIP_PATH" "$BACKUP_DIR/"
  if [ -f "$ZIP_PATH.sha256" ]; then cp "$ZIP_PATH.sha256" "$BACKUP_DIR/"; fi
fi

echo "==> 打包 zip（保留签名与扩展属性）"
TEMP_ZIP="$RELEASE_DIR/.fuyi-$VERSION.tmp.zip"
rm -f "$TEMP_ZIP"
ditto -c -k --keepParent "$STAGE_DIR" "$TEMP_ZIP"

echo "==> 回验 zip 内容"
VERIFY_DIR="$(mktemp -d)"
ditto -x -k "$TEMP_ZIP" "$VERIFY_DIR"
codesign --verify --strict "$VERIFY_DIR/译芽-$VERSION/译芽.app"
python3 "$ROOT_DIR/scripts/verify-release.py" "$VERIFY_DIR/译芽-$VERSION"
echo "    解压后签名校验通过"
mv "$TEMP_ZIP" "$ZIP_PATH"

( cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256" )

echo
echo "发布包：$ZIP_PATH"
echo "大小：$(du -h "$ZIP_PATH" | cut -f1)"
cat "$ZIP_PATH.sha256"
echo
echo "当前为 ad-hoc 签名且未公证；打开说明及配置教程已随压缩包提供。"
