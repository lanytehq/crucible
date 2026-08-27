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
METHODS = (
    "wait_channels_v1",
    "wait_channel_v3",
)
FOLLOW_EVENT = "wait_follow_v1.event"


def schema_paths(method: str) -> dict[str, pathlib.Path]:
    return {
        "params": FAMILY / f"{method}.params.schema.json",
        "result": FAMILY / f"{method}.result.schema.json",
        "error": FAMILY / f"{method}.error.schema.json",
    }


def fixture_root(method: str, kind: str) -> pathlib.Path:
    if method == "wait_channels_v1":
        return FIXTURES / kind
    return FIXTURES / method / kind


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
                violations.append(
                    "matched_channel must equal exactly one channels entry"
                )
    return violations


for method in METHODS:
    for name, schema_path in schema_paths(method).items():
        schema = load(schema_path)
        label = f"{method} {name}"
        try:
            Draft202012Validator.check_schema(schema)
        except Exception as error:  # noqa: BLE001
            fail(f"lint {schema_path.name}: {error}")
            continue

        if schema.get("$id", "").rsplit("/", 1)[-1] != schema_path.name:
            fail(f"lint {schema_path.name}: $id basename mismatch")
            continue

        validator = Draft202012Validator(schema)
        conforming = sorted((fixture_root(method, name) / "conforming").glob("*.json"))
        negative = sorted((fixture_root(method, name) / "negative").glob("*.json"))
        if not conforming or not negative:
            fail(f"{label}: fixture set is empty")
            continue

        ok(f"lint {schema_path.name}")
        for fixture in conforming:
            instance = load(fixture)
            errors = list(validator.iter_errors(instance))
            if errors:
                fail(f"{label} conforming {fixture.name}: {errors[0].message}")
            elif (
                name == "params"
                and method == "wait_channels_v1"
                and (violations := semantic_violations(name, instance))
            ):
                fail(f"{label} conforming {fixture.name}: {violations[0]}")
            elif (
                name == "result"
                and method == "wait_channels_v1"
                and (violations := semantic_violations(name, instance))
            ):
                fail(f"{label} conforming {fixture.name}: {violations[0]}")
            else:
                ok(f"{label} conforming {fixture.name}")

        for fixture in negative:
            instance = load(fixture)
            errors = list(validator.iter_errors(instance))
            violations = (
                semantic_violations(name, instance)
                if method == "wait_channels_v1"
                else []
            )
            if errors or violations:
                ok(f"{label} negative {fixture.name}")
            else:
                fail(f"{label} negative {fixture.name}: expected rejection, got pass")

follow_schema_path = FAMILY / f"{FOLLOW_EVENT}.schema.json"
follow_schema = load(follow_schema_path)
try:
    Draft202012Validator.check_schema(follow_schema)
except Exception as error:  # noqa: BLE001
    fail(f"lint {follow_schema_path.name}: {error}")
else:
    if follow_schema.get("$id", "").rsplit("/", 1)[-1] != follow_schema_path.name:
        fail(f"lint {follow_schema_path.name}: $id basename mismatch")
    else:
        ok(f"lint {follow_schema_path.name}")
        follow_validator = Draft202012Validator(follow_schema)
        follow_root = FIXTURES / "wait_follow_v1" / "event"
        conforming = sorted((follow_root / "conforming").glob("*.json"))
        negative = sorted((follow_root / "negative").glob("*.json"))
        if not conforming or not negative:
            fail(f"{FOLLOW_EVENT}: fixture set is empty")
        for fixture in conforming:
            instance = load(fixture)
            errors = list(follow_validator.iter_errors(instance))
            tip_mismatch = (
                instance.get("mode") in {"backlog", "live"}
                and instance.get("messages")
                and instance.get("tip") != instance["messages"][-1].get("id")
            )
            if errors:
                fail(f"{FOLLOW_EVENT} conforming {fixture.name}: {errors[0].message}")
            elif tip_mismatch:
                fail(
                    f"{FOLLOW_EVENT} conforming {fixture.name}: "
                    "tip must equal final message id"
                )
            else:
                ok(f"{FOLLOW_EVENT} conforming {fixture.name}")

        for fixture in negative:
            instance = load(fixture)
            errors = list(follow_validator.iter_errors(instance))
            tip_mismatch = (
                instance.get("mode") in {"backlog", "live"}
                and instance.get("messages")
                and instance.get("tip") != instance["messages"][-1].get("id")
            )
            if errors or tip_mismatch:
                ok(f"{FOLLOW_EVENT} negative {fixture.name}")
            else:
                fail(
                    f"{FOLLOW_EVENT} negative {fixture.name}: "
                    "expected rejection, got pass"
                )

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)

print("\nChanvoy daemon RPC v0 schemas and fixtures: OK")
