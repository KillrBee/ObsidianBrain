---
name: second-brain
description: Retrieve from and write to the user's SecondBrain vault via the second-brain MCP tools. Use when a task needs durable knowledge (decisions, people, systems, preferences, project state, lessons learned) or produces facts worth keeping across sessions. Covers the staged retrieval order and the memory-write discipline — search before write, append over create, update over correct, no duplication.
---

# SecondBrain retrieval and memory discipline

The vault is a trust-layered knowledge base. Tools are the only interface —
never crawl its file tree. Every result carries `trust_level` and
`review_status`; anything `unreviewed` is a lead, not a fact.

## Retrieval (staged, cheapest-trustworthy first)

1. `search_decisions` — accepted decisions outrank everything else
2. `search_curated` — human-reviewed synthesis
3. `read_context_pack` / `find_relevant_notes` — prebuilt task context
4. `search_agent_memory` — machine memory
5. `search_sources` — converted documents (cite as evidence, note review status)

Stop as soon as you have enough. For a multi-step task, ask for
`build_context_pack` once and work from the pack instead of re-searching.

## Writing memory

- **Search first.** Run `find_relevant_notes` or `search_agent_memory` before
  any write. If a note on the topic exists, add to it — don't start a rival.
- **Append over create.** Facts about an entity go through
  `append_observation` / `append_relation`: one note per entity, timestamped
  bullets. This is the default write path.
- **`write_agent_memory_note` is for genuinely new topics only.** It refuses
  suspected near-duplicates and names the existing note — append there
  instead. Pass `force=true` only after confirming the topic is distinct.
- **Update over correct.** When a fact changes, rewrite the same note (write
  to its existing path); never add a separate "correction" note. Use
  `superseded_by` frontmatter for true replacements.
- **Deltas, not transcripts.** Store conclusions, constraints, decisions —
  never conversation logs or restated file contents.
- **Link, don't copy.** Reference curated notes and sources with
  `[[wikilinks]]`; duplicating their content into memory creates drift.
- **One fact per file, small files.** If a note needs sections for unrelated
  topics, it should be several notes.
- Everything you write starts `review_status: unreviewed`; a human promotes
  it to curated. Never attempt writes into `30-curated/` or `10-originals/`.

## Routing — what goes where

- **Vault**: durable, cross-project knowledge — decisions, people, systems,
  preferences, lessons, project state.
- **Project-local memory** (CLAUDE.md, AGENTS.md, platform auto-memory):
  repo-specific mechanics only — build quirks, test commands, local paths.
  For anything durable, store a one-line pointer to the vault note, not a
  copy of its content.

## Housekeeping signals

`find_duplicate_memory` reports suspected duplicate clusters;
`find_unreviewed_conversions` and `find_stale_context_packs` feed the human
review queue. Surface their findings — never merge or delete notes yourself.
