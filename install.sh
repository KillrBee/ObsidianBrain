#!/usr/bin/env bash
# install.sh — SecondBrain stack installer for macOS.
#
#   ./install.sh --mode interactive     guided configuration
#   ./install.sh --mode default         non-interactive defaults
#   ./install.sh --dry-run              print the plan, change nothing
#   ./install.sh --repair               re-run idempotent steps, fix drift
#   ./install.sh --upgrade              refresh payload scripts (backs up user edits)
#   ./install.sh --uninstall            remove managed config; never deletes the vault
#
# Every step is "ensure state X": running twice is safe by construction.

set -u

SB_INSTALLER_ROOT="$(cd "$(dirname "$0")" && pwd)"
SB_VERSION="$(cat "$SB_INSTALLER_ROOT/VERSION" 2>/dev/null | head -1)"
SB_VERSION="${SB_VERSION:-0.0.0}"

# ------------------------------------------------------------------ args ----
SB_MODE="default"
SB_DRY_RUN="${SB_DRY_RUN:-0}"
SB_REPAIR=0
SB_UPGRADE="${SB_UPGRADE:-0}"
SB_UNINSTALL=0
SB_VAULT_DIR="${SB_VAULT_DIR:-$HOME/SecondBrain}"
SB_ENABLE_LFS="${SB_ENABLE_LFS:-0}"
SB_WITH_OCR="${SB_WITH_OCR:-0}"
SB_WITH_TRANSCRIPTION="${SB_WITH_TRANSCRIPTION:-0}"
SB_SKIP_OBSIDIAN="${SB_SKIP_OBSIDIAN:-0}"
SB_NO_MCP="${SB_NO_MCP:-0}"
SB_NO_AGENT_GUIDES="${SB_NO_AGENT_GUIDES:-0}"
SB_CLAUDE_SCOPE="${SB_CLAUDE_SCOPE:-project}"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  cat <<EOF
Options:
  --mode interactive|default   configuration style (default: default)
  --vault-dir PATH             vault location (default: ~/SecondBrain)
  --dry-run                    print actions without executing
  --repair                     re-run steps, restoring missing pieces
  --upgrade                    refresh payload scripts/config (backup user edits)
  --uninstall                  remove managed MCP config; vault is preserved
  --enable-lfs                 track 10-originals via Git LFS
  --with-ocr                   install tesseract + poppler
  --with-transcription         install ffmpeg + markitdown audio extras
  --skip-obsidian              do not install the Obsidian app
  --no-mcp                     skip Claude Code and Codex MCP configuration
  --no-agent-guides            skip user-scope memory-routing guides and skill
  --claude-scope SCOPE         project|user|both|skip (default: project)
  --version                    print installer version
  -h, --help                   this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) SB_MODE="${2:?--mode needs a value}"; shift ;;
    --mode=*) SB_MODE="${1#*=}" ;;
    --vault-dir) SB_VAULT_DIR="${2:?--vault-dir needs a value}"; shift ;;
    --vault-dir=*) SB_VAULT_DIR="${1#*=}" ;;
    --dry-run) SB_DRY_RUN=1 ;;
    --repair) SB_REPAIR=1 ;;
    --upgrade) SB_UPGRADE=1 ;;
    --uninstall) SB_UNINSTALL=1 ;;
    --enable-lfs) SB_ENABLE_LFS=1 ;;
    --with-ocr) SB_WITH_OCR=1 ;;
    --with-transcription) SB_WITH_TRANSCRIPTION=1 ;;
    --skip-obsidian) SB_SKIP_OBSIDIAN=1 ;;
    --no-mcp) SB_NO_MCP=1 ;;
    --no-agent-guides) SB_NO_AGENT_GUIDES=1 ;;
    --claude-scope) SB_CLAUDE_SCOPE="${2:?--claude-scope needs a value}"; shift ;;
    --claude-scope=*) SB_CLAUDE_SCOPE="${1#*=}" ;;
    --version) echo "$SB_VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

case "$SB_MODE" in interactive|default) : ;; *) echo "invalid --mode: $SB_MODE" >&2; exit 64 ;; esac

# Expand a leading literal ~ that survived quoting.
# shellcheck disable=SC2088
case "$SB_VAULT_DIR" in "~/"*) SB_VAULT_DIR="$HOME/${SB_VAULT_DIR#\~/}" ;; esac

# --------------------------------------------------------------- plumbing ---
SB_LOG_FILE="$(mktemp -t secondbrain-install-log)"
SB_REPORT_ROWS="$(mktemp -t secondbrain-report-rows)"
trap 'rm -f "$SB_REPORT_ROWS" "$SB_LOG_FILE"' EXIT
SB_STATE_FILE="$SB_VAULT_DIR/60-index-config/install-state.json"

for mod in common checks brew deps obsidian vault payload markitdown qmd basic_memory mcp_claude mcp_codex agent_guides validate report; do
  # shellcheck source=/dev/null
  . "$SB_INSTALLER_ROOT/lib/$mod.sh"
done

# ------------------------------------------------------------ interactive ---
if [ "$SB_MODE" = "interactive" ] && [ "$SB_UNINSTALL" != "1" ]; then
  sb_step "Interactive configuration"
  SB_VAULT_DIR="$(ask "Vault directory" "$SB_VAULT_DIR")"
  # shellcheck disable=SC2088
  case "$SB_VAULT_DIR" in "~/"*) SB_VAULT_DIR="$HOME/${SB_VAULT_DIR#\~/}" ;; esac
  SB_STATE_FILE="$SB_VAULT_DIR/60-index-config/install-state.json"
  ask_yn "Install the Obsidian app (brew cask)" "y" || SB_SKIP_OBSIDIAN=1
  ask_yn "Track original binaries with Git LFS" "n" && SB_ENABLE_LFS=1
  ask_yn "Install OCR dependencies (tesseract, poppler)" "n" && SB_WITH_OCR=1
  ask_yn "Install transcription dependencies (ffmpeg)" "n" && SB_WITH_TRANSCRIPTION=1
  if ask_yn "Configure MCP for Claude Code / Codex" "y"; then
    SB_CLAUDE_SCOPE="$(ask "Claude Code MCP scope (project/user/both/skip)" "$SB_CLAUDE_SCOPE")"
  else
    SB_NO_MCP=1
  fi
  ask_yn "Install user-scope memory-routing guides for agents (CLAUDE.md/AGENTS.md managed blocks + skill)" "y" || SB_NO_AGENT_GUIDES=1
fi

# --------------------------------------------------------------- uninstall --
if [ "$SB_UNINSTALL" = "1" ]; then
  sb_step "Uninstall (managed configuration only)"
  uninstall_mcp_claude
  uninstall_mcp_codex
  uninstall_qmd
  uninstall_agent_guides
  sb_info "The vault at $SB_VAULT_DIR was NOT touched."
  sb_info "To remove it entirely (this deletes your notes!):"
  sb_info "  rm -rf \"$SB_VAULT_DIR\""
  sb_info "Brew-installed tools (git, ripgrep, markitdown, …) were left installed."
  step_report
  exit 0
fi

# ------------------------------------------------------------------ steps ---
sb_step "SecondBrain installer v$SB_VERSION"
sb_info "mode: $SB_MODE$([ "$SB_DRY_RUN" = "1" ] && echo ' (dry-run)')$([ "$SB_REPAIR" = "1" ] && echo ' (repair)')$([ "$SB_UPGRADE" = "1" ] && echo ' (upgrade)')"
sb_info "vault: $SB_VAULT_DIR"

step_run "Pre-flight checks"            step_preflight        || exit 1
step_run "Homebrew"                     step_homebrew
step_run "Core dependencies"            step_core_deps
step_run "Optional dependencies"        step_optional_deps
step_run "Obsidian"                     step_obsidian
step_run "Vault directory structure"    step_vault_tree
step_run "Vault scripts and config"     step_payload
step_run "Vault git repository"         step_vault_git
step_run "Python environment"           step_python_env
step_run "MarkItDown"                   step_markitdown
step_run "QMD lookup layer"             step_qmd
step_run "QMD collections"              step_qmd_collections
step_run "Basic Memory"                 step_basic_memory
step_run "Claude Code MCP"              step_mcp_claude
step_run "Codex MCP"                    step_mcp_codex
step_run "Agent memory-routing guides"  step_agent_guides
step_run "Validation"                   step_validate

step_report

if [ "$SB_STEP_FAILURES" -gt 0 ]; then
  sb_err "$SB_STEP_FAILURES step(s) failed — see report above. Re-run with --repair after fixing."
  exit 1
fi
sb_ok "SecondBrain is ready at $SB_VAULT_DIR"
exit 0
