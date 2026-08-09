# Dispatch v0 semantic validation layer

**Layer id:** `dispatch/v0-semantics`
**Layer version:** `0.1.2`
**Applies to:**
`https://schemas.3leaps.dev/agentic/dispatch/v0/run-envelope.schema.json`,
`https://schemas.3leaps.dev/agentic/dispatch/v0/harness-profile.schema.json`

JSON Schema cannot express cross-field relations (timestamp ordering, the
verdict tri-state, digest binding, routing↔profile non-escalation). Those
invariants are defined **once, here**, as a versioned semantic layer with
shared fixtures under `fixtures/semantic/` that every implementation
consumes — so the schema repository's validator and any consumer's
conformance gate cannot "both conform" while disagreeing.

An implementation of this layer:

1. Declares the layer id + version it implements.
2. Runs every rule below against its inputs; **any violated rule fails the
   instance** (fail-closed).
3. Passes the shared fixture suite: every fixture in
   `fixtures/semantic/conforming/` yields zero violations; every fixture in
   `fixtures/semantic/negative/` yields a violation set **containing the
   rule id stated for it in `fixtures/semantic/manifest.json`**.
4. Additionally runs the envelope rules over
   `fixtures/run-envelope/conforming/` (all must pass).

Some outcome↔flag relations are already enforced by the schema's
conditional blocks; rules marked _(schema-enforced, re-check)_ are
re-stated here for validator independence and have no semantic-only
fixture (a violating instance cannot be schema-valid).

## Fixture envelope forms

Semantic fixtures are JSON objects discriminated by `kind`:

| `kind`               | payload                                                                                                                                                                                                    | rules exercised |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `envelope`           | `{ "kind": "envelope", "envelope": <run-envelope instance> }`                                                                                                                                              | SEM-E\*         |
| `profile-live`       | `{ "kind": "profile-live", "profile": <harness-profile instance>, "live": { "version": <string\|null>, "platform": <string\|null> } }`                                                                     | SEM-VC\*        |
| `routing-projection` | `{ "kind": "routing-projection", "profile": <harness-profile instance>, "routing": { "write_denial": ..., "fenced": ..., "fence_reason": ..., "posture_evidence": { "version": ..., "platform": ... } } }` | SEM-R\*         |

The `routing` member carries the shared-key projection of one routing lane
entry (shape mirrors the runner's routing configuration `harnesses.<lane>`
block).

## Envelope rules (single instance)

| Rule    | Invariant                                                                                                                                                                                                                                                           |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-E01 | `ended_at >= started_at` (RFC 3339 instant comparison).                                                                                                                                                                                                             |
| SEM-E02 | `verdict != null` ⇒ `raw_text == null`. Never both — raw text is forensic evidence _for the absence_ of an accepted verdict.                                                                                                                                        |
| SEM-E03 | `verdict != null` ⇒ `parse_error == null`.                                                                                                                                                                                                                          |
| SEM-E04 | `verdict != null` ⇒ `verdict_schema_id != null` and `verdict_schema_sha256 != null` (a verdict is never unbound from the schema it was validated against).                                                                                                          |
| SEM-E05 | `verdict_schema_sha256 != null` ⇔ `digests.schema_sha256 != null`, and when both are non-null they are equal. Likewise `verdict_schema_id != null` ⇔ `digests.schema_sha256 != null`.                                                                               |
| SEM-E06 | `group_reap == "survivors"` ⇒ `runner_exit != 0`. Unreaped survivors are never a success.                                                                                                                                                                           |
| SEM-E07 | `runner_exit == 2` ⇒ `verdict == null` and `digests.schema_sha256 != null` and `harness_exit == 0`. Exit class 2 is exactly "the harness succeeded but no schema-valid verdict was accepted".                                                                       |
| SEM-E08 | `outcome == "completed"` and `runner_exit == 0` and `digests.schema_sha256 != null` ⇒ `verdict != null`. A schema-requested run cannot succeed without an accepted verdict.                                                                                         |
| SEM-E09 | `rejected_verdict != null` ⇒ `verdict == null` and `parse_error != null`. A rejected verdict is forensics only and is never re-promoted.                                                                                                                            |
| SEM-E10 | `timed_out == true` ⇒ `outcome ∈ {timeout, interrupted}`; `interrupted == true` ⇒ `outcome == "interrupted"`. _(schema-enforced, re-check)_                                                                                                                         |
| SEM-E11 | `outcome == "completed"` and `runner_exit == 5` ⇒ `harness_exit != 0` or `group_reap == "survivors"`.                                                                                                                                                               |
| SEM-E12 | `outcome == "completed"` and `runner_exit == 0` ⇒ `harness_exit == 0` and `group_reap != "survivors"`.                                                                                                                                                              |
| SEM-E13 | When `group_reap_evidence` is **present**: `group_reap == "not_attempted"` ⇔ `group_reap_evidence == "not_applicable"` (biconditional). When **absent**, consumers MUST treat evidence as `unknown` (never `membership_verified`); producers SHOULD emit the field. |
| SEM-E14 | When `group_reap_evidence` is present and `group_reap ∈ {cleared, cleared_after_sigkill}` ⇒ evidence ∈ `{membership_verified, kill_dispatched}`. Pairing cleared\* with `unknown` or `not_applicable` is invalid (unproven / greenwash success).                    |
| SEM-E15 | When `group_reap_evidence` is present and `group_reap == "survivors"` ⇒ evidence ∈ `{membership_verified, unknown}`. `kill_dispatched` or `not_applicable` with survivors is invalid.                                                                               |

**Producer obligation (normative):** `group_reap_evidence` is **path-emitted** — set by the code path that established `group_reap`, from what that path observed. Never inferred solely from `cfg(unix)` / build platform.

## Validity-condition rules (profile + live probe)

| Rule     | Invariant                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-VC01 | Under `validity_condition.kind == "executable-version-platform-match"`, the evidence **holds** iff `live.version == executable_version` and `live.platform == platform`. When it does not hold — including `live.version == null` (unprobeable) — consumers MUST fail closed: treat the lane as posture `"none"` and ineligible for read-only routes. Recording a fresh probe result never updates the record in place; re-derivation is a new immutable evidence record via human-reviewed change. |

## Routing-projection rules (profile + routing lane entry)

Posture strength order: `none (0) < deny-rules (1) < sandbox (2)`.

| Rule    | Invariant                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-R01 | **Structural subset (machine-checked equality of shared keys):** `routing.write_denial == profile.write_denial.control`; `routing.fenced == profile.fenced`; `routing.posture_evidence.version == profile.executable_version`; `routing.posture_evidence.platform == profile.platform`; and when fenced, `routing.fence_reason == profile.fence_reason`. A MISSING shared key in the routing projection is a mismatch (fail-closed) — absence is never equality.                                                                         |
| SEM-R02 | **Non-escalation:** `strength(routing.write_denial) <= strength(profile.write_denial.control)`, and not (`profile.fenced` and not `routing.fenced`). A routing projection with `fenced` MISSING counts as not-fenced here — omitting the fence key on a fenced profile IS a fence lift (fail-closed). Routing may NEVER claim a more permissive/more-confining-than-proven posture than the profile evidence: dual truth here is an access-control bug class, and the gate fails on escalation even where SEM-R01's equality is relaxed. |
| SEM-R03 | **Eligibility projection:** a lane may be eligible for read-only reviewer routes only if `profile.posture ∈ {sandbox, deny-rules}` and `profile.fenced == false` and `routing.fenced == false` (explicitly false — a routing projection with fence state MISSING is treated as claiming eligibility, so this rule fires whenever the profile is ineligible; missing state never launders a claim).                                                                                                                                       |

## Consumer obligations (normative, not fixture-checkable)

- Fail closed on missing/unknown `envelope_schema` / `profile_schema`.
- Treat `verdict` as untrusted-until-revalidated against the bound schema.
- Treat all harness-reported and env-recorded fields as untrusted inputs
  for security decisions (see the trust-taxonomy table in `README.md`).

## Versioning

Semantic rules version with this document (`0.1.2` — patch: SEM-E13..E15
for optional `group_reap_evidence` invariants; prior `0.1.1` was R-rules
missing-key fail-closed). Adding a rule is a
minor bump; changing or removing one is a major bump and follows the
schema-bump policy. Implementations MUST reject a fixture manifest whose
`semantic_layer` field does not match the layer id + version they
implement.
