#!/usr/bin/env python3
"""Validate the Chanvoy daemon RPC v0 contract family.

The gate checks every schema as JSON Schema 2020-12, requires non-empty
conforming and negative fixture sets, accepts every conforming fixture, and
rejects every negative fixture. It also checks the cross-value relations which
JSON Schema cannot express. No network access is performed.
"""

from __future__ import annotations

import json
import pathlib
import sys

try:
    from jsonschema import Draft202012Validator
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "error: the 'jsonschema' package is required "
        "(try: uv run --with jsonschema "
        "scripts/validate-chanvoy-daemon-rpc-v0.py)\n"
    )
    sys.exit(1)

REPO = pathlib.Path(__file__).resolve().parent.parent
FAMILY = REPO / "schemas/common/chanvoy-daemon-rpc/v0"
FIXTURES = FAMILY / "fixtures"
SCHEMAS = {
    "params": FAMILY / "wait_channels_v1.params.schema.json",
    "result": FAMILY / "wait_channels_v1.result.schema.json",
    "error": FAMILY / "wait_channels_v1.error.schema.json",
}

failures: list[str] = []


def load(path: pathlib.Path):
    return json.loads(path.read_text())


def fail(message: str) -> None:
    failures.append(message)
    print(f"FAIL {message}")


def ok(message: str) -> None:
    print(f"ok   {message}")


def semantic_violations(name: str, instance: dict) -> list[str]:
    """Return violations of normative cross-value method invariants."""
    violations: list[str] = []
    if name == "params":
        selectors = [
            (arm.get("team"), arm.get("channel"))
            for arm in instance.get("arms", [])
            if isinstance(arm, dict)
        ]
        if len(selectors) != len(set(selectors)):
            violations.append("duplicate requested team/channel selector")
    elif name == "result":
        channels = instance.get("channels", [])
        matched = instance.get("matched_channel")
        if isinstance(channels, list) and isinstance(matched, dict):
            if sum(channel == matched for channel in channels) != 1:
                violations.append("matched_channel must equal exactly one channels entry")
    return violations


for name, schema_path in SCHEMAS.items():
    schema = load(schema_path)
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as error:  # noqa: BLE001
        fail(f"lint {schema_path.name}: {error}")
        continue

    if schema.get("$id", "").rsplit("/", 1)[-1] != schema_path.name:
        fail(f"lint {schema_path.name}: $id basename mismatch")
        continue

    validator = Draft202012Validator(schema)
    conforming = sorted((FIXTURES / name / "conforming").glob("*.json"))
    negative = sorted((FIXTURES / name / "negative").glob("*.json"))
    if not conforming or not negative:
        fail(f"{name}: fixture set is empty")
        continue

    ok(f"lint {schema_path.name}")
    for fixture in conforming:
        instance = load(fixture)
        errors = list(validator.iter_errors(instance))
        if errors:
            fail(f"{name} conforming {fixture.name}: {errors[0].message}")
        elif violations := semantic_violations(name, instance):
            fail(f"{name} conforming {fixture.name}: {violations[0]}")
        else:
            ok(f"{name} conforming {fixture.name}")

    for fixture in negative:
        instance = load(fixture)
        errors = list(validator.iter_errors(instance))
        violations = semantic_violations(name, instance)
        if errors or violations:
            ok(f"{name} negative {fixture.name}")
        else:
            fail(f"{name} negative {fixture.name}: expected rejection, got pass")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)

print("\nChanvoy daemon RPC v0 schemas and fixtures: OK")
