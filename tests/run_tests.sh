#!/usr/bin/env bash
# run_tests.sh — bats + pytest entry point. Flags: --bats-only, --pytest-only.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

RUN_BATS=1 RUN_PYTEST=1
case "${1:-}" in
  --bats-only) RUN_PYTEST=0 ;;
  --pytest-only) RUN_BATS=0 ;;
esac

# Prefer the dev venv for all python in tests.
if [ -z "${SB_TEST_PYTHON:-}" ] && [ -x "$REPO_ROOT/.venv/bin/python" ]; then
  export SB_TEST_PYTHON="$REPO_ROOT/.venv/bin/python"
fi

FAILED=0

if [ "$RUN_BATS" = "1" ]; then
  if command -v bats >/dev/null 2>&1; then
    echo "== bats =="
    bats --print-output-on-failure tests/bats || FAILED=1
  else
    echo "bats not installed (brew install bats-core) — skipping shell tests" >&2
    FAILED=1
  fi
fi

if [ "$RUN_PYTEST" = "1" ]; then
  PY="${SB_TEST_PYTHON:-python3}"
  echo "== pytest =="
  "$PY" -m pytest tests/pytest -q || FAILED=1
fi

exit "$FAILED"
