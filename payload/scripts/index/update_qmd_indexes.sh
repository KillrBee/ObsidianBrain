#!/usr/bin/env bash
# update_qmd_indexes.sh — refresh (or register) QMD collections (spec §13).
# With no QMD binary installed this is a logged no-op: the internal ripgrep
# backend searches the collection globs directly and needs no index.
#
# Usage: update_qmd_indexes.sh [--vault DIR] [--register]

set -u
. "$(cd "$(dirname "$0")" && pwd)/../lib/sb_common.sh"

REGISTER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) SB_VAULT_ROOT="${2:?--vault needs a value}"; shift ;;
    --vault=*) SB_VAULT_ROOT="${1#*=}" ;;
    --register) REGISTER=1 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) sb_err "unknown option: $1"; exit 64 ;;
  esac
  shift
done
sb_require_vault

log_index() {
  sb_python - "$SB_VAULT_ROOT" "$1" <<'PYEOF'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "70-scripts" / "lib"))
import sb_vault
sb_vault.log_jsonl(Path(sys.argv[1]), "indexing", {"event": sys.argv[2]})
PYEOF
}

if ! command -v qmd >/dev/null 2>&1; then
  log_index "no-op: qmd not installed; internal backend indexes nothing"
  echo "qmd not installed — internal search backend needs no index update"
  exit 0
fi

# QMD is present. Iterate collections from collections.yaml and update each.
# The QMD CLI surface varies between releases; every call is best-effort and
# failures are logged without breaking the pipeline (plan R1).
FAILURES=0
while IFS='|' read -r name glob; do
  [ -n "$name" ] || continue
  if [ "$REGISTER" = "1" ]; then
    qmd collection add "$name" "$SB_VAULT_ROOT/$glob" >/dev/null 2>&1 \
      || qmd collections add "$name" "$SB_VAULT_ROOT/$glob" >/dev/null 2>&1 \
      || FAILURES=$((FAILURES + 1))
  fi
done <<EOF
$(sb_python - "$SB_VAULT_ROOT" <<'PYEOF'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "70-scripts" / "lib"))
import sb_vault
cfg = sb_vault.load_collections(Path(sys.argv[1]))
for name, globs in cfg["collections"].items():
    for g in globs:
        print(f"{name}|{g}")
PYEOF
)
EOF

if qmd update >/dev/null 2>&1 || qmd index >/dev/null 2>&1; then
  log_index "qmd index updated"
  echo "qmd index updated"
else
  log_index "qmd update failed"
  sb_err "qmd update failed (searches will fall back to the internal backend)"
  FAILURES=$((FAILURES + 1))
fi

[ "$FAILURES" -eq 0 ]
