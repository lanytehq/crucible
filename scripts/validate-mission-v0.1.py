#!/usr/bin/env python3
"""Fail-closed validator for the agentic/mission v0.1 contract family.

The family deliberately has two validation layers:

* Draft 2020-12 validates each on-disk contract and its positive/negative
  fixtures.  The registry contains all family schemas so relative inter-schema
  references resolve exactly as they will for consumers.
* ``semantic-validation.md`` is represented by versioned history fixtures.
  It checks relations which cannot be expressed by JSON Schema alone.

No network access is performed.  Run directly with ``jsonschema`` installed,
or through the repository's ``make check-mission-v0.1`` target.
"""

from __future__ import annotations

import json
import pathlib
import sys
import uuid
from collections.abc import Iterable, Mapping
from datetime import datetime
from typing import Any

try:
    from jsonschema import Draft202012Validator
    from referencing import Registry, Resource
    from referencing.jsonschema import DRAFT202012
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "error: the 'jsonschema' package is required "
        "(try: uv run --with jsonschema scripts/validate-mission-v0.1.py)\n"
    )
    sys.exit(1)


REPO = pathlib.Path(__file__).resolve().parent.parent
FAMILY = REPO / "schemas/agentic/mission/v0.1"
FIXTURES = FAMILY / "fixtures"

SCHEMA_NAMES = (
    "mission-record",
    "mission-control",
    "driver-capabilities",
    "lifecycle-event",
)
SCHEMA_BASE_URI = "https://schemas.3leaps.dev/agentic/mission/v0.1/"

SEMANTIC_LAYER_ID = "mission/v0.1-semantics"
SEMANTIC_LAYER_VERSION = "0.2.1"

TERMINAL_MISSION_PHASES = {
    "completed",
    "cancelled",
    "failed",
    "deadline_exceeded",
    "budget_exhausted",
}
TERMINAL_REASON_BY_PHASE = {
    "completed": {"goal_satisfied"},
    "cancelled": {"operator_cancelled"},
    "deadline_exceeded": {"mission_deadline_exceeded"},
    "budget_exhausted": {"budget_exhausted"},
    "failed": {
        "policy_denied",
        "restore_exhausted",
        "required_driver_capability_unavailable",
        "internal_error",
    },
}
LIVE_ATTEMPT_STATES = {"starting", "running", "waiting", "unresponsive", "cancelling"}
MISSION_TRANSITIONS = {
    "created": {"active", "suspended", "cancelled", "failed"},
    "active": {
        "waiting",
        "recovery_pending",
        "suspended",
        "cancelled",
        "completed",
        "failed",
        "deadline_exceeded",
        "budget_exhausted",
    },
    "waiting": {
        "active",
        "recovery_pending",
        "suspended",
        "cancelled",
        "failed",
        "deadline_exceeded",
        "budget_exhausted",
    },
    "recovery_pending": {
        "active",
        "suspended",
        "cancelled",
        "failed",
        "deadline_exceeded",
        "budget_exhausted",
    },
    "suspended": {
        "active",
        "cancelled",
        "failed",
        "deadline_exceeded",
        "budget_exhausted",
    },
}
ATTEMPT_TRANSITIONS = {
    "starting": {"running", "cancelling", "failed", "crashed", "timed_out", "lost"},
    "running": {
        "waiting",
        "unresponsive",
        "cancelling",
        "completed",
        "failed",
        "crashed",
        "timed_out",
        "lost",
    },
    "waiting": {
        "running",
        "unresponsive",
        "cancelling",
        "completed",
        "failed",
        "crashed",
        "timed_out",
        "lost",
    },
    "unresponsive": {
        "running",
        "cancelling",
        "replaced",
        "failed",
        "crashed",
        "timed_out",
        "lost",
    },
    "cancelling": {"cancelled", "failed", "crashed", "timed_out", "lost"},
}
UUID_FIELDS = {
    "mission_id",
    "attempt_id",
    "event_id",
    "report_id",
    "request_id",
    "evidence_chain_id",
    "causation_id",
    "correlation_id",
    "predecessor_attempt_id",
    "current_attempt_id",
    "replaced_attempt_id",
}
TIMESTAMP_FIELDS = {
    "created_at",
    "updated_at",
    "deadline_at",
    "started_at",
    "ended_at",
    "occurred_at",
    "observed_at",
    "recorded_at",
    "expires_at",
    "evidence_at",
    "restored_at",
    "lease_expires_at",
    "deadman_at",
    "last_observed_at",
    "ownership_established_at",
}
FORBIDDEN_FIELD_NAMES = {
    "access_token",
    "api_key",
    "attestation_token",
    "credential",
    "credentials",
    "chain_of_thought",
    "cot",
    "password",
    "passphrase",
    "private_key",
    "raw_attestation_token",
    "raw_token",
    "refresh_token",
    "secret",
    "secrets",
    "session_token",
    "token_secret",
}

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)
    print(f"FAIL {message}")


def ok(message: str) -> None:
    print(f"ok   {message}")


def load(path: pathlib.Path) -> Any:
    return json.loads(path.read_text())


def error_leaves(errors: Iterable[Any]) -> Iterable[Any]:
    for error in errors:
        if error.context:
            yield from error_leaves(error.context)
        else:
            yield error


def is_canonical_uuid(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        return str(uuid.UUID(value)) == value
    except ValueError:
        return False


def parse_instant(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        instant = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return instant if instant.tzinfo is not None else None


def mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def field(mapping_value: Mapping[str, Any], *names: str) -> Any:
    for name in names:
        if name in mapping_value:
            return mapping_value[name]
    return None


def has_field(mapping_value: Mapping[str, Any], *names: str) -> bool:
    return any(name in mapping_value for name in names)


# ---------------------------------------------------------------- 1. schemas
schemas: dict[str, dict[str, Any]] = {}
schema_paths: dict[str, pathlib.Path] = {}
for name in SCHEMA_NAMES:
    schema_path = FAMILY / f"{name}.schema.json"
    schema_paths[name] = schema_path
    if not schema_path.is_file():
        fail(f"lint {schema_path.name}: required family schema is missing")
        continue
    try:
        schema = load(schema_path)
    except (OSError, json.JSONDecodeError) as error:
        fail(f"lint {schema_path.name}: cannot load JSON: {error}")
        continue
    if not isinstance(schema, dict):
        fail(f"lint {schema_path.name}: root must be a JSON object")
        continue
    expected_id = f"{SCHEMA_BASE_URI}{schema_path.name}"
    if schema.get("$id") != expected_id:
        fail(f"lint {schema_path.name}: $id must equal {expected_id}")
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as error:  # noqa: BLE001
        fail(f"lint {schema_path.name}: {error}")
        continue
    schemas[name] = schema
    ok(f"lint {schema_path.name}")

actual_schema_names = {
    path.stem.removesuffix(".schema") for path in FAMILY.glob("*.schema.json")
}
expected_schema_names = set(SCHEMA_NAMES)
if actual_schema_names != expected_schema_names:
    fail(
        "lint mission family schema drift: "
        f"only-expected={sorted(expected_schema_names - actual_schema_names)} "
        f"only-on-disk={sorted(actual_schema_names - expected_schema_names)}"
    )

validators: dict[str, Draft202012Validator] = {}
if not failures:
    resources = (
        (
            schema["$id"],
            Resource.from_contents(schema, default_specification=DRAFT202012),
        )
        for schema in schemas.values()
    )
    registry = Registry().with_resources(resources)
    for name, schema in schemas.items():
        validators[name] = Draft202012Validator(schema, registry=registry)


# --------------------------------------------------------- 2. schema fixtures
def check_schema_fixtures(name: str) -> None:
    validator = validators.get(name)
    if validator is None:
        return
    conforming_dir = FIXTURES / name / "conforming"
    negative_dir = FIXTURES / name / "negative"
    expected_path = negative_dir / "expected.json"
    conforming = sorted(conforming_dir.glob("*.json"))
    negative = sorted(
        path for path in negative_dir.glob("*.json") if path.name != "expected.json"
    )
    if not conforming or not negative:
        fail(f"{name}: conforming and negative fixture sets must both be non-empty")
        return
    if not expected_path.is_file():
        fail(f"{name} negative: expected.json is required")
        return
    try:
        expected = load(expected_path)
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{name} negative: cannot load expected.json: {error}")
        return
    if not isinstance(expected, dict):
        fail(f"{name} negative: expected.json root must be an object")
        return

    for path in conforming:
        try:
            errors = sorted(
                validator.iter_errors(load(path)), key=lambda error: str(error.path)
            )
        except (OSError, json.JSONDecodeError) as error:
            fail(f"{name} conforming {path.name}: cannot load JSON: {error}")
            continue
        if errors:
            fail(f"{name} conforming {path.name}: {errors[0].message}")
        else:
            ok(f"{name} conforming {path.name}")

    for path in negative:
        expectation = expected.get(path.name)
        if not isinstance(expectation, dict):
            fail(f"{name} negative {path.name}: no expected-reason entry")
            continue
        keyword = expectation.get("keyword")
        mentions = expectation.get("mentions")
        if not isinstance(keyword, str) or not isinstance(mentions, str):
            fail(
                f"{name} negative {path.name}: expected reason needs string keyword and mentions"
            )
            continue
        try:
            errors = list(validator.iter_errors(load(path)))
        except (OSError, json.JSONDecodeError) as error:
            fail(f"{name} negative {path.name}: cannot load JSON: {error}")
            continue
        if not errors:
            fail(f"{name} negative {path.name}: expected rejection, got pass")
            continue
        if any(
            error.validator == keyword
            and (mentions in error.json_path or mentions in str(error.message))
            for error in error_leaves(errors)
        ):
            ok(f"{name} negative {path.name} (rejects: {keyword} @ {mentions})")
        else:
            received = "; ".join(
                f"{error.validator}@{error.json_path}" for error in error_leaves(errors)
            )
            fail(
                f"{name} negative {path.name}: rejected, but not for the stated reason "
                f"(want {keyword} @ {mentions}; got {received})"
            )

    fixture_names = {path.name for path in negative}
    if fixture_names != set(expected):
        fail(
            f"{name} negative expected.json drift: "
            f"only-in-expected={sorted(set(expected) - fixture_names)} "
            f"only-on-disk={sorted(fixture_names - set(expected))}"
        )


for schema_name in SCHEMA_NAMES:
    check_schema_fixtures(schema_name)


# ------------------------------------------------------ 3. semantic histories
def walk_object(value: Any, path: str = "$") -> Iterable[tuple[str, str, Any]]:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if isinstance(key, str):
                child_path = f"{path}.{key}"
                yield child_path, key, child
                yield from walk_object(child, child_path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk_object(child, f"{path}[{index}]")


def principal_fingerprint(value: Any) -> Any:
    if not isinstance(value, Mapping):
        return value
    return (
        value.get("kind"),
        value.get("subject"),
        value.get("role"),
        value.get("scope"),
        mapping(value.get("attestation")).get("issuer"),
        mapping(value.get("attestation")).get("session_id"),
        mapping(value.get("attestation")).get("jti"),
    )


def operating_role_fingerprint(value: Any) -> Any:
    if not isinstance(value, Mapping):
        return value
    return value.get("role"), value.get("scope")


def semantic_record(fixture: Mapping[str, Any]) -> Mapping[str, Any]:
    return mapping(field(fixture, "mission", "record", "mission_record"))


def semantic_events(fixture: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    events = field(fixture, "events", "lifecycle_events")
    return [mapping(event) for event in events] if isinstance(events, list) else []


def event_kind(event: Mapping[str, Any]) -> str:
    kind = field(event, "event_type", "kind", "event_kind", "type")
    return kind.lower().replace("_", ".") if isinstance(kind, str) else ""


def authorization_event(event: Mapping[str, Any]) -> bool:
    kind = event_kind(event)
    return (
        (
            "authoriz" in kind
            and any(word in kind for word in ("approved", "resolved", "granted"))
        )
        or kind == "authorization.bound"
        or ("approval" in kind and "resolved" in kind)
    )


def phase_change(event: Mapping[str, Any]) -> tuple[str | None, str | None]:
    payload = mapping(event.get("payload"))
    before = field(
        payload,
        "from",
        "previous_phase",
        "from_phase",
        "old_phase",
        "previous_state",
        "from_state",
    )
    after = field(
        payload, "to", "new_phase", "to_phase", "phase", "new_state", "to_state"
    )
    return (
        before if isinstance(before, str) else None,
        after if isinstance(after, str) else None,
    )


def is_attempt_event(event: Mapping[str, Any]) -> bool:
    return mapping(event.get("payload")).get(
        "attempt_id"
    ) is not None or "attempt" in event_kind(event)


def snapshots(
    fixture: Mapping[str, Any], event: Mapping[str, Any] | None = None
) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
    source = event if event is not None else fixture
    before = mapping(
        field(source, "before", "mission_before", "prior_mission", "previous_mission")
    )
    after = mapping(
        field(source, "after", "mission_after", "restored_mission", "new_mission")
    )
    if not before and not after:
        restore = mapping(source.get("restore"))
        before = mapping(field(restore, "before", "mission_before", "prior_mission"))
        after = mapping(field(restore, "after", "mission_after", "restored_mission"))
    return before, after


def capability_entries(report: Any) -> dict[str, Mapping[str, Any]]:
    report_map = mapping(report)
    operations = field(report_map, "operations", "capabilities")
    entries: dict[str, Mapping[str, Any]] = {}
    if isinstance(operations, Mapping):
        for operation, status in operations.items():
            if isinstance(operation, str):
                entries[operation] = mapping(status)
    elif isinstance(operations, list):
        for item in operations:
            item_map = mapping(item)
            operation = field(item_map, "operation", "name", "kind")
            if isinstance(operation, str):
                entries[operation] = item_map
    return entries


def required_operations(
    fixture: Mapping[str, Any], event: Mapping[str, Any]
) -> list[str]:
    required = field(event, "required_operations", "required_capabilities")
    if required is None:
        required = field(fixture, "required_operations", "required_capabilities")
    if isinstance(required, list):
        return [item for item in required if isinstance(item, str)]
    if isinstance(required, str):
        return [required]
    return []


def can_start(event: Mapping[str, Any]) -> bool:
    _, after = phase_change(event)
    kind = event_kind(event)
    return after in {"active", "running", "restored"} or any(
        word in kind for word in (".running", ".restored", ".resumed", ".relaunched")
    )


def semantic_violations(fixture: Any) -> list[str]:
    if not isinstance(fixture, Mapping):
        return ["SEM-FIXTURE"]
    if fixture.get("kind") not in {"mission-history", "mission_history"}:
        return ["SEM-FIXTURE"]

    violations: set[str] = set()
    allowed_fixture_fields = {
        "kind",
        "mission",
        "events",
        "driver_capabilities",
        "before",
        "after",
        "required_capabilities",
    }
    if set(fixture) - allowed_fixture_fields:
        violations.add("SEM-FIXTURE")
    mission = semantic_record(fixture)
    events = semantic_events(fixture)
    if not mission:
        return ["SEM-FIXTURE"]

    reports = fixture.get("driver_capabilities")
    reports = reports if isinstance(reports, list) else []
    mission_validator = validators.get("mission-record")
    event_validator = validators.get("lifecycle-event")
    capability_validator = validators.get("driver-capabilities")
    if (
        mission_validator is None
        or event_validator is None
        or capability_validator is None
        or list(mission_validator.iter_errors(mission))
        or any(list(event_validator.iter_errors(event)) for event in events)
        or any(list(capability_validator.iter_errors(report)) for report in reports)
    ):
        violations.add("SEM-FIXTURE")

    # Identity, chronology, and trust-surface rules.
    for path, name, value in walk_object(fixture):
        if (
            name in UUID_FIELDS
            and value is not None
            and (not is_canonical_uuid(value) or uuid.UUID(value).version != 4)
        ):
            violations.add("SEM-M01")
        if (
            name in TIMESTAMP_FIELDS
            and value is not None
            and parse_instant(value) is None
        ):
            violations.add("SEM-M02")
        normalized_name = name.lower().replace("-", "_")
        if normalized_name in FORBIDDEN_FIELD_NAMES:
            violations.add("SEM-A03")
    if parse_instant(mission.get("updated_at")) and parse_instant(
        mission.get("created_at")
    ):
        if parse_instant(mission["updated_at"]) < parse_instant(mission["created_at"]):
            violations.add("SEM-M02")
    if mission.get("evidence_chain_id") != mission.get("mission_id") or any(
        event.get("mission_id") != mission.get("mission_id") for event in events
    ):
        violations.add("SEM-M03")

    previous_hash = None
    previous_occurred_at: datetime | None = None
    for index, event in enumerate(events, start=1):
        if (
            event.get("sequence") != index
            or event.get("previous_entry_hash") != previous_hash
        ):
            violations.add("SEM-M04")
        previous_hash = event.get("entry_hash")
        payload = mapping(event.get("payload"))
        if event.get("event_type") != payload.get("type"):
            violations.add("SEM-M05")
        source = mapping(event.get("source"))
        if source.get("kind") in {
            "verified_attestation",
            "operator_command",
        } and not source.get("evidence_ref"):
            violations.add("SEM-A04")
        expected_assurance = {
            "kernel_observed": {"kernel_observed", "resource_attested"},
            "verified_attestation": {"resource_attested"},
            "driver_reported": {"claim", "driver_observed"},
            "harness_reported": {"claim"},
            "operator_command": {"resource_attested"},
        }
        if source.get("assurance") not in expected_assurance.get(
            source.get("kind"), set()
        ):
            violations.add("SEM-A04")
        occurred_at = parse_instant(event.get("occurred_at"))
        recorded_at = parse_instant(event.get("recorded_at"))
        if occurred_at is not None and (
            (previous_occurred_at is not None and occurred_at < previous_occurred_at)
            or (recorded_at is not None and recorded_at < occurred_at)
        ):
            violations.add("SEM-M02")
        if occurred_at is not None:
            previous_occurred_at = occurred_at
    if (
        mission.get("terminal_entry_hash") is not None
        and mission.get("terminal_entry_hash") != previous_hash
    ):
        violations.add("SEM-M05")

    if mission.get("phase") == "created" and mission.get("authorizer") is not None:
        violations.add("SEM-A01")
    if (mission.get("authorizer") is None) != (
        mission.get("authorization_ref") is None
    ):
        violations.add("SEM-A01")
    running_index = next(
        (
            index
            for index, event in enumerate(events)
            if is_attempt_event(event) and phase_change(event)[1] == "running"
        ),
        None,
    )
    authorization_index = next(
        (
            index
            for index, event in enumerate(events)
            if authorization_event(event)
            and mapping(event.get("source")).get("kind")
            in {"verified_attestation", "operator_command"}
        ),
        None,
    )
    if mission.get("authorizer") is not None and (
        not mission.get("authorization_ref")
        or authorization_index is None
        or (running_index is not None and authorization_index > running_index)
    ):
        violations.add("SEM-A01")

    # SEM-M03: a restore/relaunch preserves the durable mission identity and
    # operating role.  Fixtures may put the snapshots on the history, a
    # restore member, or the pertinent event.
    snapshot_pairs = [snapshots(fixture)]
    snapshot_pairs.extend(
        snapshots(fixture, event)
        for event in events
        if "restor" in event_kind(event) or "relaunch" in event_kind(event)
    )
    for before, after in snapshot_pairs:
        if before or after:
            if not before or not after:
                violations.add("SEM-A02")
            elif (
                before.get("mission_id") != after.get("mission_id")
                or principal_fingerprint(before.get("initiator"))
                != principal_fingerprint(after.get("initiator"))
                or principal_fingerprint(before.get("supervisor"))
                != principal_fingerprint(after.get("supervisor"))
                or operating_role_fingerprint(before.get("operating_role"))
                != operating_role_fingerprint(after.get("operating_role"))
            ):
                violations.add("SEM-A02")

    attempts = mission.get("attempts")
    attempts = attempts if isinstance(attempts, list) else []
    attempts_by_id = {
        attempt.get("attempt_id"): attempt
        for attempt in attempts
        if isinstance(attempt, Mapping) and isinstance(attempt.get("attempt_id"), str)
    }
    ordinals = []
    attempt_generations = []
    for attempt in attempts_by_id.values():
        ordinal = attempt.get("ordinal")
        if not isinstance(ordinal, int) or isinstance(ordinal, bool):
            violations.add("SEM-T06")
        else:
            ordinals.append(ordinal)
        generation = attempt.get("generation")
        if not isinstance(generation, int) or isinstance(generation, bool):
            violations.add("SEM-T08")
        else:
            attempt_generations.append(generation)
        relation = attempt.get("recovery_relation")
        started_at = parse_instant(attempt.get("started_at"))
        ended_at = parse_instant(attempt.get("ended_at"))
        if started_at is not None and ended_at is not None and ended_at < started_at:
            violations.add("SEM-M02")
        predecessor_id = field(attempt, "predecessor_attempt_id", "replaced_attempt_id")
        if relation == "initial" and predecessor_id is not None:
            violations.add("SEM-T06")
        if relation in {"resumes", "relaunches", "reconcile"}:
            predecessor = attempts_by_id.get(predecessor_id)
            if (
                predecessor is None
                or not isinstance(ordinal, int)
                or predecessor.get("ordinal", 0) >= ordinal
            ):
                violations.add("SEM-T06")
            if predecessor is None or predecessor.get("state") != "replaced":
                violations.add("SEM-T07")
    if sorted(ordinals) != list(range(1, len(ordinals) + 1)):
        violations.add("SEM-T06")
    if len(attempt_generations) != len(
        set(attempt_generations)
    ) or attempt_generations != sorted(attempt_generations):
        violations.add("SEM-T08")

    live_attempts = [
        attempt
        for attempt in attempts_by_id.values()
        if attempt.get("state") in LIVE_ATTEMPT_STATES
    ]
    if len(live_attempts) > 1:
        violations.add("SEM-T03")
    if mission.get("phase") in TERMINAL_MISSION_PHASES and live_attempts:
        violations.add("SEM-T05")
    if mission.get("phase") in TERMINAL_MISSION_PHASES and mission.get(
        "terminal_reason"
    ) not in TERMINAL_REASON_BY_PHASE.get(mission["phase"], set()):
        violations.add("SEM-T05")

    current_attempt_id = mission.get("current_attempt_id")
    if live_attempts:
        if len(live_attempts) == 1 and current_attempt_id != live_attempts[0].get(
            "attempt_id"
        ):
            violations.add("SEM-T04")
    elif current_attempt_id is not None:
        violations.add("SEM-T04")

    for event in events:
        payload = mapping(event.get("payload"))
        if payload.get("type") in {"mission_terminal", "mission_created"}:
            continue
        before, after = phase_change(event)
        if before is not None or after is not None:
            transitions = (
                ATTEMPT_TRANSITIONS if is_attempt_event(event) else MISSION_TRANSITIONS
            )
            if (
                before is None
                or after is None
                or after not in transitions.get(before, set())
            ):
                violations.add("SEM-T02" if is_attempt_event(event) else "SEM-T01")

    entries: dict[str, Mapping[str, Any]] = {}
    report_available = True
    for report in reports:
        report_map = mapping(report)
        observed_at = parse_instant(report_map.get("observed_at"))
        expires_at = parse_instant(report_map.get("expires_at"))
        validity = mapping(report_map.get("validity_condition"))
        live = mapping(field(report_map, "live_probe", "live_evidence"))
        if (
            observed_at is not None
            and expires_at is not None
            and expires_at <= observed_at
        ):
            violations.add("SEM-D02")
        evaluated_at = parse_instant(mission.get("updated_at"))
        if (
            expires_at is not None
            and evaluated_at is not None
            and expires_at <= evaluated_at
        ):
            violations.add("SEM-D02")
        if live and (
            live.get("version") != validity.get("executable_version")
            or live.get("platform") != validity.get("platform")
        ):
            violations.add("SEM-D02")
        if report_map.get("availability") != "available":
            report_available = False
        for capability, status in capability_entries(report_map).items():
            if capability in entries:
                violations.add("SEM-D01")
            entries[capability] = status
    for event in events:
        payload = mapping(event.get("payload"))
        required = required_operations(fixture, event)
        relation = payload.get("recovery_relation")
        if relation == "resumes":
            required = [*required, "resume"]
        elif relation == "relaunches":
            required = [*required, "identify", "cancel", "terminal_status"]
        if can_start(event) and required:
            for operation in required:
                status = entries.get(operation)
                fidelity = field(
                    mapping(status), "fidelity", "support_fidelity", "support"
                )
                if (
                    status is None
                    or not report_available
                    or fidelity not in {"native", "mapped"}
                ):
                    violations.add("SEM-D03")
                    if relation in {"resumes", "relaunches"}:
                        violations.add("SEM-D04")

    generations: list[int] = []
    for event in events:
        payload = mapping(event.get("payload"))
        generation = payload.get("generation")
        if generation is not None:
            if (
                not isinstance(generation, int)
                or isinstance(generation, bool)
            ):
                violations.add("SEM-T08")
            else:
                generations.append(generation)
    if generations != sorted(generations):
        violations.add("SEM-T08")

    # Wave 3: cancel proof, lease fences, and restart receipts.
    protocol_interrupted = False
    process_cleared = False
    cancel_requested_seen = False
    deadman_only_crash = False
    max_lease_gen: dict[str, int] = {}
    restart_keys: set[tuple[Any, Any]] = set()
    fence_kinds = {
        "cancel_requested",
        "protocol_cancel_attempted",
        "process_termination_attempted",
        "lease_tick",
        "restart_reconciled",
    }

    def protocol_matches(payload: Mapping[str, Any], attempt: Mapping[str, Any] | None) -> bool:
        return bool(
            attempt is not None
            and payload.get("attempt_id") == attempt.get("attempt_id")
            and payload.get("generation") == attempt.get("generation")
            and payload.get("lease_generation") == attempt.get("lease_generation")
            and payload.get("thread_id")
            and payload.get("turn_id")
            and payload.get("thread_id") == attempt.get("harness_thread_id")
            and payload.get("turn_id") == attempt.get("harness_turn_id")
        )

    for event in events:
        payload = mapping(event.get("payload"))
        kind = payload.get("type")
        source = mapping(event.get("source"))
        attempt = attempts_by_id.get(payload.get("attempt_id"))
        if kind == "cancel_requested":
            cancel_requested_seen = True
        if kind == "protocol_cancel_attempted":
            if payload.get("outcome") == "interrupted":
                if protocol_matches(payload, attempt):
                    protocol_interrupted = True
                else:
                    violations.add("SEM-C02")
            if source.get("kind") == "kernel_observed":
                violations.add("SEM-P01")
        if kind == "process_termination_attempted":
            if source.get("kind") != "kernel_observed":
                violations.add("SEM-P01")
            if (
                payload.get("outcome") == "cleared"
                and source.get("kind") == "kernel_observed"
                and attempt is not None
                and payload.get("generation") == attempt.get("generation")
                and payload.get("lease_generation") == attempt.get("lease_generation")
            ):
                process_cleared = True
        if kind == "restart_reconciled" and payload.get("overdue") is True:
            key = (payload.get("attempt_id"), payload.get("lease_generation"))
            if key in restart_keys:
                violations.add("SEM-L03")
            restart_keys.add(key)
        lease_gen = payload.get("lease_generation")
        attempt_id = payload.get("attempt_id")
        if (
            isinstance(attempt_id, str)
            and isinstance(lease_gen, int)
            and not isinstance(lease_gen, bool)
        ):
            previous = max_lease_gen.get(attempt_id)
            if previous is not None and lease_gen < previous:
                violations.add("SEM-L01")
            max_lease_gen[attempt_id] = (
                lease_gen if previous is None else max(previous, lease_gen)
            )
            if (
                kind in fence_kinds
                and attempt is not None
                and attempt.get("lease_generation") is not None
                and lease_gen != attempt.get("lease_generation")
            ):
                violations.add("SEM-L01")
        if kind == "lease_tick" and payload.get("kind") == "deadman_fired":
            deadman_only_crash = True

    if deadman_only_crash:
        for attempt in attempts_by_id.values():
            if attempt.get("state") in {"crashed", "timed_out", "lost"}:
                violations.add("SEM-C05")

    cancelled_attempts = [
        attempt
        for attempt in attempts_by_id.values()
        if attempt.get("state") == "cancelled"
    ]
    if cancelled_attempts and not protocol_interrupted and not process_cleared:
        violations.add("SEM-C01")
    if mission.get("phase") == "cancelled":
        no_attempt = not attempts_by_id
        if not (protocol_interrupted or process_cleared or (no_attempt and cancel_requested_seen)):
            violations.add("SEM-C02")
    if cancelled_attempts and not process_cleared and not protocol_interrupted:
        violations.add("SEM-C03")

    if mission.get("phase") in TERMINAL_MISSION_PHASES:
        if not events:
            violations.add("SEM-C06")
        else:
            last = events[-1]
            last_payload = mapping(last.get("payload"))
            if (
                last_payload.get("type") != "mission_terminal"
                or last_payload.get("phase") != mission.get("phase")
                or last_payload.get("reason") != mission.get("terminal_reason")
                or last_payload.get("terminal_entry_hash") != last.get("entry_hash")
            ):
                violations.add("SEM-C06")

    lease_policy = mapping(mission.get("lease_policy"))
    lease_enabled = lease_policy.get("enabled") is True
    for attempt in attempts_by_id.values():
        runtime = [
            attempt.get("lease_expires_at"),
            attempt.get("deadman_at"),
            attempt.get("lease_generation"),
        ]
        if not lease_enabled and any(value is not None for value in runtime):
            violations.add("SEM-L04")
        if lease_enabled and attempt.get("state") in LIVE_ATTEMPT_STATES:
            if any(value is None for value in runtime) or attempt.get("last_observed_at") is None:
                violations.add("SEM-L04")
        source = attempt.get("last_observation_source")
        if source in {"seat", "chanvoy", "operator_presence"}:
            violations.add("SEM-L05")

    return sorted(violations)


manifest_path = FIXTURES / "semantic/manifest.json"
if not manifest_path.is_file():
    fail("semantic: manifest.json is required")
else:
    try:
        manifest = load(manifest_path)
    except (OSError, json.JSONDecodeError) as error:
        fail(f"semantic: cannot load manifest.json: {error}")
        manifest = None
    if not isinstance(manifest, Mapping):
        fail("semantic: manifest root must be an object")
    else:
        layer = mapping(manifest.get("semantic_layer"))
        conforming_names = manifest.get("conforming")
        negative_rules = manifest.get("negative")
        if (
            layer.get("id") != SEMANTIC_LAYER_ID
            or layer.get("version") != SEMANTIC_LAYER_VERSION
        ):
            fail(
                f"semantic manifest declares {dict(layer)}, this validator implements "
                f"{SEMANTIC_LAYER_ID} {SEMANTIC_LAYER_VERSION} (fail-closed)"
            )
        elif (
            not isinstance(conforming_names, list)
            or not all(isinstance(name, str) for name in conforming_names)
            or not isinstance(negative_rules, Mapping)
            or not all(
                isinstance(name, str) and isinstance(rule, str)
                for name, rule in negative_rules.items()
            )
        ):
            fail(
                "semantic manifest: conforming must be string list and negative string->rule map"
            )
        else:
            ok(f"semantic layer {SEMANTIC_LAYER_ID} {SEMANTIC_LAYER_VERSION}")
            semantic_conforming = FIXTURES / "semantic/conforming"
            semantic_negative = FIXTURES / "semantic/negative"
            for name in conforming_names:
                path = semantic_conforming / name
                if not path.is_file():
                    fail(f"semantic conforming {name}: fixture is missing")
                    continue
                try:
                    violations = semantic_violations(load(path))
                except (OSError, json.JSONDecodeError) as error:
                    fail(f"semantic conforming {name}: cannot load JSON: {error}")
                    continue
                if violations:
                    fail(f"semantic conforming {name}: {violations}")
                else:
                    ok(f"semantic conforming {name}")
            for name, rule in negative_rules.items():
                path = semantic_negative / name
                if not path.is_file():
                    fail(f"semantic negative {name}: fixture is missing")
                    continue
                try:
                    violations = semantic_violations(load(path))
                except (OSError, json.JSONDecodeError) as error:
                    fail(f"semantic negative {name}: cannot load JSON: {error}")
                    continue
                if rule in violations:
                    ok(f"semantic negative {name} (violates {rule})")
                else:
                    fail(
                        f"semantic negative {name}: expected violation {rule}, got {violations}"
                    )

            listed = set(conforming_names) | set(negative_rules)
            present = {
                path.name
                for directory in (semantic_conforming, semantic_negative)
                for path in directory.glob("*.json")
            }
            if listed != present:
                fail(
                    "semantic manifest / fixture drift: "
                    f"only-in-manifest={sorted(listed - present)} "
                    f"only-on-disk={sorted(present - listed)}"
                )


print()
if failures:
    print(f"{len(failures)} failure(s)")
    sys.exit(1)
print("mission v0.1 family: all checks green")
