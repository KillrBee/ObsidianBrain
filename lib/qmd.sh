#!/usr/bin/env bash
# qmd.sh — QMD lookup layer (spec §4.4, §21). QMD's distribution channel is
# not stable enough to hard-code (plan R1); the search wrappers guarantee the
# JSON contract via the built-in ripgrep backend whenever QMD is absent.

step_qmd() {
  if [ "${SB_SKIP_TOOLS:-0}" = "1" ]; then
    report_add "qmd" "skipped" "SB_SKIP_TOOLS=1 (ripgrep backend active)"
    state_set "search_backend" '"ripgrep"'
    return 0
  fi

  if sb_have qmd; then
    report_add "qmd" "verified" "$(command -v qmd)"
    state_set "search_backend" '"qmd"'
    return 0
  fi

  # Optional custom install hook, e.g. SB_QMD_INSTALL_CMD="npm install -g qmd".
  if [ -n "${SB_QMD_INSTALL_CMD:-}" ]; then
    if run /bin/bash -c "$SB_QMD_INSTALL_CMD" && sb_have qmd; then
      report_add "qmd" "installed" "via SB_QMD_INSTALL_CMD"
      state_set "search_backend" '"qmd"'
      return 0
    fi
    sb_warn "SB_QMD_INSTALL_CMD did not produce a working qmd binary."
  fi

  report_add "qmd" "skipped" "qmd binary not found; search uses built-in ripgrep backend"
  state_set "search_backend" '"ripgrep"'
  return 0
}

step_qmd_collections() {
  # Collection definitions are payload config (60-index-config/qmd/collections.yaml),
  # already copied by step_payload. If a real QMD binary exists, register them.
  local cfg="$SB_VAULT_DIR/60-index-config/qmd/collections.yaml"
  if [ ! -e "$cfg" ] && [ "${SB_DRY_RUN:-0}" != "1" ]; then
    sb_err "collections.yaml missing — payload step must run first"
    return 1
  fi
  if sb_have qmd; then
    if run "$SB_VAULT_DIR/70-scripts/index/update_qmd_indexes.sh" --vault "$SB_VAULT_DIR" --register; then
      report_add "qmd-collections" "configured" "registered from collections.yaml"
    else
      report_add "qmd-collections" "FAILED" "registration failed; ripgrep backend still functional"
    fi
  else
    report_add "qmd-collections" "configured" "collections.yaml in place (ripgrep backend reads it directly)"
  fi
  return 0
}
