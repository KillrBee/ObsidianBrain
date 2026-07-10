"""sb_similarity — near-duplicate detection for agent memory notes.

Deliberately simple and deterministic: word-boundary token sets and Jaccard
overlap, no embeddings. Used by the policy write-guard (refuse duplicate
creation) and the find_duplicate_memory maintenance report.
"""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

STOPWORDS = frozenset(
    "the a an and or of to in on for with is are was were this that it as by "
    "at be from not no has have had will would can could should about into "
    "over under out up down what when where which who how all any".split()
)

TITLE_JACCARD = 0.6   # near-identical titles
BODY_JACCARD = 0.5    # heavily overlapping content terms
TOP_TERMS = 12


def tokens(text: str) -> set[str]:
    return {
        t for t in re.findall(r"[a-z0-9]+", (text or "").lower())
        if len(t) > 2 and t not in STOPWORDS
    }


def title_tokens(meta: dict | None, path: Path | str) -> set[str]:
    title = (meta or {}).get("title") or Path(path).stem.replace("-", " ")
    return tokens(str(title))


def top_terms(body: str, k: int = TOP_TERMS) -> set[str]:
    counts = Counter(
        t for t in re.findall(r"[a-z0-9]+", (body or "").lower())
        if len(t) > 2 and t not in STOPWORDS
    )
    return {t for t, _ in counts.most_common(k)}


def jaccard(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def similarity(meta_a: dict | None, body_a: str, path_a: Path | str,
               meta_b: dict | None, body_b: str, path_b: Path | str) -> str | None:
    """Return a human-readable reason when the notes look like duplicates,
    else None."""
    if Path(path_a).name == Path(path_b).name:
        return f"same filename '{Path(path_a).name}'"
    tj = jaccard(title_tokens(meta_a, path_a), title_tokens(meta_b, path_b))
    if tj >= TITLE_JACCARD:
        return f"title overlap {tj:.2f}"
    bj = jaccard(top_terms(body_a), top_terms(body_b))
    if bj >= BODY_JACCARD:
        return f"content-term overlap {bj:.2f}"
    return None
