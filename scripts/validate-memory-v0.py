#!/usr/bin/env python3
"""Validate the agentic/memory v0 contract family and the memory-kind dimension."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import sys

try:
    from jsonschema import Draft202012Validator, FormatChecker
    from referencing import Registry, Resource
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "error: the 'jsonschema' package is required "
        "(try: uv run --with jsonschema scripts/validate-memory-v0.py)\n"
    )
    sys.exit(1)

REPO = pathlib.Path(__file__).resolve().parent.parent
FAMILY = REPO / "schemas/agentic/memory/v0"
FIXTURES = FAMILY / "fixtures"
REGISTRY_FILE = REPO / "config/agentic/memory/v0/kinds.json"
DIMENSION_FILE = REPO / "config/classifiers/dimensions/memory-kind.dimension.json"
VENDOR_DIMENSIONS = REPO / "config/classifiers/vendor/3leaps"
VENDOR_RECORD = REPO / "schemas/vendor/3leaps/durable-record/v1"
VENDOR_JCS = REPO / "scripts/vendor/3leaps"
SECRET_KEYS = REPO / "schemas/common/v0/secret-keys.schema.json"
VECTORS = FAMILY / "digest-vectors.json"

# Minimum access-tier for each sensitivity (3leaps access-tier standard).
ACCESS_FLOOR = {
    "unknown": "unknown",
    "0-public": "public",
    "1-confidential": "internal",
    "2-blinded": "internal",
    "3-proprietary": "restricted",
    "4-personal": "privileged",
    "5-privileged": "privileged",
    "6-eyes-only": "eyes-only",
}
# Classifier values the families inline, by the property that inlines them.
INLINED = {
    "sensitivity": "sensitivity",
    "access-tier": "access-tier",
    "retention-lifecycle": "retention-lifecycle",
}
# Who may claim to write each writer class. The credential is the authority;
# offline there is no credential, so a mismatch fails and a match only shows
# the claim is consistent.
WRITER_CLAIMS = {
    "agent": {"agent"},
    "maintainer": {"human"},
    "external": {"process"},
}

failures: list[str] = []


def load(path: pathlib.Path):
    return json.loads(path.read_text())


def fail(message: str) -> None:
    failures.append(message)
    print(f"FAIL {message}")


def ok(message: str) -> None:
    print(f"ok   {message}")


def dimension_keys(path: pathlib.Path) -> list[str]:
    definition = load(path)
    if definition["type"] == "sortable":
        values = definition["sortable"]["ordered_values"]
    else:
        values = definition["categorical"]["values"]
    return [value["key"] for value in values]


def dimension_order(path: pathlib.Path) -> dict[str, int]:
    return {key: index for index, key in enumerate(dimension_keys(path))}


def load_jcs():
    # Keep the vendored directory byte-identical to its manifest.
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location(
        "rfc8785", VENDOR_JCS / "rfc8785-canonicalize.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# --- vendored files match their manifests -----------------------------------

for directory in (VENDOR_DIMENSIONS, VENDOR_RECORD, VENDOR_JCS):
    manifest = load(directory / "MANIFEST.json")
    for name, entry in manifest["files"].items():
        digest = hashlib.sha256((directory / name).read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            fail(f"vendor {directory.name}/{name}: sha256 differs from MANIFEST")
        else:
            ok(f"vendor {directory.relative_to(REPO)}/{name}")

# --- schema resources --------------------------------------------------------

schema_paths = (
    [FAMILY / "entry.schema.json", FAMILY / "kind-registry.schema.json"]
    + sorted((FAMILY / "kinds").glob("*.schema.json"))
    + [SECRET_KEYS, VENDOR_RECORD / "record.schema.json"]
)
resources = []
schemas: dict[str, dict] = {}
for path in schema_paths:
    schema = load(path)
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as error:  # noqa: BLE001
        fail(f"lint {path.name}: {error}")
        continue
    schema_id = schema.get("$id", "")
    if path.parent != VENDOR_RECORD and schema_id.rsplit("/", 1)[-1] != path.name:
        fail(f"lint {path.name}: $id basename mismatch")
        continue
    ok(f"lint {path.relative_to(REPO)}")
    schemas[schema_id] = schema
    resources.append((schema_id, Resource.from_contents(schema)))
registry = Registry().with_resources(resources)


def validator_for(schema_id: str) -> Draft202012Validator:
    return Draft202012Validator(
        schemas[schema_id], registry=registry, format_checker=FormatChecker()
    )


ENTRY_ID = "https://schemas.lanyte.dev/agentic/memory/v0/entry.schema.json"
REGISTRY_ID = "https://schemas.lanyte.dev/agentic/memory/v0/kind-registry.schema.json"
RECORD_ID = "contract:durable-record/v1/record.schema.json"
SECRET_ID = "https://schemas.lanyte.dev/common/v0/secret-keys.schema.json"
entry_validator = validator_for(ENTRY_ID)
registry_validator = validator_for(REGISTRY_ID)
record_validator = validator_for(RECORD_ID)
secret_name = Draft202012Validator(
    {"$ref": f"{SECRET_ID}#/$defs/secretShapedName"}, registry=registry
)
kind_validators = {
    "contract: " + path.name.removesuffix(".schema.json") + "/v0": validator_for(
        load(path)["$id"]
    )
    for path in sorted((FAMILY / "kinds").glob("*.schema.json"))
}

# --- the memory-kind dimension -----------------------------------------------

dimension_meta = Draft202012Validator(
    load(VENDOR_DIMENSIONS / "schemas/dimension-definition.schema.json")
)
dimension = load(DIMENSION_FILE)
errors = list(dimension_meta.iter_errors(dimension))
if errors:
    fail(f"dimension memory-kind: {errors[0].message}")
else:
    ok("dimension memory-kind")
kind_values = dimension_keys(DIMENSION_FILE)

# --- classifier drift: inlined enums == vendored 3leaps dimensions -----------

registry_schema = schemas[REGISTRY_ID]
for prop, dimension_key in INLINED.items():
    inlined = registry_schema["$defs"]["classification"]["properties"][prop]["enum"]
    vendored = dimension_keys(
        VENDOR_DIMENSIONS / f"dimensions/{dimension_key}.dimension.json"
    )
    if inlined != vendored:
        fail(f"drift {prop}: registry {inlined} != 3leaps {vendored}")
    else:
        ok(f"drift {prop}")
volatility = registry_schema["$defs"]["kind"]["properties"]["stream_volatility"]["enum"]
if volatility != dimension_keys(VENDOR_DIMENSIONS / "dimensions/volatility.dimension.json"):
    fail("drift volatility: registry enum differs from 3leaps")
else:
    ok("drift volatility")
record_schema = schemas[RECORD_ID]["$defs"]["classification"]["properties"]
for prop, dimension_key in (
    ("sensitivity", "sensitivity"),
    ("retention", "retention-lifecycle"),
):
    if record_schema[prop]["enum"] != dimension_keys(
        VENDOR_DIMENSIONS / f"dimensions/{dimension_key}.dimension.json"
    ):
        fail(f"drift durable-record {prop}: differs from 3leaps {dimension_key}")
    else:
        ok(f"drift durable-record {prop}")

sensitivity_rank = dimension_order(VENDOR_DIMENSIONS / "dimensions/sensitivity.dimension.json")
tier_rank = dimension_order(VENDOR_DIMENSIONS / "dimensions/access-tier.dimension.json")
retention_rank = dimension_order(
    VENDOR_DIMENSIONS / "dimensions/retention-lifecycle.dimension.json"
)
tier_by_rank = {rank: tier for tier, rank in tier_rank.items()}

# --- registry semantics ------------------------------------------------------
#
# Every violation carries a reason code. Negative fixtures name the code they
# must be rejected for in expected.json, so a fixture rejected for some other
# reason fails the gate instead of passing vacuously.


def registry_violations(document: dict) -> list[tuple[str, str]]:
    violations: list[tuple[str, str]] = []
    kinds = document.get("kinds", [])
    names = [entry.get("kind") for entry in kinds]
    if len(names) != len(set(names)):
        violations.append(("duplicate-kind", "a kind appears more than once"))
    for name in names:
        if name not in kind_values or name == "unknown":
            violations.append(("kind-not-in-dimension", f"{name!r} is not a memory-kind value"))
    for value in kind_values:
        if value != "unknown" and value not in names:
            violations.append(("dimension-value-unregistered", f"{value!r} has no registry entry"))
    contracts = [e["payload_contract"] for e in kinds if "payload_contract" in e]
    if len(contracts) != len(set(contracts)):
        violations.append(("duplicate-contract", "payload_contract used by more than one kind"))
    for entry in kinds:
        cls = entry.get("classification", {})
        sensitivity = cls.get("sensitivity")
        tier = cls.get("access-tier")
        if sensitivity in ACCESS_FLOOR and tier in tier_rank:
            if tier_rank[tier] < tier_rank[ACCESS_FLOOR[sensitivity]]:
                violations.append(
                    ("access-tier-floor", f"{entry.get('kind')}: {tier} below floor for {sensitivity}")
                )
        if sensitivity == "unknown" and entry.get("classification_at_write") != "required":
            violations.append(
                ("unknown-default", f"{entry.get('kind')}: unknown sensitivity needs classification_at_write")
            )
        if (sensitivity == "unknown") != (tier == "unknown"):
            violations.append(("unknown-unpaired", f"{entry.get('kind')}: unknown must be paired"))
        contract = entry.get("payload_contract")
        has_schema = contract in kind_validators
        if entry.get("carrier") == "payload" and contract and not has_schema:
            violations.append(("payload-schema-missing", f"{entry.get('kind')}: no payload schema"))
        if entry.get("carrier") == "body" and has_schema:
            violations.append(("body-kind-has-payload-schema", f"{entry.get('kind')}: body kinds have no payload schema"))
    return violations


def schema_codes(validator: Draft202012Validator, instance) -> list[tuple[str, str]]:
    return [("schema", error.message) for error in validator.iter_errors(instance)]


def check_negatives(group: str, directory: pathlib.Path, judge) -> None:
    expected = load(directory / "expected.json")
    present = {f.stem for f in directory.glob("*.json")} - {"expected"}
    if set(expected) != present:
        fail(f"{group} negative expected.json out of step: {sorted(set(expected) ^ present)}")
    for name in sorted(present):
        codes = {code for code, _ in judge(load(directory / f"{name}.json"))}
        want = expected.get(name, {}).get("code")
        if not codes:
            fail(f"{group} negative {name}.json: expected rejection, got pass")
        elif want not in codes:
            fail(f"{group} negative {name}.json: rejected for {sorted(codes)}, expected {want}")
        else:
            ok(f"{group} negative {name}.json ({want})")


kind_registry = load(REGISTRY_FILE)
problems = schema_codes(registry_validator, kind_registry) + registry_violations(kind_registry)
if problems:
    fail(f"registry kinds.json: {problems[0][1]}")
else:
    ok("registry kinds.json")

check_negatives(
    "kind-registry",
    FIXTURES / "kind-registry/negative",
    lambda doc: schema_codes(registry_validator, doc) + registry_violations(doc),
)

by_contract = {
    entry["payload_contract"]: entry
    for entry in kind_registry["kinds"]
    if "payload_contract" in entry
}

# --- bounds: every payload field has a stated maximum -------------------------


def unbounded(node: dict, path: str) -> list[str]:
    found: list[str] = []
    kind = node.get("type")
    if kind == "string" and not ({"maxLength", "enum", "const"} & node.keys()):
        found.append(path)
    if kind == "array":
        if "maxItems" not in node:
            found.append(path + "[]")
        found.extend(unbounded(node["items"], path + "[]"))
    for name, child in node.get("properties", {}).items():
        found.extend(unbounded(child, f"{path}.{name}"))
    return found


for contract, validator in kind_validators.items():
    gaps = unbounded(validator.schema, "$")
    if gaps:
        fail(f"bounds {contract}: unbounded {gaps}")
    else:
        ok(f"bounds {contract}")

# --- entry semantics ---------------------------------------------------------


def secret_paths(value, path: str = "$") -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        for name, child in value.items():
            if secret_name.is_valid(name):
                found.append(f"{path}.{name}")
            found.extend(secret_paths(child, f"{path}.{name}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(secret_paths(child, f"{path}[{index}]"))
    return found


# Every kind payload is closed today, so no fixture can reach the walk above
# through schema validation. Exercise it directly so the guard stays live for
# the first kind that admits an open map.
for probe, expected_paths in (
    ({"labels": {"api_key": "x"}}, ["$.labels.api_key"]),
    ({"items": [{"Token": "x"}]}, ["$.items[0].Token"]),
    ({"locator": "x", "env_names": ["X"]}, []),
):
    if secret_paths(probe) != expected_paths:
        fail(f"secret walk self-test {probe}: got {secret_paths(probe)}")
    else:
        ok(f"secret walk self-test {sorted(probe)}")


def reader_tier(entry: dict, policy: dict) -> str:
    """Access tier a reader needs: the kind's tier or the entry's sensitivity floor, whichever is higher."""
    kind_tier = policy["classification"]["access-tier"]
    floor = ACCESS_FLOOR.get(entry.get("classification", {}).get("sensitivity"), "unknown")
    return tier_by_rank[max(tier_rank[kind_tier], tier_rank[floor])]


def entry_violations(entry: dict) -> list[tuple[str, str]]:
    violations: list[tuple[str, str]] = []
    if not record_validator.is_valid(entry):
        violations.append(("not-durable-record", "not a valid durable-record/v1 record"))
    policy = by_contract.get(entry.get("payload_contract"))
    if policy is None:
        return violations + [("unregistered-contract", "payload_contract not registered")]
    kind = policy["kind"]
    payload = entry.get("payload") if isinstance(entry.get("payload"), dict) else {}

    # Carrier and content.
    if (policy["carrier"] == "body") != ("body" in entry):
        violations.append(("carrier", f"{kind} must carry a {policy['carrier']}"))
    if "payload" in entry and entry["payload_contract"] in kind_validators:
        for error in kind_validators[entry["payload_contract"]].iter_errors(entry["payload"]):
            violations.append(("payload-schema", f"{kind} payload: {error.message}"))
    if "payload" in entry:
        for path in secret_paths(entry["payload"]):
            violations.append(("secret-shaped-member", f"secret-shaped member at {path}"))
    body = entry.get("body", {})
    cap = policy.get("limits", {}).get("max_body_bytes")
    if cap is not None and body.get("length", 0) > cap:
        violations.append(("body-over-cap", f"{kind} body exceeds {cap} bytes"))
    media_types = policy.get("body_media_types")
    if media_types is not None and "body" in entry and body.get("media_type") not in media_types:
        violations.append(("body-media-type", f"{kind} body media type {body.get('media_type')!r} not accepted"))

    # Revision policy.
    revision = entry.get("revision", 1)
    if policy["revision_policy"] == "single" and revision != 1:
        violations.append(("single-revision", f"{kind} is written at revision 1 only"))
    supersedes = entry.get("supersedes")
    if isinstance(supersedes, dict) and supersedes.get("revision") != revision - 1:
        violations.append(("supersedes-gap", "supersedes must name the immediately previous revision"))

    # Classification floors.
    cls = entry.get("classification", {})
    floor = policy["classification"]
    if cls.get("sensitivity") == "unknown" or cls.get("retention") == "unknown":
        if policy.get("classification_at_write") == "required":
            violations.append(("classification-at-write", f"{kind} requires classification at write"))
    if sensitivity_rank.get(cls.get("sensitivity"), -1) < sensitivity_rank[floor["sensitivity"]]:
        violations.append(("sensitivity-floor", f"{kind} sensitivity below floor {floor['sensitivity']}"))
    if retention_rank.get(cls.get("retention"), -1) < retention_rank[floor["retention-lifecycle"]]:
        violations.append(("retention-floor", f"{kind} retention below floor {floor['retention-lifecycle']}"))

    # Authority. The actor is the writing seat as <role>.<scope>; a stream is
    # written by its owner except for a handoff acknowledgement by the seat
    # the handoff names.
    provenance = entry.get("provenance", {})
    actor_kind = provenance.get("actor_kind")
    actor = provenance.get("actor")
    stream = entry.get("stream", "")
    if actor_kind not in WRITER_CLAIMS[policy["writer_class"]]:
        violations.append(
            ("writer-class", f"{kind} is {policy['writer_class']}-class; {actor_kind} claim rejected")
        )
    elif policy["writer_class"] == "agent" and actor != stream:
        handoff_ack = (
            policy.get("cross_role_write") == "ack"
            and revision > 1
            and payload.get("state") == "acknowledged"
            and actor == payload.get("to")
        )
        if not handoff_ack:
            violations.append(("foreign-stream", f"{actor} may not write into stream {stream}"))
    if kind == "identity":
        agent = payload.get("agent", {})
        if f"{agent.get('role')}.{agent.get('scope')}" != stream:
            violations.append(("identity-stream", "identity role and scope must match the stream"))
    return violations


def entry_judge(instance) -> list[tuple[str, str]]:
    return schema_codes(entry_validator, instance) + entry_violations(instance)


conforming = sorted((FIXTURES / "entry/conforming").glob("*.json"))
if not conforming:
    fail("entry conforming: fixture set is empty")
for fixture in conforming:
    problems = entry_judge(load(fixture))
    if problems:
        fail(f"entry conforming {fixture.name}: {problems[0][1]}")
    else:
        ok(f"entry conforming {fixture.name}")

check_negatives("entry", FIXTURES / "entry/negative", entry_judge)

covered = {load(f)["payload_contract"] for f in conforming}
for contract in by_contract:
    if contract not in covered:
        fail(f"entry conforming: no fixture for {contract}")

# Reader tier: raising an entry's sensitivity raises the tier a reader needs.
for fixture, want in load(FIXTURES / "reader-tier.json").items():
    entry = load(FIXTURES / "entry/conforming" / fixture)
    for sensitivity, tier in want.items():
        probe = json.loads(json.dumps(entry))
        probe["classification"]["sensitivity"] = sensitivity
        got = reader_tier(probe, by_contract[probe["payload_contract"]])
        if got != tier:
            fail(f"reader tier {fixture} at {sensitivity}: {got}, expected {tier}")
        else:
            ok(f"reader tier {fixture} at {sensitivity} -> {tier}")

# --- digest vectors (RFC 8785 JCS, sha256) -----------------------------------

jcs = load_jcs()
vectors = load(VECTORS)
for vector in vectors["vectors"]:
    instance = load(FAMILY / vector["entry"])
    canonical = jcs.jcs_dumps(instance).encode("utf-8")
    digest = "sha256:" + hashlib.sha256(canonical).hexdigest()
    if digest != vector["digest"]:
        fail(f"digest {vector['entry']}: {digest} != {vector['digest']}")
    elif len(canonical) != vector["canonical_length"]:
        fail(f"digest {vector['entry']}: canonical length {len(canonical)}")
    else:
        ok(f"digest {vector['entry']}")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)

print("\nagentic/memory v0 schemas, registry, dimension and fixtures: OK")
