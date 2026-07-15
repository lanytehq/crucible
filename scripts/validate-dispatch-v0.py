#!/usr/bin/env python3
"""Validator for the agentic/dispatch v0 contract family.

Checks, fail-closed (any failure => exit 1):
  1. Schema lint: both family schemas are valid JSON Schema 2020-12.
  2. Schema fixtures: every conforming fixture validates; every negative
     fixture fails, and fails for its stated reason (expected.json maps
     fixture -> {keyword, mentions}).
  3. Semantic layer (dispatch/v0-semantics 0.1.0, reference
     implementation of semantic-validation.md): all run-envelope
     conforming fixtures and semantic/conforming fixtures yield zero
     violations; every semantic/negative fixture yields a violation set
     containing the rule stated in semantic/manifest.json.

Requires the `jsonschema` package (JSON Schema 2020-12 checker, per the
repo's fixture-validation convention). No network access is performed.

Usage:
  python3 scripts/validate-dispatch-v0.py
  # or, without a jsonschema install:
  uv run --with jsonschema scripts/validate-dispatch-v0.py
"""

from __future__ import annotations

import json
import pathlib
import sys
from datetime import datetime

try:
    from jsonschema import Draft202012Validator
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "error: the 'jsonschema' package is required "
        "(try: uv run --with jsonschema scripts/validate-dispatch-v0.py)\n"
    )
    sys.exit(1)

REPO = pathlib.Path(__file__).resolve().parent.parent
FAMILY = REPO / "schemas/agentic/dispatch/v0"
FIXTURES = FAMILY / "fixtures"

SEMANTIC_LAYER_ID = "dispatch/v0-semantics"
SEMANTIC_LAYER_VERSION = "0.1.1"

failures: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)
    print(f"FAIL {msg}")


def ok(msg: str) -> None:
    print(f"ok   {msg}")


def load(path: pathlib.Path):
    return json.loads(path.read_text())


# ---------------------------------------------------------------- 1. lint
validators: dict[str, Draft202012Validator] = {}
for name in ("run-envelope", "harness-profile"):
    schema_path = FAMILY / f"{name}.schema.json"
    schema = load(schema_path)
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as e:  # noqa: BLE001
        fail(f"lint {schema_path.name}: {e}")
        continue
    if schema.get("$id", "").rsplit("/", 1)[-1] != f"{name}.schema.json":
        fail(f"lint {schema_path.name}: $id basename mismatch")
    validators[name] = Draft202012Validator(schema)
    ok(f"lint {schema_path.name}")

if failures:
    sys.exit(1)


# ------------------------------------------------------ 2. schema fixtures
def check_schema_fixtures(name: str) -> None:
    v = validators[name]
    conforming = sorted((FIXTURES / name / "conforming").glob("*.json"))
    negative_dir = FIXTURES / name / "negative"
    expected = load(negative_dir / "expected.json")
    negative = sorted(p for p in negative_dir.glob("*.json") if p.name != "expected.json")
    if not conforming or not negative:
        fail(f"{name}: fixture set is empty")
        return
    for path in conforming:
        errs = sorted(v.iter_errors(load(path)), key=lambda e: str(e.path))
        if errs:
            fail(f"{name} conforming {path.name}: {errs[0].message}")
        else:
            ok(f"{name} conforming {path.name}")
    for path in negative:
        exp = expected.get(path.name)
        if exp is None:
            fail(f"{name} negative {path.name}: no expected-reason entry")
            continue
        errs = list(v.iter_errors(load(path)))
        if not errs:
            fail(f"{name} negative {path.name}: expected rejection, got pass")
            continue

        def leaves(errors):
            for e in errors:
                if e.context:
                    yield from leaves(e.context)
                else:
                    yield e

        matched = any(
            e.validator == exp["keyword"]
            and (exp["mentions"] in e.json_path or exp["mentions"] in str(e.message))
            for e in leaves(errs)
        )
        if matched:
            ok(f"{name} negative {path.name} (rejects: {exp['keyword']} @ {exp['mentions']})")
        else:
            got = "; ".join(f"{e.validator}@{e.json_path}" for e in leaves(errs))
            fail(
                f"{name} negative {path.name}: rejected, but not for the stated reason "
                f"(want {exp['keyword']} @ {exp['mentions']}; got {got})"
            )
    stray = expected.keys() - {p.name for p in negative}
    if stray:
        fail(f"{name} negative: expected.json names missing fixtures: {sorted(stray)}")


check_schema_fixtures("run-envelope")
check_schema_fixtures("harness-profile")


# ------------------------------------------------- 3. semantic layer (ref)
def parse_instant(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


STRENGTH = {"none": 0, "deny-rules": 1, "sandbox": 2}


def envelope_violations(env: dict) -> list[str]:
    v: list[str] = []
    if parse_instant(env["ended_at"]) < parse_instant(env["started_at"]):
        v.append("SEM-E01")
    if env["verdict"] is not None and env["raw_text"] is not None:
        v.append("SEM-E02")
    if env["verdict"] is not None and env["parse_error"] is not None:
        v.append("SEM-E03")
    if env["verdict"] is not None and (
        env["verdict_schema_id"] is None or env["verdict_schema_sha256"] is None
    ):
        v.append("SEM-E04")
    schema_digest = env["digests"]["schema_sha256"]
    if (
        (env["verdict_schema_sha256"] is None) != (schema_digest is None)
        or (env["verdict_schema_id"] is None) != (schema_digest is None)
        or (schema_digest is not None and env["verdict_schema_sha256"] != schema_digest)
    ):
        v.append("SEM-E05")
    if env["group_reap"] == "survivors" and env["runner_exit"] == 0:
        v.append("SEM-E06")
    if env["runner_exit"] == 2 and not (
        env["verdict"] is None and schema_digest is not None and env["harness_exit"] == 0
    ):
        v.append("SEM-E07")
    if (
        env["outcome"] == "completed"
        and env["runner_exit"] == 0
        and schema_digest is not None
        and env["verdict"] is None
    ):
        v.append("SEM-E08")
    if env["rejected_verdict"] is not None and not (
        env["verdict"] is None and env["parse_error"] is not None
    ):
        v.append("SEM-E09")
    if (env["timed_out"] and env["outcome"] not in ("timeout", "interrupted")) or (
        env["interrupted"] and env["outcome"] != "interrupted"
    ):
        v.append("SEM-E10")
    if (
        env["outcome"] == "completed"
        and env["runner_exit"] == 5
        and env["harness_exit"] == 0
        and env["group_reap"] != "survivors"
    ):
        v.append("SEM-E11")
    if (
        env["outcome"] == "completed"
        and env["runner_exit"] == 0
        and (env["harness_exit"] != 0 or env["group_reap"] == "survivors")
    ):
        v.append("SEM-E12")
    return v


def validity_violations(profile: dict, live: dict) -> list[str]:
    holds = (
        live.get("version") is not None
        and live.get("version") == profile["executable_version"]
        and live.get("platform") == profile["platform"]
    )
    return [] if holds else ["SEM-VC01"]


def routing_violations(profile: dict, routing: dict) -> list[str]:
    v: list[str] = []
    ev = routing.get("posture_evidence") or {}
    subset_equal = (
        routing.get("write_denial") == profile["write_denial"]["control"]
        and routing.get("fenced") == profile["fenced"]
        and ev.get("version") == profile["executable_version"]
        and ev.get("platform") == profile["platform"]
        and (not profile["fenced"] or routing.get("fence_reason") == profile["fence_reason"])
    )
    if not subset_equal:
        v.append("SEM-R01")
    escalated = STRENGTH.get(routing.get("write_denial"), 99) > STRENGTH[
        profile["write_denial"]["control"]
    ] or (profile["fenced"] and not routing.get("fenced"))
    if escalated:
        v.append("SEM-R02")
    claims_eligible = not routing.get("fenced") and routing.get("write_denial") != "none"
    if claims_eligible and (profile["posture"] == "none" or profile["fenced"]):
        v.append("SEM-R03")
    return v


def semantic_violations(fixture: dict) -> list[str]:
    kind = fixture.get("kind")
    if kind == "envelope":
        return envelope_violations(fixture["envelope"])
    if kind == "profile-live":
        return validity_violations(fixture["profile"], fixture["live"])
    if kind == "routing-projection":
        return routing_violations(fixture["profile"], fixture["routing"])
    return [f"unknown fixture kind: {kind!r}"]


manifest = load(FIXTURES / "semantic/manifest.json")
layer = manifest.get("semantic_layer", {})
if layer.get("id") != SEMANTIC_LAYER_ID or layer.get("version") != SEMANTIC_LAYER_VERSION:
    fail(
        f"semantic manifest declares {layer}, this validator implements "
        f"{SEMANTIC_LAYER_ID} {SEMANTIC_LAYER_VERSION} (fail-closed)"
    )
else:
    ok(f"semantic layer {SEMANTIC_LAYER_ID} {SEMANTIC_LAYER_VERSION}")

    for path in sorted((FIXTURES / "run-envelope/conforming").glob("*.json")):
        v = envelope_violations(load(path))
        if v:
            fail(f"semantic over conforming envelope {path.name}: {v}")
        else:
            ok(f"semantic over conforming envelope {path.name}")

    for name in manifest["conforming"]:
        path = FIXTURES / "semantic/conforming" / name
        v = semantic_violations(load(path))
        if v:
            fail(f"semantic conforming {name}: {v}")
        else:
            ok(f"semantic conforming {name}")

    for name, rule in manifest["negative"].items():
        path = FIXTURES / "semantic/negative" / name
        v = semantic_violations(load(path))
        if rule in v:
            ok(f"semantic negative {name} (violates {rule})")
        else:
            fail(f"semantic negative {name}: expected violation {rule}, got {v}")

    listed = set(manifest["conforming"]) | set(manifest["negative"])
    present = {
        p.name
        for d in ("conforming", "negative")
        for p in (FIXTURES / "semantic" / d).glob("*.json")
        if p.name != "manifest.json"
    }
    if listed != present:
        fail(
            "semantic manifest / fixture drift: "
            f"only-in-manifest={sorted(listed - present)} only-on-disk={sorted(present - listed)}"
        )


# -------------------------------------------------------- engagement blind
BLIND_ALLOWED_PREFIXES = ("fixture-",)
for path in FIXTURES.rglob("*.json"):
    doc = load(path)

    def walk(node):
        if isinstance(node, dict):
            for k, val in node.items():
                if k == "engagement" and isinstance(val, str) and not val.startswith(
                    BLIND_ALLOWED_PREFIXES
                ):
                    fail(f"engagement-blind {path.name}: engagement {val!r} is not fixture-*")
                walk(val)
        elif isinstance(node, list):
            for val in node:
                walk(val)

    walk(doc)
ok("engagement-blind fixture gate (all engagement labels are fixture-*)")

print()
if failures:
    print(f"{len(failures)} failure(s)")
    sys.exit(1)
print("dispatch v0 family: all checks green")
