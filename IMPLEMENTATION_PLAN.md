# Implementation Plan — Obsidian Second Brain & Agentic Retrieval Stack

Plan for building the installer repo that produces the `~/SecondBrain` stack described in the
system specification (Obsidian + Git + MarkItDown + QMD + Basic Memory + MCP).

---

## 0. Guiding decisions (locked in unless overridden)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| D1 | Installer language | Bash (zsh-compatible, `bash 3.2`-safe) + small Python helpers | macOS ships bash 3.2; Python is a hard dependency anyway. Anything needing JSON/YAML/frontmatter logic goes in Python, not bash. |
| D2 | Originals in Git | **Not committed** by default; `--enable-lfs` opt-in | Spec's recommended default. |
| D3 | Basic Memory exposure | Direct MCP server (`uvx basic-memory mcp`), not wrapped | Spec's "recommended first implementation." Unified wrapper is a later phase. |
| D4 | Custom second-brain MCP server | Python + FastMCP, thin wrappers over the shell scripts | Keeps scripts as the single implementation; MCP is just an interface. |
| D5 | Python env | `uv` (preferred), `pipx` fallback | Spec allows either; uv is faster and handles Python installs too. |
| D6 | Shell test framework | `bats-core` (brew-installable) | Standard for shell; supports fixtures, setup/teardown, TAP output. |
| D7 | QMD | Treat as pluggable backend behind wrapper scripts; ship `ripgrep`-based fallback backend | QMD's install path/CLI surface must be verified at implementation start (see Risk R1). Wrappers guarantee the agent-facing JSON contract either way. |
| D8 | Vault path | `~/SecondBrain`, overridable via `--vault-dir` / `SB_VAULT_DIR` | Testability requires non-home installs. |

**Every script that touches the vault takes the vault root from config, never hardcodes `~/SecondBrain`.** This is what makes the test suite possible (tests install into a temp dir).

---

## 1. Installer repo structure

The installer repo (this repo, `ObsidianBrain`) is distinct from the vault it creates.
Vault scripts/templates live here under `payload/` and are *copied* into `~/SecondBrain/70-scripts` and `60-index-config` at install time, so the vault is self-contained after install.

```text
ObsidianBrain/
  README.md                       # what this is, quickstart, curl one-liner
  IMPLEMENTATION_PLAN.md          # this file
  LICENSE
  VERSION                         # single-line semver; used by --upgrade
  install.sh                      # entry point (modes: interactive/default/dry-run/repair/upgrade/uninstall)
  uninstall.sh                    # thin shim -> install.sh --uninstall

  lib/                            # installer-only bash modules (sourced by install.sh)
    common.sh                     # logging, colors, die(), run() [dry-run aware], backup_file()
    checks.sh                     # macOS version, arch, disk space, existing-install detection
    brew.sh                       # Homebrew install/verify, formula install with retry
    deps.sh                       # git, python, uv/pipx, node, jq, rg, fd + optional deps
    obsidian.sh                   # brew install --cask obsidian, or print manual instructions
    vault.sh                      # create directory tree, seed README/MEMORY.md, git init, .gitignore
    payload.sh                    # copy payload/ scripts+configs into vault, chmod +x, version-stamp
    markitdown.sh                 # uv tool install markitdown[pdf,docx,pptx,xlsx] (extras configurable)
    qmd.sh                        # install/verify QMD; register collections; fallback-backend selection
    basic_memory.sh               # install basic-memory; set project root to 40-agent-memory
    mcp_claude.sh                 # write/merge .mcp.json (project) or `claude mcp add` (user scope)
    mcp_codex.sh                  # backup + managed-section merge into ~/.codex/config.toml
    validate.sh                   # post-install command checks, sample conversion + search smoke test
    report.sh                     # installation report (installed/configured/skipped/failed)

  payload/                        # everything that ends up INSIDE the vault
    vault-files/
      README.md.tmpl
      MEMORY.md.tmpl
      gitignore.tmpl              # -> ~/SecondBrain/.gitignore (spec §4.2 defaults)
    scripts/                      # -> ~/SecondBrain/70-scripts/
      lib/
        sb_common.sh              # vault-root resolution, config loading, JSON logging helpers
      convert/
        convert_new_documents.sh  # pipeline driver (spec §12, steps 1–11)
        reconvert_document.sh
        convert_one.py            # single-file: markitdown call + frontmatter injection + manifest entry
      index/
        update_qmd_indexes.sh     # (re)index all collections; called by convert pipeline
      search/
        sb_search.sh              # core: query -> backend -> normalized JSON (path,title,score,snippet,trust_level,review_status,source_file)
        search_curated.sh         # thin wrappers: fixed collection + filters
        search_decisions.sh
        search_sources.sh
        search_agent_memory.sh
        search_context_packs.sh
        backends/
          qmd_backend.sh          # QMD JSON search path
          ripgrep_backend.sh      # rg + python ranking fallback (guarantees contract if QMD unavailable)
      context/
        build_context_pack.py     # staged retrieval -> pack assembly under token budget (Phase 5)
        refresh_context_pack.py
        archive_context_pack.sh
        find_relevant_notes.py
      maintenance/
        validate_frontmatter.py   # schema check against 60-index-config/schemas/*.yaml
        find_unreviewed_conversions.py
        find_stale_context_packs.py
        find_superseded_notes.py
        checksum_inventory.py     # dedupe detection over 10-originals
      mcp/
        second-brain-mcp          # launcher: uv run server.py
        server.py                 # FastMCP server exposing tools in §4 below
        policy.py                 # path allowlists, write boundaries, result caps
    config/                       # -> ~/SecondBrain/60-index-config/
      qmd/collections.yaml        # 6 collections + glob patterns (spec §13.1)
      qmd/exclude-patterns.txt    # security excludes (spec §22)
      basic-memory/config.json    # project root = 40-agent-memory
      mcp/mcp.claude.json.tmpl    # project .mcp.json template
      mcp/codex-managed.toml.tmpl # managed section for ~/.codex/config.toml
      schemas/
        source_conversion.yaml    # frontmatter schemas (spec §7.1–7.4), as JSON-Schema-in-YAML
        curated_synthesis.yaml
        decision.yaml
        agent_memory.yaml
        context_pack.yaml
      manifests/
        conversion-manifest.json  # seeded as {"documents": []}

  tests/
    run_tests.sh                  # entry: bats + pytest, honors CI env
    helpers/
      setup_vault.bash            # installs into mktemp dir with --vault-dir
      fixtures.bash
    fixtures/
      sample.pdf  sample.docx  sample.pptx  sample.xlsx  sample.html
      corrupt.pdf                 # failure-path fixture
      vault-with-user-edits/      # for idempotency/repair tests
      codex-config-existing.toml  # for merge tests
      mcp-json-existing.json
    bats/
      10_install_dry_run.bats
      11_install_default.bats
      12_idempotency.bats
      13_repair_upgrade.bats
      14_uninstall.bats
      20_conversion_pipeline.bats
      21_manifest.bats
      30_search_contract.bats
      40_mcp_config_merge.bats
    pytest/
      test_frontmatter_schemas.py
      test_convert_one.py
      test_context_pack_budget.py
      test_mcp_tools.py           # in-process FastMCP client tests
      test_policy_boundaries.py   # write/read boundary enforcement

  .github/workflows/ci.yml        # macos-latest: shellcheck + bats + pytest (dry-run + temp-vault installs)
  .shellcheckrc
  Makefile                        # make test / make lint / make install-dev
```

---

## 2. Shell scripts — key behaviors

### 2.1 `install.sh`

```bash
./install.sh [--mode interactive|default] [--dry-run] [--repair] [--upgrade] [--uninstall]
             [--vault-dir PATH] [--enable-lfs] [--with-ocr] [--with-transcription]
             [--skip-obsidian] [--no-mcp]
```

- **Idempotent by construction:** every step is "ensure state X", never "do action Y."
  Re-running detects existing state and reports `skipped (already configured)`.
- **Dry-run:** `run()` in `lib/common.sh` prints commands instead of executing when `DRY_RUN=1`.
  All mutations go through `run()`/`write_file()`/`backup_file()` — no naked `mv`/`rm`/`brew` calls.
- **Backups:** any pre-existing file the installer would modify (`~/.codex/config.toml`, `.mcp.json`,
  vault `.gitignore`) is copied to `<file>.bak.<timestamp>` first.
- **Fail-safe ordering:** dependency checks → installs → vault skeleton → payload copy → tool config
  → MCP config → validation → report. A failure marks the step failed in the report and continues
  with independent steps; MCP config steps are no-ops when the client isn't installed.
- **State file:** `~/SecondBrain/60-index-config/install-state.json` records installer version,
  chosen options, per-step status. `--repair` re-runs failed/missing steps; `--upgrade` re-copies
  payload scripts (diffing first, backing up user-modified copies) and re-validates.
- **Uninstall:** removes installed brew-managed tools *only on confirmation*, removes MCP managed
  sections (restoring from backup), and **never deletes the vault** — it prints how to do that manually.
- **Report:** ends with a table — component / action (installed | verified | configured | skipped | FAILED)
  / detail — and writes it to `80-logs/install-report-<timestamp>.md` (spec §16.28, §24.14).

### 2.2 Conversion pipeline (`convert_new_documents.sh` + `convert_one.py`)

Implements spec §12 exactly:

1. Scan `00-inbox/raw-drops/` and `10-originals/` (files not yet in the manifest by checksum).
2. Detect type by extension (+ `file` fallback); route inbox files into `10-originals/<type>/` (copy, never move-with-modify; originals are immutable from then on).
3. `sha256` checksum → skip if manifest has a successful conversion for that checksum.
4. `convert_one.py`: run MarkItDown → prepend §7.1 frontmatter (source path, checksum, format, timestamps, `trust_level: source-derived`, `review_status: unreviewed`) → write to `20-converted/<format>-md/`.
5. Append/update manifest entry (spec §12 JSON fields) — manifest writes are atomic (write temp + `mv`).
6. Log per-file success/failure to `80-logs/conversion/` (JSON lines); failures never abort the batch.
7. Trigger `update_qmd_indexes.sh` once at the end.

### 2.3 Search wrappers (`sb_search.sh` + per-collection wrappers)

Contract (spec §21): every wrapper accepts `--query`, optional `--project`, `--domain`,
`--status`, `--max-results` (default 10, hard cap 50) and emits **one JSON object** on stdout:

```json
{"query": "...", "collection": "curated", "backend": "qmd", "results": [
  {"path": "...", "title": "...", "score": 0.91, "snippet": "...",
   "trust_level": "human-reviewed", "review_status": "reviewed", "source_file": null}
]}
```

- Backend selection: `qmd_backend.sh` if QMD is installed and the collection is registered,
  else `ripgrep_backend.sh` (rg over the collection globs + a small Python scorer that reads
  frontmatter for trust/review fields). The consumer-facing JSON is identical.
- Post-filters (`project`, `status`) are applied on frontmatter in Python, backend-agnostic.
- Every invocation appends one line to `80-logs/agent-access/access.jsonl` (tool, query, collection, result count) — this is the audit trail for agentic lookup.

### 2.4 MCP server (`payload/scripts/mcp/server.py`)

FastMCP server exposing spec §10 tools, delegating to the scripts above. Enforcement in `policy.py`:

- **Read allowlist:** `20-converted/`, `30-curated/`, `40-agent-memory/`, `50-context-packs/`, `MEMORY.md`. `read_note` rejects paths outside these (and any `..` traversal) — no reads of `10-originals/` content, only `read_source_metadata` (manifest lookup).
- **Write allowlist:** `40-agent-memory/**` and `50-context-packs/{drafts,active}/**` only. All writes stamp §7.4 frontmatter with `review_status: unreviewed`.
- **Not exposed** (spec §11): delete, overwrite-curated, bulk ops, git commit/push, unbounded reads. `search_all_markdown` exists but is capped and excluded-pattern-aware.
- Tool list, v1: the five search tools, four read tools, `find_relevant_notes`, `build_context_pack`, the four memory tools, and read-only maintenance tools (`find_unreviewed_conversions`, `find_stale_context_packs`, `find_superseded_notes`, `validate_frontmatter`). `convert_new_documents`/`update_indexes` are exposed but touch only their designated output dirs.

---

## 3. Config templates

| Template | Installed to | Notes |
|---|---|---|
| `gitignore.tmpl` | `~/SecondBrain/.gitignore` | Spec §4.2 defaults + `10-originals/` ignore (removed when `--enable-lfs`, which instead writes `.gitattributes`). |
| `qmd/collections.yaml` | `60-index-config/qmd/` | 6 collections with the §13.1 globs; exclude patterns from §22 referenced globally. |
| `basic-memory/config.json` | `60-index-config/basic-memory/` + registered via `basic-memory` CLI | Project root pinned to `40-agent-memory/`. |
| `mcp.claude.json.tmpl` | `~/SecondBrain/.mcp.json` (project scope) and/or `claude mcp add --scope user` | Two servers: `second-brain` (custom) + `basic-memory` (`uvx basic-memory mcp`). Merge-not-overwrite if `.mcp.json` exists (jq deep-merge under `mcpServers`, backup first). |
| `codex-managed.toml.tmpl` | merged into `~/.codex/config.toml` | Delimited managed block: `# >>> second-brain managed >>> … # <<< second-brain managed <<<`. Merge = backup, strip old managed block, append new, validate with `python -c "import tomllib"`. On parse failure of the *existing* file: abort that step, report, leave untouched. |
| `schemas/*.yaml` | `60-index-config/schemas/` | JSON Schema for each frontmatter type (§7.1–7.4 + context packs). Single source of truth for `validate_frontmatter.py`, `convert_one.py`, and MCP write stamping. |
| `README.md.tmpl` / `MEMORY.md.tmpl` | vault root | README documents the source-of-truth model (§6), lookup priority (§8), and script usage. MEMORY.md seeds the agent-memory index. |

---

## 4. Test plan

Three layers, all runnable via `make test` and in CI (macos runner).

### 4.1 Static

- `shellcheck` on `install.sh`, `lib/*.sh`, all payload scripts.
- `ruff` + `mypy` (loose) on Python helpers.

### 4.2 Unit / component (fast, no brew)

| Test | Verifies |
|---|---|
| `test_frontmatter_schemas.py` | Each §7 schema accepts its spec example and rejects missing required keys / bad enums (`trust_level`, `status`, `memory_type`). |
| `test_convert_one.py` | Frontmatter injection (checksum, source path, timestamps), output path routing per format, corrupt-input produces manifest `conversion_status: "failure"` + error entry, original file bytes untouched (checksum before == after). |
| `21_manifest.bats` | Manifest atomicity, dedupe-by-checksum (same file twice → one conversion), reconvert updates rather than duplicates. |
| `30_search_contract.bats` | Both backends emit identical JSON shape; `max_results` cap; excluded patterns (`.env`, `*.pem`, `secrets.*` planted in fixtures) never appear in results; project/status filters. |
| `test_policy_boundaries.py` | MCP `read_note` rejects `10-originals/…`, `../../etc/passwd`, absolute paths outside vault; `write_agent_memory_note` rejects paths in `30-curated/`; writes get `review_status: unreviewed`. |
| `test_context_pack_budget.py` | Pack ≤ `max_token_target` (tiktoken-ish estimate), source_notes listed in frontmatter, refresh archives prior version to `50-context-packs/archived/` instead of overwriting. |
| `40_mcp_config_merge.bats` | Existing `.mcp.json` / `config.toml` fixtures: user keys preserved, backup created, managed section replaced cleanly on second run, invalid existing TOML → step fails safely without modification. |

### 4.3 Installer integration (temp vault)

Each test installs into `mktemp -d` via `--vault-dir`, with brew/uv steps stubbed where possible (`SB_SKIP_BREW=1` honored by `lib/brew.sh` in test mode).

| Test | Verifies |
|---|---|
| `10_install_dry_run.bats` | Dry run performs **zero** filesystem writes outside the log, prints full action plan. |
| `11_install_default.bats` | Full directory tree from spec §5 exists; git repo initialized; `.gitignore` matches template; scripts executable; manifest seeded; report file written and lists every §16 step as installed/verified/skipped. |
| `12_idempotency.bats` | Second run: no duplicate config blocks, no changed mtimes on user-edited files, all steps report skipped/verified. Fixture vault with user edits survives untouched. |
| `13_repair_upgrade.bats` | Delete a script + corrupt a config → `--repair` restores only those; `--upgrade` re-copies payload, backs up user-modified script before replacing. |
| `14_uninstall.bats` | Vault untouched; managed MCP sections removed; codex backup restored. |
| `20_conversion_pipeline.bats` | Drop the four fixtures (pdf/docx/pptx/xlsx) into `00-inbox/raw-drops` → run pipeline → valid-frontmatter Markdown in the right `20-converted/` subdirs, manifest entries, originals routed and byte-identical, index update invoked (spec success criteria 3–5, 12). |

### 4.4 Acceptance script

`tests/acceptance.sh` — run manually on a real Mac (or CI nightly), walks spec §24 success
criteria 1–14 end-to-end including a live MCP handshake (`claude mcp list` / spawning `server.py`
and calling `search_curated` over stdio) and prints a pass/fail checklist.

---

## 5. Build order (maps to spec §25 phases)

**Milestone 0 — Repo scaffold (½ day)**
Repo skeleton, `lib/common.sh` (logging, `run()`, dry-run, backups), `install.sh` arg parsing +
mode dispatch, CI with shellcheck, `Makefile`. *Exit: `./install.sh --dry-run` prints a full plan.*

**Milestone 1 — Vault + conversion (spec Phase 1)**
`checks.sh`, `brew.sh`, `deps.sh`, `vault.sh` (tree, git init, templates), `payload.sh`,
`markitdown.sh`, `convert_one.py`, pipeline script, manifest, schemas, obsidian cask step.
Tests: 10/11/12, 20/21, frontmatter + convert unit tests.
*Exit: fixtures convert with valid frontmatter into a temp vault; Obsidian can open it.*

**Milestone 2 — Search & indexing (spec Phase 2)**
Resolve **R1 (QMD)** first. `sb_search.sh` + both backends + wrappers, `update_qmd_indexes.sh`,
collection config, access logging, exclude patterns.
Tests: 30_search_contract against both backends.
*Exit: `search_curated.sh --query x` returns contract JSON on a seeded vault.*

**Milestone 3 — Agent memory (spec Phase 3)**
`basic_memory.sh` install + root config, memory folder discipline (seed subdirs + README),
sample write/read validation step in `validate.sh`.
*Exit: `uvx basic-memory mcp` serves against `40-agent-memory`; note visible in Obsidian.*

**Milestone 4 — MCP integration (spec Phase 4)**
`server.py` + `policy.py` + launcher, `mcp_claude.sh`, `mcp_codex.sh` (merge logic),
no-op detection for missing clients.
Tests: 40_mcp_config_merge, test_mcp_tools, test_policy_boundaries.
*Exit: Claude Code and Codex both list `second-brain` + `basic-memory` tools; §11 forbidden ops absent.*

**Milestone 5 — Context packs (spec Phase 5)**
`build_context_pack.py` (staged retrieval per §9.1, ranking per §9.2 preference order, token
budget), refresh/archive scripts, stale-pack maintenance tool, MCP exposure.
Tests: context-pack budget/archive tests.
*Exit: agent builds a topic pack ≤ budget without vault-wide reads (success criteria 10–11).*

**Milestone 6 — Hardening & release**
`validate.sh` full sweep + report polish, `acceptance.sh` on a clean machine/VM,
uninstall/repair/upgrade paths finished, README + curl-install instructions, tag `v0.1.0`.

---

## 6. Risks & open items

- **R1 — QMD availability/CLI surface. RESOLVED 2026-07-10.** QMD is
  [tobi/qmd](https://github.com/tobi/qmd), npm package `@tobilu/qmd` (verified v2.5.3).
  Integration facts: `qmd collection add <path> --name sb-<n> --mask <glob>` (brace masks work
  for multi-glob collections; config in `$XDG_CONFIG_HOME/qmd/index.yml`), `qmd update` to
  re-index, `qmd search <q> -c <name> --json -n <k>` returns
  `[{docid, score, file: "qmd://<coll>/<rel>", line, title, snippet}]`. Quirk: qmd exits 0 even
  on errors, so backend fallback keys on stdout-not-JSON, not exit codes. The ripgrep fallback
  remains for qmd-less installs and unregistered collections.
- **R2 — MarkItDown extras weight.** `markitdown[all]` drags in heavy deps (ffmpeg/OCR chains).
  Install `[pdf,docx,pptx,xlsx]` by default; `--with-ocr` adds tesseract+poppler, `--with-transcription`
  adds ffmpeg — matching spec §17's optional list.
- **R3 — Codex TOML merge fragility.** No `jq`-equivalent for TOML in stock macOS. Managed-block
  string surgery + `tomllib` validation (D-template above) avoids a TOML-writing dependency; on any
  doubt the step aborts with the backup intact.
- **R4 — Obsidian cask under `curl | bash`.** `brew install --cask obsidian` can require password/
  permissions in some environments. The step degrades to printed instructions (spec §16.8 allows this).
- **R5 — bash 3.2.** No associative arrays, no `mapfile` in installer bash. Anything tempted to use
  them goes to Python (D1).
- **Open decision (deferred, defaulted):** committing `20-converted/` to git. Default: yes, commit
  converted Markdown (it's text, it's the retrieval substrate, and git history of conversions is
  useful); revisit if repo size becomes a problem.

---

## 7. Definition of done

All spec §24 success criteria pass via `tests/acceptance.sh` on a clean macOS machine, CI is green
(shellcheck + bats + pytest), and running `./install.sh` twice in a row produces an identical
vault with a report showing only `verified`/`skipped` on the second run.
