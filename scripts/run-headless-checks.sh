#!/usr/bin/env bash
# CI/default checks: synthetic data only; no windows, clipboard or real services.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export FY_TEST_ALLOW_UI=0 FY_TEST_COMPILE_ONLY=0
python3 tests/SourceManifestTests.py
python3 tests/DistributionTests.py
python3 tests/UpdateDistributionTests.py
bash scripts/run-learning-tests.sh
python3 scripts/debug.py check
echo "Headless baseline passed; known product gaps and UI/device acceptance are listed in the Debug report."
