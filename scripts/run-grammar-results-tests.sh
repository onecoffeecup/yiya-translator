#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/grammar-results-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness -Wno-unused-function -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning")
clang "${COMMON[@]}" "$ROOT_DIR/tests/GrammarResultsRendererTests.m" "${FY_GRAMMAR_RESULTS_SOURCES[@]}" "${FY_GRAMMAR_INTERACTION_SOURCES[@]}" "$ROOT_DIR/objc/FYGrammarActionState.m" "${FY_PRESENTATION_TEXT_SOURCES[@]}" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "${FY_LEARNING_CORE_SOURCES[@]}" "${FY_TRANSLATION_CORE_SOURCES[@]}" "$ROOT_DIR/objc/learning/FYLearningViews.m" -framework Cocoa -framework CoreGraphics -framework QuartzCore -framework CoreText -framework Carbon -framework NaturalLanguage -lsqlite3 -o "$OUT/GrammarResultsRendererTests"
"$OUT/GrammarResultsRendererTests"
clang "${COMMON[@]}" -include "$ROOT_DIR/tests/FYTestIsolation.h" "$ROOT_DIR/tests/GrammarResultsHostTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/GrammarResultsHostTests"
"$OUT/GrammarResultsHostTests"
python3 - "$ROOT_DIR" "$OUT" <<'PY'
from pathlib import Path
import subprocess,sys
r=Path(sys.argv[1]);out=Path(sys.argv[2]);p=subprocess.run(['clang','-fobjc-arc','-fmodules','-mmacosx-version-min=13.0','-I',str(r/'objc'),'-x','objective-c','-MM','-'],input='#import "presentation/FYGrammarPresentationController.h"\n',text=True,capture_output=True)
if p.returncode:raise RuntimeError(p.stderr)
(out/'grammar-header.d').write_text(p.stdout)
for name in ['FYAppSupport.h','FYAppDelegateInternal.h','FYCaptureCardInput.h','FYOCRManager.h','FYSettingsStore.h','FYDiagnosticsController.h','FYServiceTestController.h']:
 if name in p.stdout:raise AssertionError('Grammar public header imports '+name)
print('PASS Grammar header: actual compiler dependency graph excludes Root/support/capture/OCR/settings/diagnostics')
PY
