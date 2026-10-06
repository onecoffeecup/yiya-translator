#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="译芽.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
TARGET_DIR="$HOME/Applications"
TARGET_APP="$TARGET_DIR/$APP_NAME"
BACKUP_DIR="$ROOT_DIR/.build/app-backups"

"$ROOT_DIR/scripts/package-app.sh"
mkdir -p "$TARGET_DIR"
mkdir -p "$BACKUP_DIR"

if pgrep -x LiveCaptionTranslator >/dev/null 2>&1; then
  osascript -e 'tell application id "com.nanami.fuyi" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x LiveCaptionTranslator >/dev/null 2>&1 || break
    sleep 0.3
  done
  if pgrep -x LiveCaptionTranslator >/dev/null 2>&1; then
    echo "译芽仍在运行。请先退出 App，再重新运行安装脚本。" >&2
    exit 1
  fi
fi

if [ -e "$TARGET_APP" ]; then
  mv "$TARGET_APP" "$BACKUP_DIR/$APP_NAME.bak.$(date +%Y%m%d-%H%M%S)"
fi

# 旧名称与新版共用同一 bundle ID，移入备份避免 Dock/LaunchServices 再打开旧版。
LEGACY_APP="$TARGET_DIR/浮译.app"
if [ -d "$LEGACY_APP" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY_APP/Contents/Info.plist" 2>/dev/null || true)" = "com.nanami.fuyi" ]; then
  mv "$LEGACY_APP" "$BACKUP_DIR/浮译.app.bak.$(date +%Y%m%d-%H%M%S)"
fi

ditto --noextattr --noqtn "$SOURCE_APP" "$TARGET_APP"
xattr -cr "$TARGET_APP"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/"/ {print $2; exit}')"
fi
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="-"
  echo "No code-signing certificate found; using stable ad-hoc requirement for local testing."
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign \
    --force \
    --deep \
    --sign - \
    --identifier com.nanami.fuyi \
    --requirements '=designated => identifier "com.nanami.fuyi"' \
    "$TARGET_APP"
else
  codesign --force --deep --sign "$SIGN_IDENTITY" --identifier com.nanami.fuyi "$TARGET_APP"
fi
codesign --verify --strict "$TARGET_APP"

echo "Installed $TARGET_APP"
