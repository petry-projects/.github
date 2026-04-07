#!/usr/bin/env python3
"""Validate a signals.json file against signals.schema.json.

Usage:
    validate-signals.py <signals.json> [<schema.json>]

Exit codes:
    0  valid
    1  invalid (validation error printed to stderr)
    2  usage / file error
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.stderr.write(
        "[validate-signals] python jsonschema not installed. "
        "Install with: pip install jsonschema\n"
    )
    sys.exit(2)


def main(argv: list[str]) -> int:
    if len(argv) < 2 or len(argv) > 3:
        sys.stderr.write(
            "usage: validate-signals.py <signals.json> [<schema.json>]\n"
        )
        return 2

    signals_path = Path(argv[1])
    if len(argv) == 3:
        schema_path = Path(argv[2])
    else:
        schema_path = (
            Path(__file__).resolve().parent.parent.parent
            / "schemas"
            / "signals.schema.json"
        )

    if not signals_path.exists():
        sys.stderr.write(f"[validate-signals] not found: {signals_path}\n")
        return 2
    if not schema_path.exists():
        sys.stderr.write(f"[validate-signals] schema not found: {schema_path}\n")
        return 2

    try:
        signals = json.loads(signals_path.read_text())
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"[validate-signals] invalid JSON in {signals_path}: {exc}\n")
        return 1

    try:
        schema = json.loads(schema_path.read_text())
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"[validate-signals] invalid schema JSON: {exc}\n")
        return 2

    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(signals), key=lambda e: list(e.absolute_path))
    if not errors:
        print(f"[validate-signals] OK: {signals_path}")
        return 0

    sys.stderr.write(f"[validate-signals] {len(errors)} validation error(s) in {signals_path}:\n")
    for err in errors:
        path = "/".join(str(p) for p in err.absolute_path) or "<root>"
        sys.stderr.write(f"  - {path}: {err.message}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
