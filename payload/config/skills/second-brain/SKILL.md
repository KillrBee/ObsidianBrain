---
name: second-brain
description: Retrieve from and write to the user's SecondBrain vault. Use when a task needs durable knowledge (decisions, people, systems, preferences, project state, lessons learned) or produces facts worth keeping across sessions. Works through the second-brain MCP tools when available, or the vault's shell scripts when MCP is not configured in this session (works with any provider, including Bedrock-provisioned Claude). Covers staged retrieval order and the memory-write discipline — search before write, append over create, update over correct, no duplication.
---

# SecondBrain retrieval and memory discipline

The vault ({{VAULT_DIR}}) is a trust-layered knowledge base. Use the tools or
scripts below — never crawl its file tree. Every result carries `trust_level`
and `review_status`; anything `unreviewed` is a lead, not a fact.

## Two access paths — pick whichever this session has

**MCP path** (preferred when the `second-brain` server is connected): the
typed tools named below.

**Shell path** (always works where Bash is available — no MCP registration
needed; use it when the MCP tools are absent, e.g. enterprise-restricted
sessions). All scripts return JSON and run from any working directory:

```bash
# Retrieval (staged — same order as the MCP tools)
{{VAULT_DIR}}/70-scripts/search/search_decisions.sh --query "..." [--project P] [--max-results N]
{{VAULT_DIR}}/70-scripts/search/search_curated.sh --query "..." [--project P] [--status S]
{{VAULT_DIR}}/70-scripts/search/search_agent_memory.sh --query "..."
{{VAULT_DIR}}/70-scripts/search/search_sources.sh --query "..."
{{VAULT_DIR}}/70-scripts/context/find_relevant_notes.py --topic "..." [--project P]

# Context packs
{{VAULT_DIR}}/70-scripts/context/build_context_pack.py --topic "..." [--project P] [--max-tokens N]

# Memory writes (same dedup guard and unreviewed stamping as MCP)
{{VAULT_DIR}}/70-scripts/memory/remember.sh observe "Entity" "fact learned" --confidence high
{{VAULT_DIR}}/70-scripts/memory/remember.sh relate "Entity A" depends_on "Entity B"
{{VAULT_DIR}}/70-scripts/memory/remember.sh note 40-agent-memory/observations/topic.md "content"
{{VAULT_DIR}}/70-scripts/memory/remember.sh review 40-agent-memory/observations/topic.md
{{VAULT_DIR}}/70-scripts/memory/remember.sh summarize 20-converted/docx-md/some-doc.md

# Conversion & maintenance
{{VAULT_DIR}}/70-scripts/convert/convert_new_documents.sh
{{VAULT_DIR}}/70-scripts/maintenance/find_duplicate_memory.py
{{VAULT_DIR}}/70-scripts/maintenance/validate_frontmatter.py
```

`remember.sh` exits 3 when it suspects a duplicate and names the existing
note on stderr — append there instead of retrying; `--force` only after
confirming the topic is genuinely distinct. Read a note by path with your
normal file tools only after search has named it.

## Retrieval (staged, cheapest-trustworthy first)

1. `search_decisions` — accepted decisions outrank everything else
2. `search_curated` — human-reviewed synthesis
3. `read_context_pack` / `find_relevant_notes` — prebuilt task context
4. `search_agent_memory` — machine memory
5. `search_sources` — converted documents (cite as evidence, note review status)

Stop as soon as you have enough. For a multi-step task, build one context
pack and work from it instead of re-searching.

## Writing memory

- **Search first.** `find_relevant_notes` or `search_agent_memory` before any
  write. If a note on the topic exists, add to it — don't start a rival.
- **Append over create.** Facts about an entity go through `observe`/`relate`
  (`append_observation`/`append_relation` on MCP): one note per entity,
  timestamped bullets. This is the default write path.
- **New-note writes are for genuinely new topics only** and refuse suspected
  near-duplicates, naming the existing note — append there instead.
- **Update over correct.** When a fact changes, rewrite the same note (write
  to its existing path); never add a "correction" note. Use `superseded_by`
  frontmatter for true replacements.
- **Deltas, not transcripts.** Store conclusions, constraints, decisions —
  never conversation logs or restated file contents.
- **Link, don't copy.** Reference curated notes and sources with
  `[[wikilinks]]`; duplicating content into memory creates drift.
- Everything you write starts `review_status: unreviewed`; a human promotes
  it. Never write into `30-curated/` or `10-originals/`.

## Routing — what goes where

- **Vault**: durable, cross-project knowledge — decisions, people, systems,
  preferences, lessons, project state.
- **Project-local memory** (CLAUDE.md, AGENTS.md, platform auto-memory):
  repo-specific mechanics only. For durable facts, store a one-line pointer
  to the vault note, not a copy.

## Housekeeping signals

`find_duplicate_memory` reports suspected duplicate clusters;
`find_unreviewed_conversions` and `find_stale_context_packs` feed the human
review queue. Surface findings — never merge or delete notes yourself.
