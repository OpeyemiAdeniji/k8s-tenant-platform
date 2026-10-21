#!/usr/bin/env python3
"""Validate tenant files against the tenant contract.

Usage: python3 scripts/validate_tenants.py FILE [FILE ...]

Each file is checked in three steps:
1. It is valid YAML and holds one mapping at the top level.
2. It matches schemas/tenant.schema.json.
3. The name inside the file equals the file name without .yaml.

Exit code 0 means every file passed. Exit code 1 means at least one file failed.
"""

import json
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schemas" / "tenant.schema.json"


def location(error):
    parts = [str(part) for part in error.absolute_path]
    return ".".join(parts) if parts else "(top level)"


def check_file(validator, path):
    """Return a list of problems found in one file. An empty list means it passed."""
    try:
        data = yaml.safe_load(path.read_text())
    except OSError as exc:
        return [f"cannot read the file: {exc}"]
    except yaml.YAMLError as exc:
        return [f"not valid YAML: {exc}"]

    if not isinstance(data, dict):
        return ["the file must contain one YAML mapping at the top level"]

    errors = sorted(validator.iter_errors(data), key=location)
    problems = [f"{location(error)}: {error.message}" for error in errors]

    name = data.get("name")
    if isinstance(name, str) and name != path.stem:
        problems.append(f"name: '{name}' must match the file name '{path.stem}'")

    return problems


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2

    schema = json.loads(SCHEMA_PATH.read_text())
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)

    failed = 0
    for arg in argv[1:]:
        path = Path(arg)
        problems = check_file(validator, path)
        if problems:
            failed += 1
            print(f"FAIL {path}")
            for problem in problems:
                print(f"  - {problem}")
        else:
            print(f"ok   {path}")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
