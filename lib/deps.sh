#!/usr/bin/env bash
# deps.sh — required and optional command-line dependencies (spec §17).

step_core_deps() {
  local failed=0
  # Minimum set. python@3.11+ satisfied by any modern python3 (checked below).
  brew_ensure git || failed=1
  brew_ensure jq || failed=1
  brew_ensure ripgrep || failed=1
  brew_ensure fd || failed=1
  brew_ensure node || failed=1

  # Python 3.11+: prefer whatever python3 resolves to; install via brew if
  # missing or too old.
  if sb_have python3 && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    report_add "dep:python3" "verified" "$(python3 --version 2>&1)"
  else
    brew_ensure python@3.12 || failed=1
  fi

  # uv preferred; pipx acceptable (plan D5).
  if sb_have uv; then
    report_add "dep:uv" "verified" "$(uv --version 2>/dev/null)"
  elif sb_have pipx; then
    report_add "dep:pipx" "verified" "uv absent; pipx will be used"
  else
    brew_ensure uv || failed=1
  fi

  [ "$failed" = "0" ]
}

step_optional_deps() {
  # Optional deps never fail the install (spec §3.2).
  if [ "${SB_WITH_OCR:-0}" = "1" ]; then
    brew_ensure tesseract || report_add "dep:tesseract" "FAILED" "optional; continuing"
    brew_ensure poppler || report_add "dep:poppler" "FAILED" "optional; continuing"
  else
    report_add "dep:ocr" "skipped" "enable with --with-ocr"
  fi
  if [ "${SB_WITH_TRANSCRIPTION:-0}" = "1" ]; then
    brew_ensure ffmpeg || report_add "dep:ffmpeg" "FAILED" "optional; continuing"
  else
    report_add "dep:transcription" "skipped" "enable with --with-transcription"
  fi
  if [ "${SB_ENABLE_LFS:-0}" = "1" ]; then
    brew_ensure git-lfs || report_add "dep:git-lfs" "FAILED" "optional; continuing"
  fi
  return 0
}
