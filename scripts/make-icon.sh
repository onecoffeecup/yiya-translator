#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PYTHON="${PYTHON:-python3}"
if [ -x "$HOME/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3" ]; then
  PYTHON="$HOME/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3"
fi

exec "$PYTHON" "$ROOT_DIR/scripts/make-icon.py" "$@"
