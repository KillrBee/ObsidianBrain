#!/usr/bin/env python3
"""sb_search — scoped search over vault collections (spec §21 contract).

Usage:
    sb_search.py --query Q --collection NAME [--project P] [--domain D]
                 [--status S] [--max-results N] [--backend auto|qmd|internal]
                 [--vault DIR]

Prints one JSON object:
    {"query": ..., "collection": ..., "backend": ...,
     "results": [{"path", "title", "score", "snippet",
                  "trust_level", "review_status", "source_file"}]}

Backend policy (plan D7/R1): use QMD when a binary is present and it works;
otherwise an internal scorer (ripgrep-prefiltered when rg is available)
guarantees the same output contract.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import sb_frontmatter  # noqa: E402
import sb_vault  # noqa: E402

MAX_RESULTS_CAP = 50
READ_CAP_BYTES = 512 * 1024


def tokenize(query: str) -> list[str]:
    return [t for t in re.findall(r"[a-z0-9]+", query.lower()) if len(t) > 1]


# ------------------------------------------------------------ internal ------
def _rg_prefilter(vault: Path, terms: list[str]) -> set[Path] | None:
    """Vault files matching any term, via ripgrep. None -> rg unavailable or
    failed (callers then scan every collection file).

    Runs from the vault root so results come back vault-relative; scoping to
    the collection happens by intersection in the caller, which sidesteps
    rg-vs-pathlib glob semantics entirely.
    """
    rg = shutil.which("rg")
    if not rg or not terms:
        return None
    cmd = [rg, "--files-with-matches", "-i", "--no-messages", "--type", "md"]
    for t in terms:
        cmd += ["-e", t]
    cmd.append(".")
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=60, cwd=str(vault))
    except (subprocess.TimeoutExpired, OSError):
        return None
    if proc.returncode not in (0, 1):  # 1 = no matches
        return None
    return {
        (vault / line.removeprefix("./")).resolve()
        for line in proc.stdout.decode().splitlines() if line
    }


def _passes_filters(meta: dict, project: str | None, domain: str | None,
                    status: str | None) -> bool:
    if project and str(meta.get("project") or "").lower() != project.lower():
        return False
    if domain:
        domains = [str(d).lower() for d in (meta.get("domain") or [])]
        if domain.lower() not in domains:
            return False
    if status and str(meta.get("status") or "").lower() != status.lower():
        return False
    return True


def _snippet(body: str, terms: list[str]) -> str:
    lines = [ln.strip() for ln in body.splitlines() if ln.strip()]
    chosen = ""
    for ln in lines:
        low = ln.lower()
        if any(t in low for t in terms):
            chosen = ln
            break
    if not chosen and lines:
        chosen = lines[0]
    chosen = re.sub(r"[#*_`>\[\]]", "", chosen).strip()
    return chosen[:240]


def _score(meta: dict, title: str, body_low: str, terms: list[str]) -> float:
    tf = sum(body_low.count(t) for t in terms)
    title_low = title.lower()
    title_hits = sum(1 for t in terms if t in title_low)
    tags_low = " ".join(str(x).lower() for x in (meta.get("tags") or []))
    tag_hits = sum(1 for t in terms if t in tags_low)
    if tf + title_hits + tag_hits == 0:
        return 0.0
    raw = math.log1p(tf) + 2.0 * title_hits + 1.0 * tag_hits
    # Trust preferences (spec §9.2) as ranking bonuses:
    if meta.get("trust_level") == "human-reviewed":
        raw += 0.6
    if meta.get("review_status") == "reviewed":
        raw += 0.4
    if meta.get("status") == "accepted":
        raw += 0.4
    if meta.get("confidence") == "high":
        raw += 0.2
    if meta.get("status") in ("superseded", "deprecated", "archived", "rejected"):
        raw -= 1.0
    if meta.get("superseded_by"):
        raw -= 1.0
    raw = max(raw, 0.01)
    return round(raw / (raw + 3.0), 4)


def internal_search(vault: Path, query: str, collection: str,
                    globs: list[str], project: str | None = None,
                    domain: str | None = None, status: str | None = None,
                    max_results: int = 10) -> list[dict]:
    terms = tokenize(query)
    files = sb_vault.collection_files(vault, globs)
    prefiltered = _rg_prefilter(vault, terms)
    if prefiltered is not None:
        files = [f for f in files if f.resolve() in prefiltered]

    results = []
    for f in files:
        try:
            text = f.read_text(encoding="utf-8", errors="replace")[:READ_CAP_BYTES]
        except OSError:
            continue
        meta, body = sb_frontmatter.parse(text)
        meta = meta or {}
        if not _passes_filters(meta, project, domain, status):
            continue
        title = str(meta.get("title") or f.stem)
        score = _score(meta, title, (title + "\n" + body).lower(), terms)
        if score <= 0:
            continue
        results.append({
            "path": str(f.relative_to(vault)),
            "title": title,
            "score": score,
            "snippet": _snippet(body, terms),
            "trust_level": meta.get("trust_level"),
            "review_status": meta.get("review_status"),
            "source_file": meta.get("source_file"),
        })
    results.sort(key=lambda r: (-r["score"], r["path"]))
    return results[:max_results]


# ---------------------------------------------------------------- qmd -------
def qmd_search(vault: Path, query: str, collection: str,
               max_results: int) -> list[dict] | None:
    """Best-effort QMD invocation; None means fall back to internal."""
    qmd = shutil.which("qmd")
    if not qmd:
        return None
    try:
        proc = subprocess.run(
            [qmd, "search", query, "--collection", collection,
             "--json", "--limit", str(max_results)],
            capture_output=True, timeout=60, cwd=str(vault),
        )
        if proc.returncode != 0:
            return None
        payload = json.loads(proc.stdout.decode())
    except Exception:
        return None
    raw = payload.get("results", payload) if isinstance(payload, dict) else payload
    if not isinstance(raw, list):
        return None
    results = []
    for item in raw[:max_results]:
        if not isinstance(item, dict):
            continue
        path = item.get("path") or item.get("file") or ""
        meta = {}
        abs_path = vault / path
        if abs_path.is_file():
            meta, _ = sb_frontmatter.read_note(abs_path)
            meta = meta or {}
        results.append({
            "path": path,
            "title": item.get("title") or meta.get("title") or Path(path).stem,
            "score": float(item.get("score", 0.0)),
            "snippet": item.get("snippet") or item.get("preview") or "",
            "trust_level": meta.get("trust_level"),
            "review_status": meta.get("review_status"),
            "source_file": meta.get("source_file"),
        })
    return results


# ---------------------------------------------------------------- api -------
def search(vault: Path, query: str, collection: str, project: str | None = None,
           domain: str | None = None, status: str | None = None,
           max_results: int = 10, backend: str = "auto") -> dict:
    max_results = max(1, min(int(max_results), MAX_RESULTS_CAP))
    cfg = sb_vault.load_collections(vault)
    collections = cfg["collections"]

    if collection == "all":
        globs = [g for name in cfg["search_priority"]
                 for g in collections.get(name, [])]
    elif collection in collections:
        globs = collections[collection]
    else:
        raise ValueError(
            f"unknown collection '{collection}' (known: {', '.join(sorted(collections))}, all)")

    used_backend = "internal"
    results: list[dict] | None = None
    if backend in ("auto", "qmd") and collection != "all":
        results = qmd_search(vault, query, collection, max_results)
        if results is not None:
            used_backend = "qmd"
    if results is None:
        if backend == "qmd":
            raise RuntimeError("qmd backend requested but unavailable")
        results = internal_search(vault, query, collection, globs, project,
                                  domain, status, max_results)
        used_backend = "ripgrep" if shutil.which("rg") else "internal"

    sb_vault.log_access(vault, "search", collection=collection, query=query,
                        backend=used_backend, results=len(results))
    return {"query": query, "collection": collection,
            "backend": used_backend, "results": results}


def staged_search(vault: Path, query: str, project: str | None = None,
                  max_results: int = 10) -> list[dict]:
    """Spec §9.1/§13.2: walk collections in priority order, dedupe by path,
    keep earlier-stage hits ahead of later ones at equal score."""
    cfg = sb_vault.load_collections(vault)
    priority = cfg["search_priority"]
    merged: dict[str, dict] = {}
    for stage, name in enumerate(priority):
        if name not in cfg["collections"]:
            continue
        hits = internal_search(vault, query, name, cfg["collections"][name],
                               project=project, max_results=max_results)
        bonus = 0.05 * (len(priority) - stage)
        for h in hits:
            if h["path"] not in merged:
                h["collection"] = name
                h["stage_score"] = round(h["score"] + bonus, 4)
                merged[h["path"]] = h
    ranked = sorted(merged.values(), key=lambda r: -r["stage_score"])
    return ranked[:max_results]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--query", required=True)
    ap.add_argument("--collection", default="all")
    ap.add_argument("--project")
    ap.add_argument("--domain")
    ap.add_argument("--status")
    ap.add_argument("--max-results", type=int, default=10)
    ap.add_argument("--backend", choices=["auto", "qmd", "internal"], default="auto")
    ap.add_argument("--vault")
    args = ap.parse_args()

    vault = sb_vault.vault_root(args.vault)
    try:
        out = search(vault, args.query, args.collection, args.project,
                     args.domain, args.status, args.max_results, args.backend)
    except (ValueError, RuntimeError) as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 1
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
