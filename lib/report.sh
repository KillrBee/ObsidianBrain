#!/usr/bin/env bash
# report.sh — final installation report (spec §16.28, §24.14).

step_report() {
  local ts report_md
  ts="$(date '+%Y%m%d-%H%M%S')"

  sb_step "Installation report"
  printf '\n%-34s %-12s %s\n' "COMPONENT" "STATUS" "DETAIL"
  printf '%-34s %-12s %s\n' "---------" "------" "------"
  while IFS='|' read -r component status detail; do
    [ -n "$component" ] || continue
    printf '%-34s %-12s %s\n' "$component" "$status" "$detail"
  done <"$SB_REPORT_ROWS"
  printf '\n'

  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    sb_info "dry-run: report not written to disk"
    return 0
  fi

  report_md="$SB_VAULT_DIR/80-logs/install-report-$ts.md"
  {
    printf '# SecondBrain installation report\n\n'
    printf -- '- installer version: %s\n' "$SB_VERSION"
    printf -- '- mode: %s%s\n' "$SB_MODE" "$([ "${SB_UPGRADE:-0}" = "1" ] && echo ' (upgrade)')"
    printf -- '- date: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')"
    printf -- '- vault: %s\n\n' "$SB_VAULT_DIR"
    printf '| component | status | detail |\n|---|---|---|\n'
    while IFS='|' read -r component status detail; do
      [ -n "$component" ] || continue
      printf '| %s | %s | %s |\n' "$component" "$status" "$detail"
    done <"$SB_REPORT_ROWS"
    printf '\n'
    if [ "$SB_STEP_FAILURES" -gt 0 ]; then
      # shellcheck disable=SC2016  # backticks are literal markdown here
      printf '**%s step(s) failed.** Re-run with `--repair` after addressing the detail column.\n' "$SB_STEP_FAILURES"
    else
      printf 'All steps completed. Open %s in Obsidian (Open folder as vault) to start.\n' "$SB_VAULT_DIR"
    fi
  } >"$report_md" 2>/dev/null || { sb_warn "could not write $report_md"; return 0; }

  # Preserve the full action log alongside the report.
  if [ -n "${SB_LOG_FILE:-}" ] && [ -f "$SB_LOG_FILE" ]; then
    cp "$SB_LOG_FILE" "$SB_VAULT_DIR/80-logs/install-$ts.log" 2>/dev/null || true
  fi

  sb_ok "report written to $report_md"
  state_set "last_install" "\"$(date '+%Y-%m-%dT%H:%M:%S')\""
  state_set "installer_version" "\"$SB_VERSION\""
}
