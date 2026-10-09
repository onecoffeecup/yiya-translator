#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
cd "$ROOT_DIR"

python3 "$ROOT_DIR/scripts/reference-data.py" check
SPARKLE_DIR="$(python3 "$ROOT_DIR/scripts/sparkle.py" fetch)"

# 默认构建 Intel + Apple Silicon 双架构，保证 Intel Mac 用户也能打开。
# 本地快速迭代可用 ARCHS=arm64 scripts/build-app.sh 只编一个架构。
ARCHS="${ARCHS:-arm64 x86_64}"
MIN_MACOS="${MIN_MACOS:-13.0}"

BUILD_DIR="$ROOT_DIR/.build/release"
MODULE_CACHE="$ROOT_DIR/.build/modulecache"
mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

SOURCES=("${FY_APP_SOURCES[@]}")
FRAMEWORKS=(
  -F "$SPARKLE_DIR" -framework Sparkle
  -Wl,-rpath,@executable_path/../Frameworks
  -framework Cocoa -framework Security -framework UniformTypeIdentifiers
  -framework CoreGraphics
  -framework QuartzCore
  -framework Vision
  -framework Carbon -framework NaturalLanguage
  # 采集卡输入：AVFoundation 读视频帧，CoreImage/CoreVideo 做像素缓冲转换。
  -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo
  -lsqlite3
)

built_slices=()

for arch in $ARCHS; do
  echo "==> 编译 $arch"
  slice="$BUILD_DIR/LiveCaptionTranslator.$arch"
  objects_dir="$BUILD_DIR/objects/$arch"
  mkdir -p "$objects_dir"
  objects=()
  # Keep compilation objects until dsymutil has collected both architectures.
  # Direct compile-and-link commands discard the temporary DWARF objects.
  for source in "${SOURCES[@]}"; do
    object="$objects_dir/$(basename "${source%.m}").o"
    clang -c -O2 -g -fobjc-arc -DFY_ENABLE_UPDATES=1 -fmodules \
      -fmodules-cache-path="$MODULE_CACHE" -F "$SPARKLE_DIR" \
      -arch "$arch" -mmacosx-version-min="$MIN_MACOS" -Wall \
      "$source" -o "$object"
    objects+=("$object")
  done
  clang -g -arch "$arch" -mmacosx-version-min="$MIN_MACOS" \
    "${objects[@]}" -o "$slice" "${FRAMEWORKS[@]}"
  built_slices+=("$slice")
done

if [ "${#built_slices[@]}" -eq 1 ]; then
  cp "${built_slices[0]}" "$BUILD_DIR/LiveCaptionTranslator"
else
  lipo -create "${built_slices[@]}" -output "$BUILD_DIR/LiveCaptionTranslator"
fi

DSYM="$BUILD_DIR/LiveCaptionTranslator.dSYM"
dsymutil "$BUILD_DIR/LiveCaptionTranslator" -o "$DSYM"
diff <(dwarfdump --uuid "$BUILD_DIR/LiveCaptionTranslator" | awk '{print $2, $3}' | sort) \
     <(dwarfdump --uuid "$DSYM" | awk '{print $2, $3}' | sort)

for arch in $ARCHS; do
  rm -f "$BUILD_DIR/LiveCaptionTranslator.$arch"
done

echo "Built $BUILD_DIR/LiveCaptionTranslator ($(lipo -archs "$BUILD_DIR/LiveCaptionTranslator"))"
echo "Debug symbols: $DSYM (UUIDs verified)"
