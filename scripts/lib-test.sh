#!/usr/bin/env bash
# Shared TEST-only switches; never sourced by production build/install scripts.
FY_TEST_MODULE_CACHE="$ROOT_DIR/.build/test-module-cache"
mkdir -p "$FY_TEST_MODULE_CACHE"
fy_test_ui_gate() {
  if [ "${FY_TEST_COMPILE_ONLY:-0}" != 1 ] && [ "${FY_TEST_ALLOW_UI:-0}" != 1 ]; then
    echo "BLOCKED: reserve the desktop before UI tests; use run-acceptance.py --ui later." >&2
    return 86
  fi
}
fy_test_run() {
  if [ "${FY_TEST_COMPILE_ONLY:-0}" = 1 ]; then
    echo "COMPILED_ONLY: $1"
  else
    "$@"
  fi
}
