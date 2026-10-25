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
retention_rank = {
    key: index
    for index, key in enumerate(
        ["unknown", "transient", "short", "standard", "long", "legal-hold"]
    )
}

# --- registry semantics ------------------------------------------------------


def registry_violations(document: dict) -> list[str]:
    violations: list[str] = []
    kinds = document.get("kinds", [])
    names = [entry.get("kind") for entry in kinds]
    if len(names) != len(set(names)):
        violations.append("duplicate kind")
    for name in names:
        if name not in kind_values or name == "unknown":
            violations.append(f"kind {name!r} is not a memory-kind value")
    for value in kind_values:
        if value != "unknown" and value not in names:
            violations.append(f"memory-kind value {value!r} has no registry entry")
    contracts = [e["payload_contract"] for e in kinds if "payload_contract" in e]
    if len(contracts) != len(set(contracts)):
        violations.append("payload_contract used by more than one kind")
    for entry in kinds:
        cls = entry.get("classification", {})
        sensitivity = cls.get("sensitivity")
        tier = cls.get("access-tier")
        if sensitivity in ACCESS_FLOOR and tier in tier_rank:
            if tier_rank[tier] < tier_rank[ACCESS_FLOOR[sensitivity]]:
                violations.append(
                    f"{entry.get('kind')}: access-tier {tier} below floor for {sensitivity}"
                )
        if sensitivity == "unknown" and entry.get("classification_at_write") != "required":
            violations.append(
                f"{entry.get('kind')}: unknown sensitivity needs classification_at_write"
            )
        if (sensitivity == "unknown") != (tier == "unknown"):
            violations.append(f"{entry.get('kind')}: unknown must be paired")
    return violations


kind_registry = load(REGISTRY_FILE)
errors = list(registry_validator.iter_errors(kind_registry))
violations = registry_violations(kind_registry)
if errors:
    fail(f"registry kinds.json: {errors[0].message}")
elif violations:
    fail(f"registry kinds.json: {violations[0]}")
else:
    ok("registry kinds.json")

for fixture in sorted((FIXTURES / "kind-registry/negative").glob("*.json")):
    if fixture.name == "expected.json":
        continue
    instance = load(fixture)
    if list(registry_validator.iter_errors(instance)) or registry_violations(instance):
        ok(f"kind-registry negative {fixture.name}")
    else:
        fail(f"kind-registry negative {fixture.name}: expected rejection, got pass")

by_contract = {
    entry["payload_contract"]: entry
    for entry in kind_registry["kinds"]
    if "payload_contract" in entry
}

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


def entry_violations(entry: dict) -> list[str]:
    violations: list[str] = []
    if not record_validator.is_valid(entry):
        violations.append("not a valid durable-record/v1 record")
    policy = by_contract.get(entry.get("payload_contract"))
    if policy is None:
        return violations + ["payload_contract not registered"]
    kind = policy["kind"]

    if "payload" in entry:
        payload_errors = list(
            kind_validators[entry["payload_contract"]].iter_errors(entry["payload"])
        )
        if payload_errors:
            violations.append(f"{kind} payload: {payload_errors[0].message}")
        for path in secret_paths(entry["payload"]):
            violations.append(f"secret-shaped member at {path}")
    if (policy["carrier"] == "body") != ("body" in entry):
        violations.append(f"{kind} must carry a {policy['carrier']}")
    cap = policy.get("limits", {}).get("max_body_bytes")
    if cap is not None and entry.get("body", {}).get("length", 0) > cap:
        violations.append(f"{kind} body exceeds {cap} bytes")

    cls = entry.get("classification", {})
    floor = policy["classification"]
    if cls.get("sensitivity") == "unknown" or cls.get("retention") == "unknown":
        if policy.get("classification_at_write") == "required":
            violations.append(f"{kind} requires classification at write")
    if sensitivity_rank.get(cls.get("sensitivity"), -1) < sensitivity_rank[floor["sensitivity"]]:
        violations.append(f"{kind} sensitivity below floor {floor['sensitivity']}")
    if retention_rank.get(cls.get("retention"), -1) < retention_rank[floor["retention-lifecycle"]]:
        violations.append(f"{kind} retention below floor {floor['retention-lifecycle']}")

    claims = WRITER_CLAIMS[policy["writer_class"]]
    actor_kind = entry.get("provenance", {}).get("actor_kind")
    owner = entry.get("stream", "").split(".", 1)[0]
    actor = entry.get("provenance", {}).get("actor")
    cross_role_ack = (
        policy.get("cross_role_write") == "ack"
        and entry.get("revision", 1) > 1
        and actor_kind == "agent"
    )
    if actor_kind not in claims:
        violations.append(f"{kind} is {policy['writer_class']}-class; {actor_kind} claim rejected")
    elif policy["writer_class"] == "agent" and actor != owner and not cross_role_ack:
        violations.append(f"{actor} may not write into {owner}'s stream")
    return violations


for disposition in ("conforming", "negative"):
    fixtures = sorted((FIXTURES / "entry" / disposition).glob("*.json"))
    fixtures = [f for f in fixtures if f.name != "expected.json"]
    if not fixtures:
        fail(f"entry {disposition}: fixture set is empty")
    for fixture in fixtures:
        instance = load(fixture)
        errors = list(entry_validator.iter_errors(instance))
        violations = entry_violations(instance)
        if disposition == "conforming":
            if errors:
                fail(f"entry conforming {fixture.name}: {errors[0].message}")
            elif violations:
                fail(f"entry conforming {fixture.name}: {violations[0]}")
            else:
                ok(f"entry conforming {fixture.name}")
        elif errors or violations:
            ok(f"entry negative {fixture.name}")
        else:
            fail(f"entry negative {fixture.name}: expected rejection, got pass")

expected = load(FIXTURES / "entry/negative/expected.json")
present = {f.stem for f in (FIXTURES / "entry/negative").glob("*.json")} - {"expected"}
if set(expected) != present:
    fail(f"entry negative expected.json out of step: {sorted(set(expected) ^ present)}")

covered = {load(f)["payload_contract"] for f in (FIXTURES / "entry/conforming").glob("*.json")}
for contract in by_contract:
    if contract not in covered:
        fail(f"entry conforming: no fixture for {contract}")

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
