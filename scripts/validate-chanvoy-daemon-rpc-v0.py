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
    "wait_dm_v1",
    "wait_dm_follow_v1",
    "wait_inbox_v1",
    "wait_inbox_follow_v1",
)
FOLLOW_METHOD = "wait_follow_v1"
INBOX_FOLLOW_METHOD = "wait_inbox_follow_v1"
POST_ID_RE = __import__("re").compile(r"^[a-z0-9]{26}$")


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


def inbox_event_violations(instance: dict) -> list[str]:
    """Cross-value inbox follow invariants JSON Schema cannot express."""
    violations: list[str] = []
    mode = instance.get("mode")
    if mode in {"backlog", "live"}:
        messages = instance.get("messages") or []
        matched = instance.get("matched_post_id")
        cursor = instance.get("next_inbox_cursor")
        if messages and matched != messages[0].get("id"):
            violations.append("matched_post_id must equal the sole message id")
        if isinstance(cursor, str) and POST_ID_RE.match(cursor):
            violations.append("next_inbox_cursor must not be a Mattermost post id")
        if cursor == matched:
            violations.append("next_inbox_cursor must be distinct from matched_post_id")
        if "tip" in instance:
            violations.append("inbox events must not carry wait_follow_v1 tip")
    if mode in {"deadman", "canceled", "replaced", "failed"}:
        cursor = instance.get("inbox_cursor")
        if isinstance(cursor, str) and POST_ID_RE.match(cursor):
            violations.append("inbox_cursor must not be a Mattermost post id")
    return violations


def inbox_result_violations(instance: dict) -> list[str]:
    violations: list[str] = []
    messages = instance.get("messages") or []
    matched = instance.get("matched_post_id")
    cursor = instance.get("next_inbox_cursor")
    if messages and matched and matched != messages[0].get("id"):
        violations.append("matched_post_id must equal the sole message id")
    if isinstance(cursor, str) and POST_ID_RE.match(cursor):
        violations.append("next_inbox_cursor must not be a Mattermost post id")
    if cursor and matched and cursor == matched:
        violations.append("next_inbox_cursor must be distinct from matched_post_id")
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
            elif (
                name == "result"
                and method == "wait_inbox_v1"
                and (violations := inbox_result_violations(instance))
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
                else inbox_result_violations(instance)
                if method == "wait_inbox_v1" and name == "result"
                else []
            )
            if errors or violations:
                ok(f"{label} negative {fixture.name}")
            else:
                fail(f"{label} negative {fixture.name}: expected rejection, got pass")

for follow_kind in ("params", "event", "result", "error"):
    follow_label = f"{FOLLOW_METHOD}.{follow_kind}"
    follow_schema_path = FAMILY / f"{follow_label}.schema.json"
    follow_schema = load(follow_schema_path)
    try:
        Draft202012Validator.check_schema(follow_schema)
    except Exception as error:  # noqa: BLE001
        fail(f"lint {follow_schema_path.name}: {error}")
    else:
        if follow_schema.get("$id", "").rsplit("/", 1)[-1] != follow_schema_path.name:
            fail(f"lint {follow_schema_path.name}: $id basename mismatch")
            continue
        ok(f"lint {follow_schema_path.name}")
        follow_validator = Draft202012Validator(follow_schema)
        follow_root = FIXTURES / FOLLOW_METHOD / follow_kind
        conforming = sorted((follow_root / "conforming").glob("*.json"))
        negative = sorted((follow_root / "negative").glob("*.json"))
        if not conforming or not negative:
            fail(f"{follow_label}: fixture set is empty")
        for fixture in conforming:
            instance = load(fixture)
            errors = list(follow_validator.iter_errors(instance))
            tip_mismatch = (
                follow_kind == "event"
                and instance.get("mode") in {"backlog", "live"}
                and instance.get("messages")
                and instance.get("tip") != instance["messages"][-1].get("id")
            )
            if errors:
                fail(f"{follow_label} conforming {fixture.name}: {errors[0].message}")
            elif tip_mismatch:
                fail(
                    f"{follow_label} conforming {fixture.name}: "
                    "tip must equal final message id"
                )
            else:
                ok(f"{follow_label} conforming {fixture.name}")

        for fixture in negative:
            instance = load(fixture)
            errors = list(follow_validator.iter_errors(instance))
            tip_mismatch = (
                follow_kind == "event"
                and instance.get("mode") in {"backlog", "live"}
                and instance.get("messages")
                and instance.get("tip") != instance["messages"][-1].get("id")
            )
            if errors or tip_mismatch:
                ok(f"{follow_label} negative {fixture.name}")
            else:
                fail(
                    f"{follow_label} negative {fixture.name}: "
                    "expected rejection, got pass"
                )

inbox_event_label = f"{INBOX_FOLLOW_METHOD}.event"
inbox_event_schema_path = FAMILY / f"{inbox_event_label}.schema.json"
inbox_event_schema = load(inbox_event_schema_path)
try:
    Draft202012Validator.check_schema(inbox_event_schema)
except Exception as error:  # noqa: BLE001
    fail(f"lint {inbox_event_schema_path.name}: {error}")
else:
    if inbox_event_schema.get("$id", "").rsplit("/", 1)[-1] != inbox_event_schema_path.name:
        fail(f"lint {inbox_event_schema_path.name}: $id basename mismatch")
    else:
        ok(f"lint {inbox_event_schema_path.name}")
        inbox_event_validator = Draft202012Validator(inbox_event_schema)
        inbox_event_root = FIXTURES / INBOX_FOLLOW_METHOD / "event"
        conforming = sorted((inbox_event_root / "conforming").glob("*.json"))
        negative = sorted((inbox_event_root / "negative").glob("*.json"))
        if not conforming or not negative:
            fail(f"{inbox_event_label}: fixture set is empty")
        for fixture in conforming:
            instance = load(fixture)
            errors = list(inbox_event_validator.iter_errors(instance))
            semantic = inbox_event_violations(instance)
            if errors:
                fail(
                    f"{inbox_event_label} conforming {fixture.name}: "
                    f"{errors[0].message}"
                )
            elif semantic:
                fail(f"{inbox_event_label} conforming {fixture.name}: {semantic[0]}")
            else:
                ok(f"{inbox_event_label} conforming {fixture.name}")
        for fixture in negative:
            instance = load(fixture)
            errors = list(inbox_event_validator.iter_errors(instance))
            semantic = inbox_event_violations(instance)
            if errors or semantic:
                ok(f"{inbox_event_label} negative {fixture.name}")
            else:
                fail(
                    f"{inbox_event_label} negative {fixture.name}: "
                    "expected rejection, got pass"
                )

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)

print("\nChanvoy daemon RPC v0 schemas and fixtures: OK")
