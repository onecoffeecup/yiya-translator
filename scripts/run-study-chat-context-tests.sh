#!/usr/bin/env bash
set -euo pipefail
FY_OPT="${FY_OPT:--O0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-sources.sh"
OUT="$ROOT_DIR/.build/study-chat-context-tests/${FY_OPT#-}"
mkdir -p "$OUT"
COMMON=("$FY_OPT" -fobjc-arc -fmodules -mmacosx-version-min=13.0 -Wall -Wno-nullability-completeness -Wno-unused-function -fmodules-cache-path="$OUT/module-cache" -I "$ROOT_DIR/objc" -I "$ROOT_DIR/objc/learning")
clang "${COMMON[@]}" "$ROOT_DIR/tests/StudyChatContextTests.m" "${FY_STUDY_CHAT_CONTEXT_SOURCES[@]}" "${FY_STUDY_CHAT_SESSION_SOURCES[@]}" "${FY_LEARNING_CORE_SOURCES[@]}" "${FY_TRANSLATION_CORE_SOURCES[@]}" -framework Foundation -framework CoreGraphics -framework Carbon -framework NaturalLanguage -lsqlite3 -o "$OUT/StudyChatContextTests"
"$OUT/StudyChatContextTests"
clang "${COMMON[@]}" -include "$ROOT_DIR/tests/FYTestIsolation.h" "$ROOT_DIR/tests/StudyChatContextHostTests.m" "$ROOT_DIR/tests/FYTestIsolation.m" "$ROOT_DIR/tests/FYTestCaptureCardInput.m" "${FY_APP_LINK_SOURCES[@]}" -framework Cocoa -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework QuartzCore -framework Vision -framework Carbon -framework NaturalLanguage -framework AVFoundation -framework CoreImage -framework CoreMedia -framework CoreVideo -lsqlite3 -o "$OUT/StudyChatContextHostTests"
"$OUT/StudyChatContextHostTests"
python3 - "$ROOT_DIR" "$OUT" <<'PY'
from pathlib import Path
import subprocess,sys
r=Path(sys.argv[1]);out=Path(sys.argv[2]);p=subprocess.run(['clang','-fobjc-arc','-fmodules','-mmacosx-version-min=13.0','-I',str(r/'objc'),'-x','objective-c','-M','-'],input='#import "presentation/FYStudyChatContextCoordinator.h"\n',text=True,capture_output=True)
if p.returncode:raise RuntimeError(p.stderr)
(out/'study-chat-business-header.d').write_text(p.stdout)
for name in ['AppKit.framework','FYAppSupport.h','FYAppDelegateInternal.h','FYCaptureCardInput.h','FYOCRManager.h','FYSettingsStore.h','FYDiagnosticsController.h']:
 if name in p.stdout:raise AssertionError('Study chat business header imports '+name)
print('PASS Study chat business header: actual compiler graph is Foundation/domain only, no UI/Root/private/capture/settings/diagnostics')
PY
