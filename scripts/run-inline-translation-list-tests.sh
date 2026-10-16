#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/inline-translation-list-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness -Wno-unused-function -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning")
PURE=("${FY_INLINE_TRANSLATION_LIST_COORDINATION_SOURCES[@]}" "$ROOT_DIR/objc/presentation/FYInlineBlockSnapshot.m" "${FY_PRESENTATION_TEXT_SOURCES[@]}" "${FY_INLINE_MODEL_SOURCES[@]}" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m")
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineTranslationListCoordinatorTests.m" "${PURE[@]}" -framework Foundation -framework CoreGraphics -o "$OUT/InlineTranslationListCoordinatorTests"
"$OUT/InlineTranslationListCoordinatorTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/InlineTranslationListRendererTests.m" "${PURE[@]}" "${FY_INLINE_TRANSLATION_LIST_RENDERING_SOURCES[@]}" -framework Foundation -framework CoreGraphics -framework AppKit -framework CoreText -o "$OUT/InlineTranslationListRendererTests"
"$OUT/InlineTranslationListRendererTests"
clang "${COMMON[@]}" -include "$ROOT_DIR/tests/FYTestIsolation.h" "$ROOT_DIR/tests/InlineTranslationListHostTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/InlineTranslationListHostTests"
"$OUT/InlineTranslationListHostTests"
