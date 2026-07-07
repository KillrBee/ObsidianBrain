#!/usr/bin/env bash
# brew.sh — Homebrew bootstrap and formula installs.

step_homebrew() {
  if [ "${SB_SKIP_BREW:-0}" = "1" ]; then
    report_add "homebrew" "skipped" "SB_SKIP_BREW=1"
    return 0
  fi
  if sb_have brew; then
    report_add "homebrew" "verified" "$(brew --version 2>/dev/null | head -1)"
    return 0
  fi
  sb_info "Homebrew not found; installing (may prompt for password)…"
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    run /bin/bash -c "curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    report_add "homebrew" "installed" "dry-run"
    return 0
  fi
  if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    # Activate for this process.
    if [ -x "${SB_BREW_PREFIX:-/opt/homebrew}/bin/brew" ]; then
      eval "$("${SB_BREW_PREFIX:-/opt/homebrew}/bin/brew" shellenv)"
    fi
    report_add "homebrew" "installed" ""
  else
    return 1
  fi
}

# brew_ensure <formula> [--cask] — install if missing; report either way.
brew_ensure() {
  local formula="$1" kind="${2:-}"
  if [ "${SB_SKIP_BREW:-0}" = "1" ]; then
    report_add "dep:$formula" "skipped" "SB_SKIP_BREW=1"
    return 0
  fi
  if [ "$kind" = "--cask" ]; then
    if brew list --cask "$formula" >/dev/null 2>&1; then
      report_add "dep:$formula" "verified" "cask already installed"
      return 0
    fi
    if run brew install --cask "$formula"; then
      report_add "dep:$formula" "installed" "cask"
    else
      return 1
    fi
    return 0
  fi
  if brew list --formula "$formula" >/dev/null 2>&1 || sb_have "$formula"; then
    report_add "dep:$formula" "verified" ""
    return 0
  fi
  if run brew install "$formula"; then
    report_add "dep:$formula" "installed" ""
  else
    return 1
  fi
}
