#!/usr/bin/env bash
# checks.sh — pre-flight: macOS version, architecture, existing install.

step_preflight() {
  local os_name os_ver arch

  if [ "${SB_SKIP_OS_CHECK:-0}" = "1" ]; then
    report_add "preflight" "skipped" "SB_SKIP_OS_CHECK=1"
    return 0
  fi

  os_name="$(uname -s)"
  if [ "$os_name" != "Darwin" ]; then
    sb_err "This installer targets macOS; detected $os_name."
    return 1
  fi

  os_ver="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  arch="$(uname -m)"
  case "$arch" in
    arm64) SB_ARCH="apple-silicon"; SB_BREW_PREFIX="/opt/homebrew" ;;
    x86_64) SB_ARCH="intel"; SB_BREW_PREFIX="/usr/local" ;;
    *) sb_err "Unsupported architecture: $arch"; return 1 ;;
  esac

  # macOS 12+ required (Homebrew's own floor moves; we just sanity-check).
  local major
  major="${os_ver%%.*}"
  case "$major" in
    ''|*[!0-9]*) sb_warn "Could not parse macOS version '$os_ver'; continuing." ;;
    *)
      if [ "$major" -lt 12 ]; then
        sb_err "macOS $os_ver is older than the supported minimum (12.0)."
        return 1
      fi
      ;;
  esac

  sb_info "macOS $os_ver on $SB_ARCH"
  state_set "os_version" "\"$os_ver\""
  state_set "arch" "\"$SB_ARCH\""

  if [ -f "$SB_STATE_FILE" ] && [ "${SB_DRY_RUN:-0}" != "1" ]; then
    sb_info "existing installation state found at $SB_STATE_FILE"
  fi

  report_add "preflight" "verified" "macOS $os_ver, $SB_ARCH"
}
