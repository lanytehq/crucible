#!/usr/bin/env python3
"""Validate the mail v0 contract family."""

from __future__ import annotations

import datetime
import hashlib
import json
import pathlib
import sys

try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "error: the 'jsonschema' package is required "
        "(try: uv run --with jsonschema "
        "scripts/validate-mail-v0.py)\n"
    )
    sys.exit(1)

REPO = pathlib.Path(__file__).resolve().parent.parent
FAMILY = REPO / "schemas/mail/v0"
FIXTURES = FAMILY / "fixtures"
ARTIFACTS = {
    "delegation": FAMILY / "delegation.schema.json",
    "action-request": FAMILY / "action-request.schema.json",
    "policy-decision": FAMILY / "policy-decision.schema.json",
}

SEND_CLASS = {"send", "reply", "forward"}
MUTATE_CLASS = {"draft", "mark", "move", "archive", "trash"}
DECISION_RANK = {"allow": 0, "require_approval": 1, "deny": 2}
# Signal outcomes that raise a decision to at least require_approval, per class.
ESCALATING_OUTCOMES = {
    "send": {"flag", "abstain", "error"},
    "mutate": {"flag"},
    "read": set(),
}


def op_class(op) -> str:
    if op in SEND_CLASS:
        return "send"
    if op in MUTATE_CLASS:
        return "mutate"
    return "read"

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


def later(first, second) -> bool | None:
    """True when second is strictly later than first; None when not comparable."""
    try:
        return parse_datetime(second) > parse_datetime(first)
    except (TypeError, ValueError):
        return None


def semantic_violations(artifact: str, instance: dict) -> list[str]:
    violations: list[str] = []
    if artifact == "delegation":
        valid_from = instance.get("valid_from")
        for field in ("expires_at", "revoked_at"):
            value = instance.get(field)
            if value is not None and later(valid_from, value) is False:
                violations.append(f"{field} must be later than valid_from")
    elif artifact == "action-request":
        if instance.get("op") in SEND_CLASS:
            if "content" not in instance:
                violations.append("send-class op requires content.draft_digest")
            recipients = instance.get("recipients") or {}
            if not any(recipients.get(k) for k in ("to", "cc", "bcc")):
                violations.append("send-class op requires at least one recipient")
    elif artifact == "policy-decision":
        baseline = DECISION_RANK.get(instance.get("baseline_decision"))
        final = DECISION_RANK.get(instance.get("decision"))
        if baseline is not None and final is not None and final < baseline:
            violations.append("decision must not be weaker than baseline_decision")
        outcomes = {
            signal.get("outcome")
            for signal in instance.get("signals") or []
            if isinstance(signal, dict)
        }
        escalating = ESCALATING_OUTCOMES[op_class(instance.get("op"))]
        if final is not None and outcomes & escalating:
            if final < DECISION_RANK["require_approval"]:
                violations.append(
                    "escalating signal outcome requires at least require_approval"
                )
        if baseline is not None and final is not None and final > baseline:
            reasons = instance.get("reasons") or []
            if not any(
                isinstance(r, dict) and r.get("source") == "signal" for r in reasons
            ):
                violations.append("escalation above baseline requires a signal reason")
            if not outcomes & escalating:
                violations.append(
                    "escalation above baseline requires an escalating signal"
                )
        has_approval = "approval" in instance
        if instance.get("decision") == "require_approval" and not has_approval:
            violations.append("require_approval requires an approval binding")
        if instance.get("decision") != "require_approval" and has_approval:
            violations.append("approval binding only accompanies require_approval")
        if has_approval:
            approval = instance["approval"]
            if later(instance.get("decided_at"), approval.get("expires_at")) is False:
                violations.append("approval.expires_at must be later than decided_at")
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


def canonical_digest(instance: dict) -> str:
    encoded = json.dumps(
        instance, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def pair_violations(request: dict, decision: dict) -> list[str]:
    """Cross-record rules binding a decision to the request it decided."""
    violations: list[str] = []
    for field in ("request_id", "delegation_id", "op"):
        if request.get(field) != decision.get(field):
            violations.append(f"{field} differs between request and decision")
    if decision.get("input_digest") != canonical_digest(request):
        violations.append("input_digest is not the canonical request digest")
    projected = [
        {key: signal.get(key) for key in ("source", "id", "outcome")}
        for signal in request.get("signals") or []
        if isinstance(signal, dict)
    ]
    if decision.get("signals") != projected:
        violations.append("decision signals differ from the request signals")
    approval = decision.get("approval")
    if isinstance(approval, dict):
        content = request.get("content") or {}
        if approval.get("draft_digest") != content.get("draft_digest"):
            violations.append("approval draft_digest differs from the request")
    return violations


validators = {
    artifact: Draft202012Validator(load(path), format_checker=FormatChecker())
    for artifact, path in ARTIFACTS.items()
}
for disposition in ("conforming", "negative"):
    pair_dirs = sorted(
        d for d in (FIXTURES / "pairs" / disposition).glob("*") if d.is_dir()
    )
    if not pair_dirs:
        fail(f"pairs {disposition}: fixture set is empty")
        continue
    for pair_dir in pair_dirs:
        request = load(pair_dir / "request.json")
        decision = load(pair_dir / "decision.json")
        single = [
            f"request: {e.message}"
            for e in validators["action-request"].iter_errors(request)
        ] + [
            f"decision: {e.message}"
            for e in validators["policy-decision"].iter_errors(decision)
        ]
        single += semantic_violations("action-request", request)
        single += semantic_violations("policy-decision", decision)
        if single:
            fail(f"pairs {disposition} {pair_dir.name}: record invalid: {single[0]}")
            continue
        violations = pair_violations(request, decision)
        if disposition == "conforming":
            if violations:
                fail(f"pairs conforming {pair_dir.name}: {violations[0]}")
            else:
                ok(f"pairs conforming {pair_dir.name}")
        elif violations:
            ok(f"pairs negative {pair_dir.name}")
        else:
            fail(f"pairs negative {pair_dir.name}: expected rejection, got pass")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)

print("\nMail v0 schemas and fixtures: OK")
