#!/usr/bin/env bash
# convert_new_documents.sh — the conversion pipeline driver (spec §12).
#   1. Route files from 00-inbox/raw-drops into 10-originals/<type>/
#   2. Convert anything in 10-originals not yet in the manifest
#   3. Trigger an index update
#
# Usage: convert_new_documents.sh [--vault DIR]

set -u
. "$(cd "$(dirname "$0")" && pwd)/../lib/sb_common.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) SB_VAULT_ROOT="${2:?--vault needs a value}"; shift ;;
    --vault=*) SB_VAULT_ROOT="${1#*=}" ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) sb_err "unknown option: $1"; exit 64 ;;
  esac
  shift
done
sb_require_vault

# ---- classify by extension -> originals subdir ------------------------------
originals_subdir() {
  case "$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')" in
    pdf) echo pdf ;;
    docx|doc) echo docx ;;
    pptx|ppt) echo pptx ;;
    xlsx|xls|csv) echo xlsx ;;
    html|htm) echo html ;;
    eml|msg) echo email ;;
    mp3|m4a|wav|mp4|mov) echo audio ;;
    png|jpg|jpeg|gif|webp|heic) echo images ;;
    *) echo other ;;
  esac
}

file_sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# ---- 1. ingest inbox ---------------------------------------------------------
INGESTED=0
INBOX="$SB_VAULT_ROOT/00-inbox/raw-drops"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  base="$(basename "$f")"
  sub="$(originals_subdir "$base")"
  dest_dir="$SB_VAULT_ROOT/10-originals/$sub"
  dest="$dest_dir/$base"
  mkdir -p "$dest_dir"
  if [ -e "$dest" ]; then
    if [ "$(file_sha "$f")" = "$(file_sha "$dest")" ]; then
      rm -f "$f"                       # exact duplicate already ingested
      continue
    fi
    # Same name, different content: keep both, never overwrite an original.
    short="$(file_sha "$f" | cut -c1-8)"
    dest="$dest_dir/${base%.*}--$short.${base##*.}"
  fi
  cp -p "$f" "$dest" || { sb_err "failed to ingest $base"; continue; }
  # Only remove the inbox copy once the ingested copy is verified.
  if [ "$(file_sha "$f")" = "$(file_sha "$dest")" ]; then
    rm -f "$f"
    INGESTED=$((INGESTED + 1))
  else
    rm -f "$dest"
    sb_err "checksum mismatch ingesting $base; left in inbox"
  fi
done <<EOF
$(find "$INBOX" -type f ! -name '.gitkeep' ! -name '.DS_Store' 2>/dev/null | sort)
EOF

# ---- 2. convert unconverted originals ---------------------------------------
CONVERTED=0 SKIPPED=0 FAILED=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  sb_python "$SB_SCRIPTS_ROOT/convert/convert_one.py" --vault "$SB_VAULT_ROOT" --source "$f"
  case $? in
    0) CONVERTED=$((CONVERTED + 1)) ;;
    3) SKIPPED=$((SKIPPED + 1)) ;;
    *) FAILED=$((FAILED + 1)) ;;
  esac
done <<EOF
$(find "$SB_VAULT_ROOT/10-originals" -type f ! -name '.gitkeep' ! -name '.DS_Store' 2>/dev/null | sort)
EOF

# ---- 3. refresh indexes (best effort) ---------------------------------------
if [ "$CONVERTED" -gt 0 ]; then
  "$SB_SCRIPTS_ROOT/index/update_qmd_indexes.sh" --vault "$SB_VAULT_ROOT" >/dev/null 2>&1 \
    || sb_err "index update failed (search still works via the ripgrep backend)"
fi

echo "ingested=$INGESTED converted=$CONVERTED skipped=$SKIPPED failed=$FAILED"
[ "$FAILED" -eq 0 ]
