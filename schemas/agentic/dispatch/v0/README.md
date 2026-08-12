# agentic/dispatch v0 — dispatch contract family

Contracts for the dispatch runner's supervision seam:

| Artifact                                                     | Purpose                                                                                                 |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| [`run-envelope.schema.json`](run-envelope.schema.json)       | One supervised harness run, discriminated by `outcome`.                                                 |
| [`harness-profile.schema.json`](harness-profile.schema.json) | One lane's capability/posture evidence as data.                                                         |
| [`semantic-validation.md`](semantic-validation.md)           | Versioned semantic layer (`dispatch/v0-semantics 0.1.1`) for the invariants JSON Schema cannot express. |
| `fixtures/`                                                  | Synthetic-normative fixtures (see below).                                                               |

Validate the whole family:

```bash
python3 scripts/validate-dispatch-v0.py          # needs the jsonschema package
uv run --with jsonschema scripts/validate-dispatch-v0.py
make check-dispatch-v0   # also part of the default `make check` gate
```

## Layering (normative)

This repository holds **schemas and synthetic-normative fixtures only**.
Live operational state — a machine's current lane profiles, today's CLI
versions, routing eligibility — lives in the consuming runner repository
(or an evidence store), validated against these pinned schemas. The
canonical schema repo never tracks one installation's drift.

Fixtures are **engagement-blind**: every identity/engagement label is a
`fixture-*` placeholder, never a real engagement or client string. The
validator enforces this.

## Fail-closed rules (normative)

- Consumers MUST reject an envelope with a missing or unknown
  `envelope_schema`, and a profile with a missing or unknown
  `profile_schema`. v0 is the first pin; there is no version negotiation.
- Capability evidence expires as a **validity condition** (a runtime
  relation between the recorded `executable_version` + `platform` and a
  live probe), never a stored boolean. Consumers fail closed on mismatch
  or unprobeable executables (SEM-VC01).
- Harness-profile is authoritative evidence; routing is a non-escalating
  projection. A routing artifact may NEVER claim a more permissive
  posture than the profile evidence proves (SEM-R01/R02/R03) — consumers
  gate on this, not on prose.
- `verdict` is untrusted-until-revalidated against the schema bound by
  `verdict_schema_id` + `verdict_schema_sha256`.
- Profile re-derivation is a new immutable evidence record landed through
  human review; agents never self-clear a fence.

## Outcome ↔ runner-exit ↔ nullability (run-envelope)

`runner_exit` classes: 0 ok · 2 unschema'd output · 4 environment/config ·
5 supervised-harness failure.

| `outcome`           | `runner_exit` | Meaning                                                                                                                                                                                            | Nullability highlights (schema-enforced)                                                                                                                                                                                                                             |
| ------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `completed`         | 0, 2, 5       | Harness spawned and exited on its own. 0 = success (verdict accepted, or none requested); 2 = no schema-valid verdict accepted (`harness_exit` 0); 5 = harness nonzero exit or unreaped survivors. | `harness`, `harness_exit`, `harness_pgid`, `timeout_s` non-null; `timed_out`/`interrupted` false.                                                                                                                                                                    |
| `refused-pre-spawn` | 4             | Fail-closed posture/fence/evidence refusal; the harness was never spawned.                                                                                                                         | `harness` non-null; `posture_enforced` = `"none"` (never-spawned paths cannot claim an enforced posture); `harness_exit`/`harness_pgid`/`session_id`/`usage`/`num_turns`/`verdict`/`raw_text`/`rejected_verdict`/`parse_error` null; `group_reap` = `not_attempted`. |
| `config-fatal`      | 4             | Configuration/environment error (pre- or at-spawn).                                                                                                                                                | As refusal — including `posture_enforced` = `"none"` (an argv that never executed enforces nothing) — but `harness` may be null (selector never resolved; the raw request stays traced in `harness_requested`) and `timeout_s` may be null.                          |
| `timeout`           | 5             | Run exceeded its timeout; process group reaped.                                                                                                                                                    | `timed_out` true; `verdict` null; `group_reap` ∈ {cleared, cleared_after_sigkill, survivors}; `harness_exit` may be null (signal exit).                                                                                                                              |
| `interrupted`       | 5             | Wrapper received SIGINT/SIGTERM; group reaped.                                                                                                                                                     | `interrupted` true; otherwise as timeout (`timed_out` may also be true when both fired; interruption wins the discriminator).                                                                                                                                        |

### Verdict tri-state (when `verdict` is null)

| State                  | Discriminants                                                                                                                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| not requested          | `digests.schema_sha256` null (⇒ `verdict_schema_id`/`verdict_schema_sha256` null, SEM-E05)                                                                         |
| run never produced one | `outcome` ≠ `completed`, or `runner_exit` = 5                                                                                                                      |
| schema-failed          | `parse_error` non-null (`runner_exit` = 2); a validation-rejected object may appear in `rejected_verdict` (forensics only, size-bounded string, never re-promoted) |

`raw_text` is null whenever `verdict` is non-null (never both, SEM-E02):
raw text is forensic evidence _for the absence_ of an accepted verdict.

## Trust taxonomy (run-envelope, every field)

Labels: **W** wrapper-derived (established by the supervising wrapper
itself) · **H** harness-reported (the supervised process's own claim) ·
**E** env-recorded claim (copied from the wrapper's environment) ·
**W+H** hybrid (wrapper-authored container carrying harness-reported
content — treat the embedded content as untrusted even though the
field itself is wrapper-emitted).
**Non-W fields are untrusted inputs for security decisions.** Recorded
claims stay labeled claims until platform attestation evidence lands as a
separate versioned member.

| Field                                        | Label   | Notes                                                                                                                                                             |
| -------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `envelope_schema`                            | W       | Contract pin; consumers fail closed on missing/unknown.                                                                                                           |
| `producer`, `emitter_version`                | W       | Emitter identity; never conflated with the contract version.                                                                                                      |
| `outcome`, `runner_exit`                     | W       | The wrapper's own terminal classification.                                                                                                                        |
| `harness`                                    | W       | RESOLVED lane only (null unless the selector resolved; never `""`, never a raw unresolved selector).                                                              |
| `harness_requested`                          | W       | The raw selector as requested — traceability signal, honestly labeled a request, not a resolution.                                                                |
| `model_requested`                            | W       | Selector the wrapper passed through.                                                                                                                              |
| `cwd`, `brief_file`, `role_file`, `runlog`   | W       | Opaque path strings, forensics only.                                                                                                                              |
| `read_only`, `task_class`, `timeout_s`       | W       | Wrapper-resolved run configuration.                                                                                                                               |
| `digests.*`                                  | W       | Wrapper-computed SHA-256 of run inputs.                                                                                                                           |
| `started_at`, `ended_at`, `duration_ms`      | W       | Wrapper clocks.                                                                                                                                                   |
| `harness_exit`                               | W       | Observed child exit status.                                                                                                                                       |
| `timed_out`, `interrupted`, `group_reap`     | W       | Wrapper supervision facts.                                                                                                                                        |
| `posture_enforced`                           | W       | Derived from the enforcing flags the wrapper actually applied to the argv — never copied from config.                                                             |
| `harness_path`                               | W       | Wrapper's PATH/realpath resolution.                                                                                                                               |
| `harness_version`                            | **H**   | The binary's own `--version` claim; consumed only in the fail-closed comparison against recorded posture evidence.                                                |
| `harness_pgid`                               | W       | Spawn fact.                                                                                                                                                       |
| `session_id`, `usage`, `num_turns`           | H       | Harness telemetry.                                                                                                                                                |
| `verdict`                                    | H       | Untrusted-until-revalidated against the bound schema; wrapper-side validation is a gate, not a laundering step.                                                   |
| `verdict_schema_id`, `verdict_schema_sha256` | W       | Wrapper-computed binding to the requested schema.                                                                                                                 |
| `raw_text`                                   | H       | Size-bounded sensitive surface; forensics only.                                                                                                                   |
| `rejected_verdict`                           | **W+H** | Wrapper-performed serialization of harness-reported content; size-bounded, never re-promoted to `verdict`.                                                        |
| `stderr_tail`                                | **W+H** | Harness stderr when a harness ran; wrapper-authored refusal/fatal message on never-spawned paths. Size-bounded.                                                   |
| `parse_error`                                | **W+H** | Wrapper-authored message that may quote harness-reported content verbatim — quoted material is untrusted.                                                         |
| `env_identity.role/team/scope/engagement`    | E       | Recorded claims, not proofs (pre-attestation).                                                                                                                    |
| `env_identity.session_token_present`         | E       | **Presence-only boolean — NOT PROOF.** Never token material, never a hash. Kept for round-trip compatibility; the label, not deletion, is the over-trust control. |

Harness-profile fields are all evidence-record facts (wrapper/probe
derived at derivation time) except `fenced`/`fence_reason`, which mirror
routing state at derivation time and are referenced, not owned — routing
owns eligibility.

## Constructs beyond the portable core (per the structured-output policy, as amended)

These schemas are **tool-validated contract schemas**, never passed to a
vendor's structured-output enforcement. Per the amended platform policy
(strict vendor subset scoped to vendor-enforced schemas), they use the
portable core (objects/arrays/scalars, `enum`, all-properties-required,
`additionalProperties: false`) plus exactly the constructs below — each
justified, and each proven in both validators:

| Construct                         | Where           | Justification                                                                                                                                                                           |
| --------------------------------- | --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `allOf` + `if`/`then` + `const`   | both schemas    | The discriminated outcome model (a flat schema either fails every refusal envelope or over-nullabilizes the completed shape) and the profile's control↔posture/fence↔reason bindings. |
| `oneOf` (null unions over `$ref`) | both schemas    | Nullable-and-required fields whose non-null branch carries `pattern`/length constraints (digests, opaque paths).                                                                        |
| `$defs` / `$ref`                  | both schemas    | Shared shapes (digests, posture enum, timestamps) defined once.                                                                                                                         |
| `pattern`                         | both schemas    | SHA-256 hex, RFC 3339 shape, calendar dates — `format` alone is annotation-only in many validators.                                                                                     |
| `format`                          | run-envelope    | Annotation only (`date-time`); the enforced floor is the accompanying `pattern`.                                                                                                        |
| `minLength`/`maxLength`           | both schemas    | Null-not-empty (`harness`), and portable max bounds on sensitive surfaces (`raw_text` 262144, `rejected_verdict` 65536, `parse_error` 16384, `stderr_tail` 8192).                       |
| `minimum`                         | run-envelope    | Non-negative durations/counts, positive timeout/pgid.                                                                                                                                   |
| `minItems`/`maxItems`             | harness-profile | Posture-without-evidence rejection; bounded evidence-ref lists.                                                                                                                         |
| `const` (top-level pins)          | both schemas    | `envelope_schema`/`profile_schema` exact-$id fail-closed check; `validity_condition.kind`.                                                                                              |

**Proof of support (both validators):**

- Crucible validator — `python3 scripts/validate-dispatch-v0.py`
  (jsonschema, Draft 2020-12): lints both schemas and proves every
  conforming/negative fixture, which collectively exercise every construct
  above (see `fixtures/*/negative/expected.json` for the keyword each
  negative must fail on).
- Rust validator — the consuming runner repository embeds these pinned
  schemas and runs the same fixture suite through the `jsonschema` crate
  (Draft 2020-12) in its `make check` conformance tests; a fixture that
  passes here and fails there (or vice versa) turns that gate red.

## Fixtures

- `fixtures/run-envelope/{conforming,negative}/` and
  `fixtures/harness-profile/{conforming,negative}/` — JSON Schema layer.
  Negative sets include the known defect classes: stale experimental
  claim shape, posture-without-evidence, unknown property,
  harness-as-empty-string, missing/unknown `envelope_schema`.
- `fixtures/semantic/{conforming,negative}/` + `manifest.json` — shared
  semantic-layer fixtures (envelope invariants, validity-condition
  expiry, routing-projection divergence/escalation/fence-lift). Both this
  repo's validator and downstream conformance gates consume the same
  files, keyed by the manifest's stated rule ids.
- Every negative fails **for its stated reason** (`expected.json` /
  `manifest.json`), not merely somehow.
