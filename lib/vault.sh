#!/usr/bin/env bash
# vault.sh — create the ~/SecondBrain tree (spec §5), seed files, git init.

# Directory list exactly per spec §5 (plus script/config subdirs the payload
# copy will also ensure). .gitkeep files make empty dirs trackable.
SB_VAULT_DIRS="
00-inbox/raw-drops
00-inbox/needs-triage
10-originals/pdf
10-originals/docx
10-originals/pptx
10-originals/xlsx
10-originals/html
10-originals/email
10-originals/audio
10-originals/images
10-originals/other
20-converted/pdf-md
20-converted/docx-md
20-converted/pptx-md
20-converted/xlsx-md
20-converted/html-md
20-converted/email-md
20-converted/transcript-md
20-converted/image-md
20-converted/other-md
30-curated/concepts
30-curated/decisions
30-curated/summaries
30-curated/people
30-curated/projects
30-curated/systems
30-curated/glossary
30-curated/patterns
30-curated/playbooks
40-agent-memory/daily
40-agent-memory/project-memory
40-agent-memory/constraints
40-agent-memory/preferences
40-agent-memory/observations
40-agent-memory/relations
40-agent-memory/lessons-learned
50-context-packs/active
50-context-packs/drafts
50-context-packs/archived
60-index-config/qmd
60-index-config/basic-memory
60-index-config/mcp
60-index-config/schemas
60-index-config/manifests
70-scripts/lib
70-scripts/convert
70-scripts/index
70-scripts/search
70-scripts/context
70-scripts/maintenance
70-scripts/memory
70-scripts/mcp
80-logs/conversion
80-logs/indexing
80-logs/agent-access
80-logs/errors
90-archive
"

step_vault_tree() {
  local d
  # shellcheck disable=SC2153  # SB_VAULT_DIR is set by install.sh
  ensure_dir "$SB_VAULT_DIR" || return 1
  for d in $SB_VAULT_DIRS; do
    ensure_dir "$SB_VAULT_DIR/$d" || return 1
    if [ "${SB_DRY_RUN:-0}" != "1" ] && [ ! -e "$SB_VAULT_DIR/$d/.gitkeep" ]; then
      # Only leaf dirs need .gitkeep, but extra ones are harmless.
      touch "$SB_VAULT_DIR/$d/.gitkeep"
    fi
  done

  # Seed root files from templates only when absent — never clobber user edits.
  _seed_from_template "vault-files/README.md.tmpl" "$SB_VAULT_DIR/README.md"
  _seed_from_template "vault-files/MEMORY.md.tmpl" "$SB_VAULT_DIR/MEMORY.md"
  _seed_from_template "vault-files/AGENTS.md.tmpl" "$SB_VAULT_DIR/AGENTS.md"
  _seed_from_template "vault-files/agent-memory-MEMORY.md.tmpl" "$SB_VAULT_DIR/40-agent-memory/MEMORY.md"
  _seed_from_template "vault-files/sample-concept.md.tmpl" "$SB_VAULT_DIR/30-curated/concepts/second-brain-overview.md"
  _seed_from_template "vault-files/sample-decision.md.tmpl" "$SB_VAULT_DIR/30-curated/decisions/adopt-second-brain-stack.md"

  report_add "vault-tree" "$([ -d "$SB_VAULT_DIR/30-curated" ] && echo verified || echo installed)" "$SB_VAULT_DIR"
  state_set "vault_dir" "\"$SB_VAULT_DIR\""
}

_seed_from_template() {
  local tpl="$SB_INSTALLER_ROOT/payload/$1" dest="$2"
  if [ -e "$dest" ]; then
    sb_info "$(basename "$dest") exists; leaving untouched"
    return 0
  fi
  render_template "$tpl" | write_file "$dest" 0644
}

step_vault_git() {
  if [ -d "$SB_VAULT_DIR/.git" ]; then
    report_add "git-init" "verified" "repository already initialized"
  else
    run git -C "$SB_VAULT_DIR" init -b main >/dev/null || {
      # Older git without -b support.
      run git -C "$SB_VAULT_DIR" init >/dev/null || return 1
    }
    report_add "git-init" "installed" "$SB_VAULT_DIR/.git"
  fi

  # .gitignore: seed if absent; leave user-modified versions alone.
  if [ ! -e "$SB_VAULT_DIR/.gitignore" ]; then
    local tpl="$SB_INSTALLER_ROOT/payload/vault-files/gitignore.tmpl"
    {
      render_template "$tpl"
      if [ "${SB_ENABLE_LFS:-0}" != "1" ]; then
        printf '\n# Originals are kept local, not versioned (enable Git LFS mode to track them)\n10-originals/**\n!10-originals/**/.gitkeep\n'
      fi
    } | write_file "$SB_VAULT_DIR/.gitignore" 0644
    report_add "gitignore" "installed" ""
  else
    report_add "gitignore" "verified" "existing file preserved"
  fi

  if [ "${SB_ENABLE_LFS:-0}" = "1" ]; then
    if [ ! -e "$SB_VAULT_DIR/.gitattributes" ]; then
      write_file "$SB_VAULT_DIR/.gitattributes" 0644 <<'EOF'
10-originals/** filter=lfs diff=lfs merge=lfs -text
EOF
    fi
    run git -C "$SB_VAULT_DIR" lfs install --local >/dev/null 2>&1 || sb_warn "git lfs install failed; continuing"
    report_add "git-lfs" "configured" "10-originals tracked via LFS"
  fi

  # Initial commit so the vault starts with a clean baseline. Local identity
  # fallback avoids failing on machines without git user config.
  if [ "${SB_DRY_RUN:-0}" != "1" ]; then
    if ! git -C "$SB_VAULT_DIR" rev-parse HEAD >/dev/null 2>&1; then
      git -C "$SB_VAULT_DIR" add -A >/dev/null 2>&1 || true
      if git -C "$SB_VAULT_DIR" \
        -c user.name="${GIT_AUTHOR_NAME:-SecondBrain Installer}" \
        -c user.email="${GIT_AUTHOR_EMAIL:-installer@secondbrain.local}" \
        commit -m "Initialize SecondBrain vault (installer v${SB_VERSION})" >/dev/null 2>&1; then
        report_add "git-initial-commit" "installed" ""
      else
        report_add "git-initial-commit" "skipped" "commit failed (empty tree or git config); not fatal"
      fi
    else
      report_add "git-initial-commit" "verified" "history exists"
    fi
  else
    report_add "git-initial-commit" "skipped" "dry-run"
  fi
}
