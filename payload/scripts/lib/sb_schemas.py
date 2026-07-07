"""sb_schemas — frontmatter validation against 60-index-config/schemas/*.yaml.

Uses jsonschema when available; falls back to a minimal validator covering
required / type / enum / const, which is all the shipped schemas need.
"""
from __future__ import annotations

from pathlib import Path

import yaml

try:
    import jsonschema
    _HAVE_JSONSCHEMA = True
except ImportError:
    _HAVE_JSONSCHEMA = False

_SCHEMA_CACHE: dict = {}


def load_schemas(vault: Path) -> dict[str, dict]:
    key = str(vault)
    if key not in _SCHEMA_CACHE:
        schemas = {}
        schema_dir = vault / "60-index-config" / "schemas"
        for p in sorted(schema_dir.glob("*.yaml")):
            with open(p) as f:
                schema = yaml.safe_load(f)
            if isinstance(schema, dict) and schema.get("title"):
                schemas[schema["title"]] = schema
        _SCHEMA_CACHE[key] = schemas
    return _SCHEMA_CACHE[key]


def schema_for(vault: Path, doc_type: str) -> dict | None:
    return load_schemas(vault).get(doc_type)


def validate(vault: Path, meta: dict) -> list[str]:
    """Return a list of human-readable errors; empty list = valid."""
    doc_type = meta.get("doc_type")
    if not doc_type:
        return ["missing doc_type"]
    schema = schema_for(vault, str(doc_type))
    if schema is None:
        return [f"no schema for doc_type '{doc_type}'"]
    if _HAVE_JSONSCHEMA:
        validator = jsonschema.Draft7Validator(schema)
        return [
            f"{'.'.join(str(x) for x in e.path) or '<root>'}: {e.message}"
            for e in validator.iter_errors(meta)
        ]
    return _minimal_validate(schema, meta)


def _type_ok(value, expected) -> bool:
    types = expected if isinstance(expected, list) else [expected]
    for t in types:
        if t == "string" and isinstance(value, str):
            return True
        if t == "number" and isinstance(value, (int, float)) and not isinstance(value, bool):
            return True
        if t == "boolean" and isinstance(value, bool):
            return True
        if t == "array" and isinstance(value, list):
            return True
        if t == "object" and isinstance(value, dict):
            return True
        if t == "null" and value is None:
            return True
    return False


def _minimal_validate(schema: dict, meta: dict) -> list[str]:
    errors = []
    for field in schema.get("required", []):
        if field not in meta:
            errors.append(f"{field}: required field missing")
    for field, rule in (schema.get("properties") or {}).items():
        if field not in meta or not isinstance(rule, dict):
            continue
        value = meta[field]
        if "const" in rule and value != rule["const"]:
            errors.append(f"{field}: must be {rule['const']!r}")
        if "enum" in rule and value not in rule["enum"]:
            errors.append(f"{field}: {value!r} not in {rule['enum']!r}")
        if "type" in rule and not _type_ok(value, rule["type"]):
            errors.append(f"{field}: wrong type {type(value).__name__}")
    return errors
