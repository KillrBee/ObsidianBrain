# SecondBrain Installer

[![ci](https://github.com/KillrBee/ObsidianBrain/actions/workflows/ci.yml/badge.svg)](https://github.com/KillrBee/ObsidianBrain/actions/workflows/ci.yml)

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
git clone https://github.com/KillrBee/ObsidianBrain.git
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
- `second-brain` MCP server (25 tools; search/read/context/memory/maintenance)
  wired into Claude Code (`.mcp.json`, optional user scope) and Codex
  (managed block in `~/.codex/config.toml`)
- Basic Memory pointed at `40-agent-memory/` only
- Agent memory-routing guides: managed blocks in `~/.claude/CLAUDE.md` and
  `~/.codex/AGENTS.md`, a `second-brain` skill in `~/.claude/skills/`, and
  `AGENTS.md`/`MEMORY.md` in the vault (`--no-agent-guides` to opt out)

### Search backends

The primary lookup layer is [tobi/qmd](https://github.com/tobi/qmd)
(`npm install -g @tobilu/qmd`, done by the installer). Vault collections are
mirrored into QMD under an `sb-` prefix (`sb-curated`, `sb-decisions`, …) so
they never collide with your own QMD collections; `qmd update` runs after
each conversion batch. The wrappers call `qmd search … --json` (BM25 — no
model downloads); run `qmd embed` yourself to enable `qmd query`
hybrid/vector search, and `qmd mcp` if you also want QMD's native MCP tools.

Wrapper scripts guarantee the same JSON contract regardless of backend: if
`qmd` is missing or a collection isn't registered, a built-in ripgrep-based
scorer over the same `collections.yaml` takes over transparently. Set
`SB_QMD_INSTALL_CMD` to override how the installer installs QMD, or
`SB_QMD_BIN` to point at a specific binary.

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

## Environments — how agents reach the vault

Both access paths hit the same policy layer (dedup guard, unreviewed
stamping, access logging), so pick per machine:

| Environment | Path |
|---|---|
| Claude Code / Codex, MCP allowed | MCP tools, user scope (`--claude-scope both`) — richest: typed tools, works in every session |
| Claude Code, enterprise policy blocks user-scope MCP | Project `.mcp.json` per repo where allowed, plus **script mode** everywhere: the `second-brain` skill carries runnable commands for search (`70-scripts/search/*.sh`), context packs, and memory writes (`70-scripts/memory/remember.sh`) — no MCP registration needed, only Bash. Optional: allowlist `Bash(<vault>/70-scripts/*)` in `~/.claude/settings.json` to skip per-call prompts |
| Claude CLI on Bedrock / any provider | Identical to the above — MCP and skills are harness features, provider-agnostic |
| Chat clients (Claude Desktop, claude.ai) | MCP only (no shell): add the `second-brain` launcher to the client's MCP config |
| Humans | Obsidian on the vault folder; scripts directly |

## Memory discipline (anti-bloat)

The vault is the single durable memory across projects; per-project agent
memory files should hold repo mechanics plus *pointers*, not copies. This is
enforced in mechanism, not just prose: `write_agent_memory_note` refuses to
create a note that near-duplicates an existing one (same filename, title
overlap, or content-term overlap) and answers with the existing path —
`append_observation`/`append_relation` keep one note per entity, updates to
existing paths always pass, and `force=true` is the deliberate escape hatch.
`find_duplicate_memory` reports anything that still slips through for human
consolidation. The prose rules (search before write, update over correct,
deltas not transcripts, link don't copy) live in the vault's `AGENTS.md` and
`MEMORY.md`, in the `second-brain` skill, and in the managed user-scope
blocks the installer maintains.

## Safety model

Agents get bounded tools only: reads from converted/curated/memory/packs,
writes to `40-agent-memory/` and `50-context-packs/` (always stamped
`review_status: unreviewed`), no deletes, no curated writes, no git push, no
crawling, credential patterns excluded from indexing (spec §11/§22). The
installer backs up any file it must modify and never deletes your vault.
