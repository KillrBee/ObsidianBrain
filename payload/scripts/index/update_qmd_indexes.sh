#!/usr/bin/env bash
# update_qmd_indexes.sh — mirror collections.yaml into QMD and re-index
# (spec §13). Collections register as sb-<name> (one QMD collection per vault
# collection; multi-glob collections use a brace mask). With no QMD binary
# this is a logged no-op: the built-in ripgrep backend searches the collection
# globs directly and needs no index.
#
# Usage: update_qmd_indexes.sh [--vault DIR] [--register]
# Env:   SB_QMD_BIN — explicit qmd binary (else resolved from PATH)

set -u
. "$(cd "$(dirname "$0")" && pwd)/../lib/sb_common.sh"

REGISTER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) SB_VAULT_ROOT="${2:?--vault needs a value}"; shift ;;
    --vault=*) SB_VAULT_ROOT="${1#*=}" ;;
    --register) REGISTER=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) sb_err "unknown option: $1"; exit 64 ;;
  esac
  shift
done
sb_require_vault

QMD_BIN="${SB_QMD_BIN:-}"
[ -n "$QMD_BIN" ] || QMD_BIN="$(command -v qmd 2>/dev/null || true)"

log_index() {
  sb_python - "$SB_VAULT_ROOT" "$1" <<'PYEOF'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "70-scripts" / "lib"))
import sb_vault
sb_vault.log_jsonl(Path(sys.argv[1]), "indexing", {"event": sys.argv[2]})
PYEOF
}

if [ -z "$QMD_BIN" ]; then
  log_index "no-op: qmd not installed; ripgrep backend needs no index"
  echo "qmd not installed — built-in search backend needs no index update"
  exit 0
fi

FAILURES=0

# ---- register collections (sb-<name>, brace mask for multi-glob) ------------
if [ "$REGISTER" = "1" ]; then
  while IFS=$'\t' read -r name mask; do
    [ -n "$name" ] || continue
    out="$("$QMD_BIN" collection add "$SB_VAULT_ROOT" --name "sb-$name" --mask "$mask" 2>&1)"
    case "$out" in
      *"already exists"*) : ;;                        # idempotent re-run
      *"created successfully"*|*"✓"*) : ;;
      *) sb_err "qmd register sb-$name failed: $out"; FAILURES=$((FAILURES + 1)) ;;
    esac
  done <<EOF
$(sb_python - "$SB_VAULT_ROOT" <<'PYEOF'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "70-scripts" / "lib"))
import sb_vault
cfg = sb_vault.load_collections(Path(sys.argv[1]))
for name, globs in cfg["collections"].items():
    mask = globs[0] if len(globs) == 1 else "{" + ",".join(globs) + "}"
    print(f"{name}\t{mask}")
PYEOF
)
EOF
fi

# ---- re-index ---------------------------------------------------------------
if out="$("$QMD_BIN" update 2>&1)"; then
  log_index "qmd update ok"
  echo "qmd index updated"
else
  log_index "qmd update failed"
  sb_err "qmd update failed: $(printf '%s' "$out" | tail -1)"
  sb_err "(searches fall back to the built-in backend)"
  FAILURES=$((FAILURES + 1))
fi

[ "$FAILURES" -eq 0 ]
