#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

SOURCES=(
  "$ROOT_DIR/objc/LiveCaptionTranslator.m"
  "$ROOT_DIR/objc/FYAppUpdater.m"
  "$ROOT_DIR/objc/FYWindowManager.m" "$ROOT_DIR/objc/FYOCRManager.m" "$ROOT_DIR/objc/FYGeometryManager.m" "$ROOT_DIR/objc/FYTranslationManager.m"
  "$ROOT_DIR/objc/FYTranslationTrace.m" "$ROOT_DIR/objc/FYRuntimeDiagnostics.m"
  "$ROOT_DIR/objc/FYInlineLayout.m" "$ROOT_DIR/objc/FYInlineLayoutDebug.m"
  "$ROOT_DIR/objc/FYCaptureCardInput.m"
  "$ROOT_DIR/objc/learning/FYLearningModels.m"
  "$ROOT_DIR/objc/learning/FYLearningStore.m"
  "$ROOT_DIR/objc/learning/FYLearningAnalyzer.m"
  "$ROOT_DIR/objc/learning/FYJapaneseTokenizer.m"
  "$ROOT_DIR/objc/learning/FYGrammarCatalog.m"
  "$ROOT_DIR/objc/learning/FYLearningCoordinator.m"
  "$ROOT_DIR/objc/learning/FYLearningViews.m"
  "$ROOT_DIR/objc/learning/FYStudyChatView.m"
  "$ROOT_DIR/objc/learning/FYStudyChatSession.m"
  "$ROOT_DIR/objc/learning/FYGlobalShortcuts.m"
  "$ROOT_DIR/objc/learning/FYStudyOverlayPanel.m"
  "$ROOT_DIR/objc/learning/FYReferenceDictionary.m"
  "$ROOT_DIR/objc/learning/FYSavedWordReferenceView.m"
)

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
  clang \
    -fobjc-arc \
    -DFY_ENABLE_UPDATES=1 \
    -fmodules \
    -fmodules-cache-path="$MODULE_CACHE" \
    -arch "$arch" \
    -mmacosx-version-min="$MIN_MACOS" \
    -Wall \
    "${SOURCES[@]}" \
    -o "$slice" \
    "${FRAMEWORKS[@]}"
  built_slices+=("$slice")
done

if [ "${#built_slices[@]}" -eq 1 ]; then
  cp "${built_slices[0]}" "$BUILD_DIR/LiveCaptionTranslator"
else
  lipo -create "${built_slices[@]}" -output "$BUILD_DIR/LiveCaptionTranslator"
fi

for arch in $ARCHS; do
  rm -f "$BUILD_DIR/LiveCaptionTranslator.$arch"
done

echo "Built $BUILD_DIR/LiveCaptionTranslator ($(lipo -archs "$BUILD_DIR/LiveCaptionTranslator"))"
