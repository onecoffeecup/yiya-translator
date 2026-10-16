#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/collection-workflow-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness -Wno-unused-function -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning" -I "$ROOT_DIR/tests")
BUSINESS=("${FY_COLLECTION_WORKFLOW_SOURCES[@]}" "$ROOT_DIR/objc/ocr/FYOCRTextModels.m" "${FY_LEARNING_CORE_SOURCES[@]}" "${FY_TRANSLATION_CORE_SOURCES[@]}")
clang "${COMMON[@]}" "$ROOT_DIR/tests/CollectionWorkflowTests.m" "${BUSINESS[@]}" -framework Foundation -framework CoreGraphics -framework Carbon -framework NaturalLanguage -lsqlite3 -o "$OUT/CollectionWorkflowTests"
"$OUT/CollectionWorkflowTests"
clang "${COMMON[@]}" "$ROOT_DIR/tests/CollectionRendererTests.m" "${BUSINESS[@]}" "${FY_COLLECTION_NATIVE_RENDERING_SOURCES[@]}" "$ROOT_DIR/objc/learning/FYLearningViews.m" "$ROOT_DIR/objc/learning/FYSavedWordReferenceView.m" "$ROOT_DIR/objc/learning/FYReferenceDictionary.m" -framework Cocoa -framework QuartzCore -framework CoreGraphics -framework Carbon -framework NaturalLanguage -lsqlite3 -o "$OUT/CollectionRendererTests"
"$OUT/CollectionRendererTests"
for suite in CollectionWorkflowHostTests CollectionRendererHostTests; do
  clang "${COMMON[@]}" -include "$ROOT_DIR/tests/FYTestIsolation.h" "$ROOT_DIR/tests/$suite.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/$suite"
  "$OUT/$suite"
done
python3 - "$ROOT_DIR" "$OUT" <<'PY'
from pathlib import Path
import subprocess,sys
r=Path(sys.argv[1]);out=Path(sys.argv[2])
for name in ['FYCollectionQueryCoordinator','FYCollectionCardCoordinator','FYCollectionController','FYCollectionRenderer']:
 p=subprocess.run(['clang','-fobjc-arc','-fmodules','-mmacosx-version-min=13.0','-I',str(r/'objc'),'-x','objective-c','-M','-'],input='#import "presentation/'+name+'.h"\n',text=True,capture_output=True)
 if p.returncode:raise RuntimeError(p.stderr)
 (out/(name+'.d')).write_text(p.stdout)
 forbidden=['FYAppSupport.h','FYAppDelegateInternal.h','FYCaptureCardInput.h','FYOCRManager.h','FYSettingsStore.h','FYDiagnosticsController.h']
 if name.endswith('Coordinator'):forbidden+=['AppKit.framework']
 for path in forbidden:
  if path in p.stdout:raise AssertionError(name+' imports '+path)
 print('PASS '+name+': actual compiler dependency graph isolates UI/Root boundaries')
PY
