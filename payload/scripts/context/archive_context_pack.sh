#!/usr/bin/env bash
# archive_context_pack.sh — move a pack from active/ or drafts/ to archived/
# with a timestamp suffix. Usage: archive_context_pack.sh [--vault DIR] <name>

set -u
. "$(cd "$(dirname "$0")" && pwd)/../lib/sb_common.sh"

NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) SB_VAULT_ROOT="${2:?--vault needs a value}"; shift ;;
    --vault=*) SB_VAULT_ROOT="${1#*=}" ;;
    -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) NAME="$1" ;;
  esac
  shift
done
sb_require_vault
[ -n "$NAME" ] || { sb_err "usage: archive_context_pack.sh [--vault DIR] <name>"; exit 64; }
NAME="${NAME%.md}"

TS="$(date '+%Y%m%dT%H%M%SZ')"
for area in active drafts; do
  src="$SB_VAULT_ROOT/50-context-packs/$area/$NAME.md"
  if [ -f "$src" ]; then
    dest="$SB_VAULT_ROOT/50-context-packs/archived/$NAME-$TS.md"
    mkdir -p "$(dirname "$dest")"
    mv "$src" "$dest"
    echo "archived: 50-context-packs/$area/$NAME.md -> 50-context-packs/archived/$(basename "$dest")"
    exit 0
  fi
done
sb_err "context pack not found: $NAME"
exit 1
