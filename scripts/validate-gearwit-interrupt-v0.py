#!/usr/bin/env python3
"""Validate the Gearwit interrupt v0 contract family."""

from __future__ import annotations

import datetime
import json
import pathlib
import sys

try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "error: the 'jsonschema' package is required "
        "(try: uv run --with jsonschema "
        "scripts/validate-gearwit-interrupt-v0.py)\n"
    )
    sys.exit(1)

REPO = pathlib.Path(__file__).resolve().parent.parent
FAMILY = REPO / "schemas/agentic/gearwit/v0"
FIXTURES = FAMILY / "fixtures"
ARTIFACTS = {
    "arm-request": FAMILY / "arm-request.schema.json",
    "arm-record": FAMILY / "arm-record.schema.json",
    "ring-request": FAMILY / "ring-request.schema.json",
    "waiter-link": FAMILY / "waiter-link.schema.json",
    "handled-cursor": FAMILY / "handled-cursor.schema.json",
    "lifecycle-receipt": FAMILY / "lifecycle-receipt.schema.json",
}

SOURCE_PHASES = {
    "control_plane": {
        "wait_armed",
        "signal_matched",
        "waiter_completed",
        "events_drained",
        "delivery_attempted",
        "handled_cursor_recorded",
        "coverage_rearmed",
        "coverage_ended",
    },
    "provider": {"signal_matched", "events_drained"},
    "waiter_process": {
        "wait_armed",
        "waiter_completed",
        "coverage_rearmed",
        "coverage_ended",
    },
    "harness": {"turn_started", "model_observed"},
    "controller": {"turn_started", "model_observed"},
    "seat": {
        "model_observed",
        "seat_acted",
        "handled_cursor_recorded",
        "coverage_rearmed",
    },
    "operator": {"seat_acted"},
}

failures: list[str] = []


def load(path: pathlib.Path):
    return json.loads(path.read_text())


def fail(message: str) -> None:
    failures.append(message)
    print(f"FAIL {message}")


def ok(message: str) -> None:
    print(f"ok   {message}")


def parse_datetime(value: str) -> datetime.datetime:
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


def semantic_violations(artifact: str, instance: dict) -> list[str]:
    violations: list[str] = []
    if artifact == "arm-request":
        if instance.get("deadman_secs", 0) > instance.get("coverage_secs", 0):
            violations.append("deadman_secs exceeds coverage_secs")
    elif artifact == "arm-record":
        try:
            armed_at = parse_datetime(instance["armed_at"])
            coverage_until = parse_datetime(instance["coverage_until"])
            if coverage_until <= armed_at:
                violations.append("coverage_until must be later than armed_at")
        except (KeyError, TypeError, ValueError):
            pass
    elif artifact == "lifecycle-receipt":
        fact = instance.get("fact")
        if not isinstance(fact, dict):
            return violations
        phase = fact.get("phase")
        source = instance.get("source")
        if phase not in SOURCE_PHASES.get(source, set()):
            violations.append(f"{source} cannot evidence {phase}")

        signal_present = "signal_id" in instance
        signal_required = phase in {
            "signal_matched",
            "delivery_attempted",
            "turn_started",
            "model_observed",
            "seat_acted",
            "events_drained",
            "handled_cursor_recorded",
        } or (
            phase == "waiter_completed" and fact.get("outcome") == "matched"
        )
        if signal_required and not signal_present:
            violations.append(f"{phase} requires signal_id")
        if not signal_required and signal_present:
            violations.append(f"{phase} must omit signal_id")
    elif artifact == "waiter-link":
        message_type = instance.get("type")
        if message_type == "attach_accepted":
            try:
                accepted_at = parse_datetime(instance["accepted_at"])
                lease_until = parse_datetime(instance["lease_until"])
                if lease_until <= accepted_at:
                    violations.append("lease_until must be later than accepted_at")
            except (KeyError, TypeError, ValueError):
                pass
        elif message_type == "deliver_events":
            events = instance.get("events")
            if isinstance(events, list) and events:
                event_refs = [
                    event.get("event_ref")
                    for event in events
                    if isinstance(event, dict)
                ]
                if len(event_refs) == len(events) and all(
                    isinstance(event_ref, str) for event_ref in event_refs
                ):
                    if len(event_refs) != len(set(event_refs)):
                        violations.append(
                            "delivery event_ref values must be unique"
                        )
                    if event_refs[-1] != instance.get("newest_event_ref"):
                        violations.append(
                            "newest_event_ref must match the final delivery event"
                        )
    return violations


for artifact, schema_path in ARTIFACTS.items():
    schema = load(schema_path)
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as error:  # noqa: BLE001
        fail(f"lint {schema_path.name}: {error}")
        continue

    if schema.get("$id", "").rsplit("/", 1)[-1] != schema_path.name:
        fail(f"lint {schema_path.name}: $id basename mismatch")
        continue

    ok(f"lint {schema_path.name}")
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    for disposition in ("conforming", "negative"):
        fixtures = sorted((FIXTURES / artifact / disposition).glob("*.json"))
        if not fixtures:
            fail(f"{artifact} {disposition}: fixture set is empty")
            continue
        for fixture in fixtures:
            instance = load(fixture)
            errors = list(validator.iter_errors(instance))
            violations = semantic_violations(artifact, instance)
            if disposition == "conforming":
                if errors:
                    fail(
                        f"{artifact} conforming {fixture.name}: "
                        f"{errors[0].message}"
                    )
                elif violations:
                    fail(
                        f"{artifact} conforming {fixture.name}: "
                        f"{violations[0]}"
                    )
                else:
                    ok(f"{artifact} conforming {fixture.name}")
            elif errors or violations:
                ok(f"{artifact} negative {fixture.name}")
            else:
                fail(
                    f"{artifact} negative {fixture.name}: "
                    "expected rejection, got pass"
                )

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)

print("\nGearwit interrupt v0 schemas and fixtures: OK")
