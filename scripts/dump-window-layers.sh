#!/usr/bin/env bash
# 只读窗口层级诊断。默认只列屏幕上的窗口；--all 连其他 Space/隐藏窗口一起列。
#   scripts/dump-window-layers.sh [--all] [--json]
#   scripts/dump-window-layers.sh --watch <秒> [间隔秒=2]   持续记录到 .build/window-layers/timeline.jsonl
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT_DIR/.build/window-layers"
mkdir -p "$OUT"
clang -fobjc-arc -fmodules -fmodules-cache-path="$ROOT_DIR/.build/modulecache" \
  -mmacosx-version-min=13.0 -Wall \
  "$ROOT_DIR/tools/WindowLayerDump.m" -o "$OUT/WindowLayerDump" \
  -framework Cocoa -framework CoreGraphics
if [ "${1:-}" = "--watch" ]; then
  SECONDS_TO_RUN="${2:?用法: --watch <秒> [间隔秒]}"
  INTERVAL="${3:-2}"
  TIMELINE="$OUT/timeline.jsonl"
  : > "$TIMELINE"
  echo "开始记录窗口层级 ${SECONDS_TO_RUN} 秒（每 ${INTERVAL} 秒一次）→ $TIMELINE"
  END=$(( $(date +%s) + SECONDS_TO_RUN ))
  while [ "$(date +%s)" -lt "$END" ]; do
    "$OUT/WindowLayerDump" --json >> "$TIMELINE"
    sleep "$INTERVAL"
  done
  echo "记录结束：$(wc -l < "$TIMELINE" | tr -d ' ') 条"
  exit 0
fi
"$OUT/WindowLayerDump" "$@"
