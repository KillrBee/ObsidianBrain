# SecondBrain Installer

One-command macOS setup for an Obsidian-based second brain with agentic
retrieval: MarkItDown conversion, scoped search collections, Basic Memory,
and MCP integration for Claude Code and Codex.

```text
Original documents are evidence.
Converted Markdown is retrieval substrate.
Curated Markdown is trusted knowledge.
Basic Memory is structured agent memory.
QMD is lookup.
MCP is the agent interface.
Git is the temporal and versioning backbone.
Obsidian is the human interface.
```

## Install

```bash
git clone <this-repo>
cd ObsidianBrain
./install.sh                    # defaults: vault at ~/SecondBrain
./install.sh --mode interactive # guided configuration
```

Other modes:

```bash
./install.sh --dry-run          # print the plan, change nothing
./install.sh --repair           # restore missing scripts/config
./install.sh --upgrade          # refresh payload (backs up your edits)
./install.sh --uninstall        # remove managed MCP config; vault untouched
```

Useful flags: `--vault-dir PATH`, `--enable-lfs`, `--with-ocr`,
`--with-transcription`, `--skip-obsidian`, `--no-mcp`,
`--claude-scope project|user|both|skip`.

The installer is idempotent — run it twice and the second run only verifies.
Every run ends with a report (also written to `80-logs/install-report-*.md`)
stating what was installed, verified, configured, skipped, or failed.

## What you get

- `~/SecondBrain` vault (spec §5 layout) — open it in Obsidian via
  *Open folder as vault*
- Conversion pipeline: drop files in `00-inbox/raw-drops/`, run
  `70-scripts/convert/convert_new_documents.sh`; originals are checksummed,
  never modified, and every conversion lands in
  `60-index-config/manifests/conversion-manifest.json`
- Scoped search with a stable JSON contract:
  `70-scripts/search/search_{curated,decisions,sources,agent_memory}.sh`
- Context packs: `70-scripts/context/build_context_pack.py --topic X`
- `second-brain` MCP server (24 tools; search/read/context/memory/maintenance)
  wired into Claude Code (`.mcp.json`, optional user scope) and Codex
  (managed block in `~/.codex/config.toml`)
- Basic Memory pointed at `40-agent-memory/` only

### Search backends (QMD note)

Wrapper scripts guarantee the JSON contract regardless of backend. When a
`qmd` binary is on PATH it is used per collection; otherwise a built-in
ripgrep-based scorer over the same `collections.yaml` takes over. Set
`SB_QMD_INSTALL_CMD` before installing to have the installer install QMD
your preferred way.

## Development

```bash
make install-dev   # dev venv: pyyaml, jsonschema, mcp, pytest, markitdown, fixture libs
make lint          # shellcheck
make test          # bats + pytest (installs into throwaway temp vaults)
make fixtures      # regenerate tests/fixtures binaries
tests/acceptance.sh            # spec §24 walk on a real machine (temp vault)
tests/acceptance.sh --vault-dir ~/SecondBrain   # the real thing
```

Repo layout: `install.sh` + `lib/` is the installer; everything under
`payload/` is copied into the vault (`payload/scripts` → `70-scripts`,
`payload/config` → `60-index-config`). `IMPLEMENTATION_PLAN.md` records the
full design, decision log, and phase mapping.

## Safety model

Agents get bounded tools only: reads from converted/curated/memory/packs,
writes to `40-agent-memory/` and `50-context-packs/` (always stamped
`review_status: unreviewed`), no deletes, no curated writes, no git push, no
crawling, credential patterns excluded from indexing (spec §11/§22). The
installer backs up any file it must modify and never deletes your vault.
