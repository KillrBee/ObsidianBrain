#!/usr/bin/env bash
# payload.sh — copy payload/ scripts and config into the vault.
#
# Rules (plan §2.1):
#   new file                -> install
#   identical file          -> verified
#   stale installer version -> replace (dest matches checksum we recorded)
#   user-modified file      -> preserve on install/repair; backup+replace on --upgrade
#   seed-only files         -> install only if absent (data files: manifest, basic-memory config)

_sha256() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

_payload_recorded_sum() {
  # _payload_recorded_sum <relkey> — recorded checksum from install-state.json
  [ -f "${SB_STATE_FILE:-}" ] || { echo ""; return 0; }
  sb_python - "$SB_STATE_FILE" "$1" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get("payload_checksums", {}).get(sys.argv[2], ""))
except Exception:
    print("")
PYEOF
}

_is_seed_only() {
  case "$1" in
    config/manifests/conversion-manifest.json) return 0 ;;
    config/basic-memory/config.json) return 0 ;;
    *) return 1 ;;
  esac
}

# _install_payload_file <src> <dest> <relkey> <mode>
_install_payload_file() {
  local src="$1" dest="$2" relkey="$3" mode="$4"
  local src_sum dest_sum recorded_sum
  src_sum="$(_sha256 "$src")"

  if [ ! -e "$dest" ]; then
    write_file "$dest" "$mode" <"$src" || return 1
    SB_PAYLOAD_INSTALLED=$((SB_PAYLOAD_INSTALLED + 1))
    _payload_note_sum "$relkey" "$src_sum"
    return 0
  fi

  dest_sum="$(_sha256 "$dest")"
  if [ "$dest_sum" = "$src_sum" ]; then
    SB_PAYLOAD_VERIFIED=$((SB_PAYLOAD_VERIFIED + 1))
    _payload_note_sum "$relkey" "$src_sum"
    return 0
  fi

  if _is_seed_only "$relkey"; then
    SB_PAYLOAD_PRESERVED=$((SB_PAYLOAD_PRESERVED + 1))
    return 0
  fi

  recorded_sum="$(_payload_recorded_sum "$relkey")"
  if [ -n "$recorded_sum" ] && [ "$dest_sum" = "$recorded_sum" ]; then
    # Unmodified file from a previous install — safe to refresh.
    write_file "$dest" "$mode" <"$src" || return 1
    SB_PAYLOAD_UPDATED=$((SB_PAYLOAD_UPDATED + 1))
    _payload_note_sum "$relkey" "$src_sum"
    return 0
  fi

  # User-modified.
  if [ "${SB_UPGRADE:-0}" = "1" ]; then
    backup_file "$dest" >/dev/null || return 1
    write_file "$dest" "$mode" <"$src" || return 1
    SB_PAYLOAD_UPDATED=$((SB_PAYLOAD_UPDATED + 1))
    _payload_note_sum "$relkey" "$src_sum"
  else
    sb_info "preserving user-modified $relkey (use --upgrade to replace with backup)"
    SB_PAYLOAD_PRESERVED=$((SB_PAYLOAD_PRESERVED + 1))
  fi
}

_payload_note_sum() {
  # Accumulate rel->sum lines; flushed to state once at the end (cheap).
  printf '%s %s\n' "$1" "$2" >>"$SB_PAYLOAD_SUMS_TMP"
}

step_payload() {
  local src rel relkey dest mode
  SB_PAYLOAD_INSTALLED=0 SB_PAYLOAD_VERIFIED=0 SB_PAYLOAD_UPDATED=0 SB_PAYLOAD_PRESERVED=0
  SB_PAYLOAD_SUMS_TMP="$(mktemp)"

  # 70-scripts from payload/scripts
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    rel="${src#"$SB_INSTALLER_ROOT"/payload/scripts/}"
    relkey="scripts/$rel"
    dest="$SB_VAULT_DIR/70-scripts/$rel"
    mode=0755
    _install_payload_file "$src" "$dest" "$relkey" "$mode" || { rm -f "$SB_PAYLOAD_SUMS_TMP"; return 1; }
  done <<EOF
$(find "$SB_INSTALLER_ROOT/payload/scripts" -type f ! -name '.DS_Store' ! -path '*__pycache__*' | sort)
EOF

  # 60-index-config from payload/config
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    rel="${src#"$SB_INSTALLER_ROOT"/payload/config/}"
    relkey="config/$rel"
    dest="$SB_VAULT_DIR/60-index-config/$rel"
    mode=0644
    _install_payload_file "$src" "$dest" "$relkey" "$mode" || { rm -f "$SB_PAYLOAD_SUMS_TMP"; return 1; }
  done <<EOF
$(find "$SB_INSTALLER_ROOT/payload/config" -type f ! -name '.DS_Store' | sort)
EOF

  # Flush recorded checksums to state (skipped in dry-run by state_set).
  if [ -s "$SB_PAYLOAD_SUMS_TMP" ] && [ "${SB_DRY_RUN:-0}" != "1" ]; then
    sb_python - "$SB_STATE_FILE" "$SB_PAYLOAD_SUMS_TMP" <<'PYEOF'
import json, os, sys
state_path, sums_path = sys.argv[1], sys.argv[2]
try:
    with open(state_path) as f:
        data = json.load(f)
except Exception:
    data = {}
sums = data.setdefault("payload_checksums", {})
with open(sums_path) as f:
    for line in f:
        parts = line.strip().split(" ", 1)
        if len(parts) == 2:
            sums[parts[0]] = parts[1]
os.makedirs(os.path.dirname(state_path), exist_ok=True)
tmp = state_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
os.replace(tmp, state_path)
PYEOF
  fi
  rm -f "$SB_PAYLOAD_SUMS_TMP"

  report_add "payload" "$([ "$SB_PAYLOAD_INSTALLED" -gt 0 ] || [ "$SB_PAYLOAD_UPDATED" -gt 0 ] && echo installed || echo verified)" \
    "installed=$SB_PAYLOAD_INSTALLED updated=$SB_PAYLOAD_UPDATED unchanged=$SB_PAYLOAD_VERIFIED preserved=$SB_PAYLOAD_PRESERVED"
}
