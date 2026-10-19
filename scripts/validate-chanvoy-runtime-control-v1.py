#!/usr/bin/env python3
"""Check explicit local roots and fixtures, not native lifecycle or Rust parsing."""

from __future__ import annotations

import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator, SchemaError

ROOTS = (
    "runtime_rpc_error_response",
    "retirement_no_ack_report",
    "retire_rpc_request",
    "retire_rpc_response",
    "observation_rpc_request",
    "observation_rpc_response",
    "runtime_bootstrap",
    "runtime_readiness",
    "cli_lifecycle_report",
)
FAMILY = Path("schemas/ipc/local")
FIXTURES = FAMILY / "fixtures/chanvoy-runtime-control-v1"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_constant(value: str) -> None:
    raise ValueError(f"non-JSON number: {value}")


def load(path: Path):
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=unique_object,
        parse_constant=reject_constant,
    )


def validate(repo: Path) -> None:
    family = load(repo / FAMILY / "chanvoy-runtime-control-v1.schema.json")
    Draft202012Validator.check_schema(family)
    # A positive meta-validation alone must not qualify a permissive validator.
    try:
        Draft202012Validator.check_schema({"allOf": []})
    except SchemaError:
        pass
    else:
        raise ValueError("meta-validator accepted invalid empty allOf")

    roots = load(repo / FAMILY / "chanvoy-runtime-control-v1.roots.json")
    require(roots["roots"] == list(ROOTS), "selected-root inventory changed")
    validators = {}
    for name in ROOTS:
        schema = load(repo / FAMILY / f"{name}.selected.schema.json")
        Draft202012Validator.check_schema(schema)
        require(schema["$schema"] == family["$schema"], f"dialect drift: {name}")
        require(schema["$defs"] == family["$defs"], f"definition drift: {name}")
        require(schema["$ref"] == f"#/$defs/{name}", f"wrong root: {name}")
        validators[name] = Draft202012Validator(schema)

    cases = load(repo / FIXTURES / "manifest.json")
    require(isinstance(cases, list) and len(cases) == 100, "expected 100 fixture cases")
    seen = set()
    data_files = set()
    coverage = {name: set() for name in ROOTS}
    for case in cases:
        name = case["root"]
        require(name in validators, f"unknown fixture root: {name}")
        identity = (name, case["case"])
        require(identity not in seen, f"duplicate fixture case: {identity}")
        seen.add(identity)
        expected_schema = (FAMILY / f"{name}.selected.schema.json").as_posix()
        require(case["schema"] == expected_schema, f"wrong schema path: {identity}")
        data = Path(case["data"])
        require(
            data.parent == FIXTURES
            and data.suffix == ".json"
            and data.name != "manifest.json",
            f"invalid fixture path: {identity}",
        )
        require(data not in data_files, f"repeated fixture file: {data}")
        data_files.add(data)
        expected = case["expected_valid"]
        require(type(expected) is bool, f"non-boolean expectation: {identity}")
        coverage[name].add(expected)
        actual = validators[name].is_valid(load(repo / data))
        require(actual == expected, f"fixture validity mismatch: {identity}")
    for name, outcomes in coverage.items():
        require(
            outcomes == {True, False}, f"missing positive/negative coverage: {name}"
        )
    actual_files = {
        path.relative_to(repo)
        for path in (repo / FIXTURES).glob("*.json")
        if path.name != "manifest.json"
    }
    require(
        data_files == actual_files,
        "fixture manifest does not cover exact file inventory",
    )


def main() -> int:
    try:
        validate(Path(__file__).resolve().parent.parent)
    except (ValueError, KeyError, TypeError, OSError, SchemaError) as error:
        print(f"FAIL runtime-control v1: {error}", file=sys.stderr)
        return 1
    print(
        "[ok] runtime-control v1: 10 schemas, 9 selected roots, 100 fixtures; meta negative control"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
