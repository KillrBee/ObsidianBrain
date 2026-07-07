"""Schema validation: spec §7 examples accepted, mutations rejected."""
from __future__ import annotations

import pytest

BASE_CONVERSION = {
    "title": "Legacy System BRD",
    "doc_type": "source_conversion",
    "source_file": "10-originals/docx/legacy-system-brd.docx",
    "source_format": "docx",
    "source_checksum": "sha256:" + "a" * 64,
    "converted_by": "markitdown",
    "converted_at": "2026-07-07T12:00:00Z",
    "source_modified_at": None,
    "project": "introhive",
    "domain": ["identity"],
    "status": "converted",
    "trust_level": "source-derived",
    "review_status": "unreviewed",
    "effective_from": None,
    "effective_to": None,
    "contains_tables": "unknown",
    "contains_images": False,
    "contains_comments": "unknown",
    "contains_ocr": False,
    "summary_file": None,
    "tags": [],
}

BASE_CURATED = {
    "title": "Dynamic Survivorship",
    "doc_type": "curated_synthesis",
    "created": "2026-07-07",
    "updated": "2026-07-07",
    "project": "introhive",
    "domain": [],
    "status": "active",
    "trust_level": "human-reviewed",
    "review_status": "reviewed",
    "source_files": [],
    "confidence": "medium",
    "supersedes": [],
    "superseded_by": None,
    "tags": [],
}

BASE_DECISION = {
    "title": "Adopt X",
    "doc_type": "decision",
    "decision_type": "architecture",
    "created": "2026-07-07",
    "status": "accepted",
    "decision_owner": "greg",
    "source_files": [],
    "confidence": "high",
    "supersedes": [],
    "superseded_by": None,
    "tags": [],
}

BASE_MEMORY = {
    "title": "Observation about X",
    "doc_type": "agent_memory",
    "created": "2026-07-07T12:00:00Z",
    "updated": "2026-07-07T12:00:00Z",
    "memory_type": "observation",
    "project": None,
    "confidence": "medium",
    "source": None,
    "agent": "claude",
    "review_status": "unreviewed",
    "tags": [],
}


@pytest.mark.parametrize("meta", [BASE_CONVERSION, BASE_CURATED, BASE_DECISION, BASE_MEMORY],
                         ids=["conversion", "curated", "decision", "memory"])
def test_spec_examples_validate(vault, meta):
    import sb_schemas
    assert sb_schemas.validate(vault, meta) == []


@pytest.mark.parametrize("mutation, base", [
    ({"trust_level": "totally-trusted"}, BASE_CONVERSION),
    ({"source_checksum": "md5:abc"}, BASE_CONVERSION),
    ({"review_status": "maybe"}, BASE_CURATED),
    ({"confidence": "extreme"}, BASE_CURATED),
    ({"decision_type": "vibes"}, BASE_DECISION),
    ({"status": "kinda-accepted"}, BASE_DECISION),
    ({"memory_type": "dream"}, BASE_MEMORY),
], ids=["bad-trust", "bad-checksum", "bad-review", "bad-confidence",
        "bad-decision-type", "bad-status", "bad-memory-type"])
def test_bad_enum_values_rejected(vault, mutation, base):
    import sb_schemas
    assert sb_schemas.validate(vault, {**base, **mutation})


@pytest.mark.parametrize("missing, base", [
    ("source_checksum", BASE_CONVERSION),
    ("title", BASE_CURATED),
    ("decision_type", BASE_DECISION),
    ("memory_type", BASE_MEMORY),
])
def test_missing_required_rejected(vault, missing, base):
    import sb_schemas
    meta = {k: v for k, v in base.items() if k != missing}
    assert sb_schemas.validate(vault, meta)


def test_unknown_doc_type_reported(vault):
    import sb_schemas
    assert sb_schemas.validate(vault, {"doc_type": "mystery"}) == ["no schema for doc_type 'mystery'"]


def test_minimal_validator_agrees_with_jsonschema(vault):
    import sb_schemas
    schema = sb_schemas.schema_for(vault, "curated_synthesis")
    good = sb_schemas._minimal_validate(schema, BASE_CURATED)
    bad = sb_schemas._minimal_validate(schema, {**BASE_CURATED, "confidence": "extreme"})
    assert good == [] and bad
