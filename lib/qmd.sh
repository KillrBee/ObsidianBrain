#!/usr/bin/env bash
# qmd.sh — QMD lookup layer (spec §4.4, §21), backed by tobi/qmd
# (npm: @tobilu/qmd). Vault collections are registered under an "sb-" name
# prefix so they never collide with the user's own QMD collections.
# When QMD is absent the search wrappers serve the identical JSON contract
# through the built-in ripgrep backend, so this step never blocks an install.

step_qmd() {
  if [ "${SB_SKIP_TOOLS:-0}" = "1" ]; then
    report_add "qmd" "skipped" "SB_SKIP_TOOLS=1 (ripgrep backend active)"
    state_set "search_backend" '"ripgrep"'
    return 0
  fi

  if sb_have qmd; then
    report_add "qmd" "verified" "$(qmd --version 2>/dev/null | head -1)"
    state_set "search_backend" '"qmd"'
    return 0
  fi

  # Optional custom install hook takes precedence, e.g.
  # SB_QMD_INSTALL_CMD="bun install -g @tobilu/qmd".
  if [ -n "${SB_QMD_INSTALL_CMD:-}" ]; then
    if run /bin/bash -c "$SB_QMD_INSTALL_CMD" && sb_have qmd; then
      report_add "qmd" "installed" "via SB_QMD_INSTALL_CMD"
      state_set "search_backend" '"qmd"'
      return 0
    fi
    sb_warn "SB_QMD_INSTALL_CMD did not produce a working qmd binary."
  elif sb_have npm; then
    if run npm install -g @tobilu/qmd; then
      if sb_have qmd || [ "${SB_DRY_RUN:-0}" = "1" ]; then
        report_add "qmd" "installed" "@tobilu/qmd via npm"
        state_set "search_backend" '"qmd"'
        return 0
      fi
    fi
    sb_warn "npm install -g @tobilu/qmd failed (permissions?)."
  fi

  report_add "qmd" "FAILED" "install failed; search falls back to the built-in ripgrep backend"
  state_set "search_backend" '"ripgrep"'
  return 0   # search still works; do not block the install
}

step_qmd_collections() {
  # Collection definitions are payload config (60-index-config/qmd/collections.yaml),
  # already copied by step_payload. With a real QMD binary, mirror them into
  # QMD (sb-<name>) and build the index.
  local cfg="$SB_VAULT_DIR/60-index-config/qmd/collections.yaml"
  if [ ! -e "$cfg" ] && [ "${SB_DRY_RUN:-0}" != "1" ]; then
    sb_err "collections.yaml missing — payload step must run first"
    return 1
  fi
  if { [ -n "${SB_QMD_BIN:-}" ] && [ -x "${SB_QMD_BIN:-}" ]; } || sb_have qmd; then
    if run "$SB_VAULT_DIR/70-scripts/index/update_qmd_indexes.sh" --vault "$SB_VAULT_DIR" --register; then
      report_add "qmd-collections" "configured" "registered as sb-* collections; index built"
    else
      report_add "qmd-collections" "FAILED" "registration failed; ripgrep backend still functional"
    fi
  else
    report_add "qmd-collections" "configured" "collections.yaml in place (ripgrep backend reads it directly)"
  fi
  return 0
}

uninstall_qmd() {
  # Remove only our namespaced collections; the qmd tool and the user's own
  # collections are left alone.
  local qmd_bin="${SB_QMD_BIN:-}"
  [ -n "$qmd_bin" ] || qmd_bin="$(command -v qmd 2>/dev/null || true)"
  [ -n "$qmd_bin" ] || return 0
  local cfg="$SB_VAULT_DIR/60-index-config/qmd/collections.yaml"
  [ -f "$cfg" ] || return 0
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    "$qmd_bin" collection remove "sb-$name" >/dev/null 2>&1 || true
  done <<EOF
$(sb_python - "$cfg" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f) or {}
for name in (cfg.get("collections") or {}):
    print(name)
PYEOF
)
EOF
  report_add "qmd-collections" "configured" "sb-* collections removed"
}
