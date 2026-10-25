#!/usr/bin/env python3
"""Validate the agentic/memory v0 contract family and the memory-kind dimension."""

from __future__ import annotations

import datetime
import hashlib
import json
import pathlib
import re
import sys
import urllib.parse

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


def _strict_object(pairs: list[tuple[str, object]]) -> dict:
    seen: dict = {}
    for name, value in pairs:
        if name in seen:
            raise ValueError(f"duplicate member {name!r}")
        seen[name] = value
    return seen


def _check_text(value) -> None:
    if isinstance(value, str):
        try:
            value.encode("utf-8")
        except UnicodeEncodeError as error:
            raise ValueError("lone surrogate in string") from error
    elif isinstance(value, dict):
        for name, child in value.items():
            _check_text(name)
            _check_text(child)
    elif isinstance(value, list):
        for child in value:
            _check_text(child)


def parse_ijson(raw: str):
    """Decode I-JSON: unique member names, well-formed Unicode, finite numbers."""
    value = json.loads(
        raw,
        object_pairs_hook=_strict_object,
        parse_constant=lambda name: (_ for _ in ()).throw(ValueError(name)),
    )
    _check_text(value)
    return value


verified_bytes: dict[pathlib.Path, bytes] = {}


def load(path: pathlib.Path):
    """Read JSON; vendored files come only from the bytes verified against their manifest."""
    if path in verified_bytes:
        return parse_ijson(verified_bytes[path].decode("utf-8"))
    return parse_ijson(path.read_text(encoding="utf-8"))


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


# --- vendored files match their manifests -----------------------------------
#
# Runs before anything reads a vendored file. Each manifest must list exactly
# the files in its directory; any mismatch stops the gate before vendored code
# or schemas are loaded.

VENDOR_INVENTORY = {
    VENDOR_DIMENSIONS: {
        "dimensions/access-tier.dimension.json",
        "dimensions/retention-lifecycle.dimension.json",
        "dimensions/sensitivity.dimension.json",
        "dimensions/volatility.dimension.json",
        "schemas/dimension-definition.schema.json",
    },
    VENDOR_RECORD: {"record.schema.json"},
    VENDOR_JCS: {"rfc8785-canonicalize.py"},
}
for directory, inventory in VENDOR_INVENTORY.items():
    label = directory.relative_to(REPO)
    try:
        manifest = load(directory / "MANIFEST.json")
    except (OSError, ValueError) as error:
        fail(f"vendor {label}: unreadable MANIFEST.json: {error}")
        continue
    files = manifest.get("files") if isinstance(manifest, dict) else None
    commit = manifest.get("commit") if isinstance(manifest, dict) else None
    if not isinstance(commit, str) or len(commit) != 40:
        fail(f"vendor {label}: MANIFEST.json commit is not a full sha")
    if not isinstance(files, dict) or set(files) != inventory:
        fail(f"vendor {label}: MANIFEST.json must list exactly {sorted(inventory)}")
        continue
    on_disk = {
        str(path.relative_to(directory))
        for path in directory.rglob("*")
        if path.is_file() and path.name != "MANIFEST.json"
    }
    if on_disk != inventory:
        fail(f"vendor {label}: unexpected files {sorted(on_disk ^ inventory)}")
    for name in sorted(inventory):
        raw = (directory / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != files[name].get("sha256"):
            fail(f"vendor {label}/{name}: sha256 differs from MANIFEST")
        else:
            verified_bytes[directory / name] = raw
            ok(f"vendor {label}/{name}")

if failures:
    print(f"\n{len(failures)} failure(s); vendored files unverified, stopping")
    sys.exit(1)


def load_jcs():
    """Run the canonicalizer from the exact bytes verified above."""
    path = VENDOR_JCS / "rfc8785-canonicalize.py"
    namespace = {"__name__": "rfc8785", "__file__": str(path)}
    exec(compile(verified_bytes[path], str(path), "exec"), namespace)
    return namespace


jcs = load_jcs()

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


# Formats this family uses, checked with the standard library. jsonschema
# treats a format with no registered checker as valid, so the gate registers
# its own and refuses any format it has no checker for.
RFC3339 = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})"
)
format_checker = FormatChecker(formats=())


@format_checker.checks("date-time", raises=ValueError)
def is_date_time(value) -> bool:
    if not isinstance(value, str):
        return True
    if not RFC3339.fullmatch(value):
        raise ValueError("not an RFC 3339 date-time")
    datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    return True


@format_checker.checks("date", raises=ValueError)
def is_date(value) -> bool:
    if not isinstance(value, str):
        return True
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        raise ValueError("not a full-date")
    datetime.date.fromisoformat(value)
    return True


@format_checker.checks("uri", raises=ValueError)
def is_uri(value) -> bool:
    if not isinstance(value, str):
        return True
    parts = urllib.parse.urlsplit(value)
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9+.-]*", parts.scheme) or not (parts.netloc or parts.path):
        raise ValueError("not an absolute URI")
    if any(c.isspace() for c in value):
        raise ValueError("URI contains whitespace")
    return True


def formats_used(node) -> set[str]:
    found: set[str] = set()
    if isinstance(node, dict):
        if isinstance(node.get("format"), str):
            found.add(node["format"])
        for child in node.values():
            found |= formats_used(child)
    elif isinstance(node, list):
        for child in node:
            found |= formats_used(child)
    return found


for schema_id, schema in schemas.items():
    missing = formats_used(schema) - set(format_checker.checkers)
    if missing:
        fail(f"formats {schema_id.rsplit('/', 1)[-1]}: no checker for {sorted(missing)}")


def validator_for(schema_id: str) -> Draft202012Validator:
    return Draft202012Validator(
        schemas[schema_id], registry=registry, format_checker=format_checker
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
        try:
            instance = load(directory / f"{name}.json")
        except ValueError:
            codes = {"ijson"}
        else:
            codes = {code for code, _ in judge(instance)}
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
            if name_rejected(name):
                found.append(f"{path}.{name}")
            found.extend(secret_paths(child, f"{path}.{name}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(secret_paths(child, f"{path}[{index}]"))
    elif isinstance(value, str) and credential_value.is_valid(value):
        found.append(f"{path} (credential-shaped value)")
    return found


member_name = Draft202012Validator(
    {"$ref": f"{SECRET_ID}#/$defs/memberName"}, registry=registry
)


def name_rejected(name: str) -> bool:
    return not member_name.is_valid(name) or secret_name.is_valid(name)


conformance = load(REPO / "schemas/common/v0/secret-keys.conformance.json")
for name in conformance["reject"]:
    if not name_rejected(name):
        fail(f"secret-keys conformance: {name!r} should be rejected")
for name in conformance["accept"]:
    if name_rejected(name):
        fail(f"secret-keys conformance: {name!r} should be accepted")
credential_value = Draft202012Validator(
    {"$ref": f"{SECRET_ID}#/$defs/credentialShapedValue"}, registry=registry
)
for value in conformance["value_reject"]:
    if not credential_value.is_valid(value):
        fail(f"secret-keys conformance: value {value!r} should match")
for value in conformance["value_accept"]:
    if credential_value.is_valid(value):
        fail(f"secret-keys conformance: value {value!r} should not match")
ok(f"secret-keys conformance ({len(conformance['reject'])} reject, {len(conformance['accept'])} accept, {len(conformance['value_reject'])} values)")

# Every kind payload is closed today, so no fixture can reach the walk above
# through schema validation. Exercise it directly so the guard stays live for
# the first kind that admits an open map.
for probe, expected_paths in (
    ({"labels": {"api_key": "x"}}, ["$.labels.api_key"]),
    ({"items": [{"Token": "x"}]}, ["$.items[0].Token"]),
    ({"locator": "x", "env_names": ["X"]}, []),
    ({"note": "Bearer abcdefgh12345678"}, ["$.note (credential-shaped value)"]),
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
    if kind == "handoff" and payload.get("state") == "acknowledged":
        if revision < 2 or actor != payload.get("to"):
            violations.append(
                ("ack-not-by-recipient", "a handoff is acknowledged only by the seat named in to, in a later revision")
            )
    if kind == "week" and isinstance(payload.get("week"), str):
        try:
            year, week = payload["week"].split("-W")
            datetime.date.fromisocalendar(int(year), int(week), 1)
        except ValueError:
            violations.append(("week-not-in-year", f"{payload['week']} is not an ISO week"))
    if kind == "identity":
        agent = payload.get("agent", {})
        if f"{agent.get('role')}.{agent.get('scope')}" != stream:
            violations.append(("identity-stream", "identity role and scope must match the stream"))
    return violations


def entry_judge(instance) -> list[tuple[str, str]]:
    problems = schema_codes(entry_validator, instance) + entry_violations(instance)
    try:
        jcs["jcs_dumps"](instance)
    except (TypeError, ValueError) as error:
        problems.append(("not-canonicalizable", f"entry is not I-JSON: {error}"))
    return problems


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

# --- revision pairs ----------------------------------------------------------
#
# Rules that relate a revision to the revision it supersedes. Each pair file
# holds {"predecessor": entry, "revision": entry}.


def entry_digest(entry: dict) -> str:
    canonical = jcs["jcs_dumps"](entry).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


ACK_MEMBERS = {"state", "acknowledged_at"}


def pair_violations(pair: dict) -> list[tuple[str, str]]:
    violations: list[tuple[str, str]] = []
    before, after = pair.get("predecessor", {}), pair.get("revision", {})
    for side, entry in (("predecessor", before), ("revision", after)):
        for code, message in entry_judge(entry):
            violations.append((f"{side}-invalid", f"{side}: {message}"))
    for member in ("stream", "record_id", "payload_contract"):
        if before.get(member) != after.get(member):
            violations.append(("identity-changed", f"{member} changes across revisions"))
    supersedes = after.get("supersedes", {})
    if supersedes.get("revision") != before.get("revision"):
        violations.append(("supersedes-revision", "supersedes.revision does not name the predecessor"))
    if supersedes.get("digest") != entry_digest(before):
        violations.append(("supersedes-digest", "supersedes.digest is not the predecessor's digest"))
    provenance = after.get("provenance", {})
    if provenance.get("actor_kind") == "agent" and provenance.get("actor") != after.get("stream"):
        # An agent writing outside its own stream is only ever acknowledging a handoff.
        if before.get("payload", {}).get("state") != "open":
            violations.append(("ack-predecessor-not-open", "only an open handoff can be acknowledged"))
        for member in ("classification", "labels", "links"):
            if before.get(member) != after.get(member):
                violations.append(("ack-metadata-changed", f"an acknowledgement may not change {member}"))
        before_rest = {k: v for k, v in before.get("payload", {}).items() if k not in ACK_MEMBERS}
        after_rest = {k: v for k, v in after.get("payload", {}).items() if k not in ACK_MEMBERS}
        if before_rest != after_rest:
            violations.append(("ack-payload-changed", "an acknowledgement may change only state and acknowledged_at"))
    return violations


for fixture in sorted((FIXTURES / "pairs/conforming").glob("*.json")):
    problems = pair_violations(load(fixture))
    if problems:
        fail(f"pair conforming {fixture.name}: {problems[0][1]}")
    else:
        ok(f"pair conforming {fixture.name}")
check_negatives("pair", FIXTURES / "pairs/negative", pair_violations)

# --- digest vectors (RFC 8785 JCS, sha256) -----------------------------------

vectors = load(VECTORS)
for vector in vectors["vectors"]:
    instance = load(FAMILY / vector["entry"])
    canonical = jcs["jcs_dumps"](instance).encode("utf-8")
    digest = "sha256:" + hashlib.sha256(canonical).hexdigest()
    if digest != vector["digest"]:
        fail(f"digest {vector['entry']}: {digest} != {vector['digest']}")
    elif len(canonical) != vector["canonical_length"]:
        fail(f"digest {vector['entry']}: canonical length {len(canonical)}")
    else:
        ok(f"digest {vector['entry']}")

for vector in vectors.get("canonicalization_vectors", []):
    canonical = jcs["jcs_dumps"](vector["value"]).encode("utf-8")
    if canonical.hex() != vector["canonical_utf8_hex"]:
        fail(f"canonicalization {vector['name']}: bytes differ")
    elif "sha256:" + hashlib.sha256(canonical).hexdigest() != vector["digest"]:
        fail(f"canonicalization {vector['name']}: digest differs")
    else:
        ok(f"canonicalization {vector['name']}")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)

print("\nagentic/memory v0 schemas, registry, dimension and fixtures: OK")
