#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/lib-appbundle.sh"

"$ROOT_DIR/scripts/build-app.sh"

APP_DIR="$ROOT_DIR/dist/译芽.app"

# 旧包备份到 .build/app-backups，不再堆在 dist/ 里（之前 dist/ 累积了几十个 .bak）
if [ -e "$APP_DIR" ]; then
  BACKUP_DIR="$ROOT_DIR/.build/app-backups"
  mkdir -p "$BACKUP_DIR"
  mv "$APP_DIR" "$BACKUP_DIR/译芽.app.bak.$(date +%Y%m%d-%H%M%S)"
fi

fy_stage_app "$APP_DIR" > /dev/null

echo "已生成 ${APP_DIR}（版本 $(fy_read_version)，build $(fy_read_build_number)）"
echo "本地安装请运行 scripts/install-app.sh（会签名并复制到 ~/Applications）。"
echo "对外分发请运行 scripts/release-app.sh（会输出 zip 与校验值）。"
