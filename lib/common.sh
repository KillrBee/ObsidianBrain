#!/usr/bin/env bash
# common.sh — logging, dry-run execution, backups, report accumulation.
# Sourced by install.sh. Must stay bash-3.2 compatible (macOS stock bash):
# no associative arrays, no mapfile, no ${var,,}.

# ---------------------------------------------------------------- colors ----
if [ -t 1 ]; then
  SB_C_RED=$'\033[31m'; SB_C_GRN=$'\033[32m'; SB_C_YLW=$'\033[33m'
  SB_C_BLU=$'\033[34m'; SB_C_BLD=$'\033[1m'; SB_C_RST=$'\033[0m'
else
  SB_C_RED=""; SB_C_GRN=""; SB_C_YLW=""; SB_C_BLU=""; SB_C_BLD=""; SB_C_RST=""
fi

# ---------------------------------------------------------------- logging ---
_sb_log_line() {
  # Append plain (uncolored) line to the log file when one is configured.
  if [ -n "${SB_LOG_FILE:-}" ]; then
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" >>"$SB_LOG_FILE" 2>/dev/null || true
  fi
}

sb_info() { printf '%s\n' "  $*";                              _sb_log_line "INFO  $*"; }
sb_ok()   { printf '%s\n' "  ${SB_C_GRN}ok${SB_C_RST} $*";     _sb_log_line "OK    $*"; }
sb_warn() { printf '%s\n' "  ${SB_C_YLW}warn${SB_C_RST} $*";   _sb_log_line "WARN  $*"; }
sb_err()  { printf '%s\n' "  ${SB_C_RED}error${SB_C_RST} $*" >&2; _sb_log_line "ERROR $*"; }
sb_step() { printf '\n%s\n' "${SB_C_BLD}${SB_C_BLU}==>${SB_C_RST}${SB_C_BLD} $*${SB_C_RST}"; _sb_log_line "STEP  $*"; }

die() { sb_err "$*"; exit 1; }

sb_have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------ dry-run exec --
# run <cmd> [args...] — execute unless SB_DRY_RUN=1, in which case print only.
run() {
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    printf '%s\n' "  ${SB_C_YLW}[dry-run]${SB_C_RST} $*"
    _sb_log_line "DRYRUN $*"
    return 0
  fi
  _sb_log_line "RUN   $*"
  "$@"
}

# ensure_dir <dir> — mkdir -p, dry-run aware.
ensure_dir() {
  if [ -d "$1" ]; then return 0; fi
  run mkdir -p "$1"
}

# backup_file <path> — copy to <path>.bak.<ts> if it exists. Echoes backup path.
backup_file() {
  local src="$1" ts bak
  [ -e "$src" ] || return 0
  ts="$(date '+%Y%m%d%H%M%S')"
  bak="${src}.bak.${ts}"
  # Avoid clobbering a same-second backup.
  local n=1
  while [ -e "$bak" ]; do bak="${src}.bak.${ts}.${n}"; n=$((n + 1)); done
  run cp -p "$src" "$bak" || return 1
  sb_info "backed up $(basename "$src") -> $(basename "$bak")"
  printf '%s\n' "$bak"
}

# write_file <dest> <mode> — write stdin to dest atomically, dry-run aware.
# Never overwrites silently: caller decides whether to backup_file first.
write_file() {
  local dest="$1" mode="${2:-0644}" tmp
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    printf '%s\n' "  ${SB_C_YLW}[dry-run]${SB_C_RST} write $dest (mode $mode)"
    cat >/dev/null   # drain stdin
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp "${dest}.tmp.XXXXXX")" || return 1
  cat >"$tmp" || { rm -f "$tmp"; return 1; }
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$dest"
  _sb_log_line "WRITE $dest"
}

# render_template <template> — substitute {{VAULT_DIR}} {{VERSION}} {{DATE}}
# {{INSTALLER_ROOT}} placeholders on stdout.
render_template() {
  local tpl="$1"
  sed \
    -e "s|{{VAULT_DIR}}|${SB_VAULT_DIR}|g" \
    -e "s|{{VERSION}}|${SB_VERSION}|g" \
    -e "s|{{DATE}}|$(date '+%Y-%m-%d')|g" \
    -e "s|{{INSTALLER_ROOT}}|${SB_INSTALLER_ROOT}|g" \
    "$tpl"
}

# --------------------------------------------------------------- reporting --
# Rows accumulate as pipe-delimited lines: component|status|detail
# status vocabulary: installed | verified | configured | skipped | FAILED
report_add() {
  local component="$1" status="$2" detail="${3:-}"
  [ -n "${SB_REPORT_ROWS:-}" ] || return 0
  printf '%s|%s|%s\n' "$component" "$status" "$detail" >>"$SB_REPORT_ROWS"
  case "$status" in
    FAILED) sb_err  "$component: $detail" ;;
    warning) sb_warn "$component: $detail" ;;
    skipped) sb_info "$component: skipped${detail:+ ($detail)}" ;;
    *)      sb_ok   "$component: $status${detail:+ ($detail)}" ;;
  esac
}

# step_run <component> <fn> [args...] — run an install step function.
# The function returns 0 on success (it does its own report_add), non-zero on
# failure (step_run records FAILED). Failures do not abort the installer;
# SB_STEP_FAILURES counts them for the exit code.
SB_STEP_FAILURES=0
step_run() {
  local component="$1"; shift
  sb_step "$component"
  if "$@"; then
    return 0
  fi
  report_add "$component" "FAILED" "step function $1 returned non-zero"
  SB_STEP_FAILURES=$((SB_STEP_FAILURES + 1))
  return 0
}

# ------------------------------------------------------------ interaction ---
# ask <prompt> <default> — echo answer; non-interactive mode returns default.
ask() {
  local prompt="$1" default="$2" answer
  if [ "${SB_MODE:-default}" != "interactive" ] || [ ! -t 0 ]; then
    printf '%s\n' "$default"
    return 0
  fi
  printf '%s [%s]: ' "$prompt" "$default" >&2
  read -r answer || answer=""
  printf '%s\n' "${answer:-$default}"
}

# ask_yn <prompt> <default y|n> — returns 0 for yes, 1 for no.
ask_yn() {
  local a
  a="$(ask "$1 (y/n)" "$2")"
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ----------------------------------------------------------------- python ---
# sb_python — best available python3 for installer-side JSON/TOML surgery.
sb_python() {
  if [ -n "${SB_PYTHON:-}" ]; then "$SB_PYTHON" "$@"; else python3 "$@"; fi
}

# state_set <key> <json-value> — update install-state.json (object merge).
state_set() {
  local key="$1" value="$2" state="${SB_STATE_FILE:-}"
  [ -n "$state" ] || return 0
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then return 0; fi
  mkdir -p "$(dirname "$state")"
  sb_python - "$state" "$key" "$value" <<'PYEOF'
import json, os, sys
path, key, raw = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
try:
    value = json.loads(raw)
except json.JSONDecodeError:
    value = raw
data[key] = value
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
os.replace(tmp, path)
PYEOF
}
