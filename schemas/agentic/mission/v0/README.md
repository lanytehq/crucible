# Mission contract family v0

This family defines the durable mission domain above replaceable harness
attempts. It is the contract boundary for mission records, handler payloads,
driver capability evidence, and append-only lifecycle evidence.

## Files

| File                              | Purpose                                                                |
| --------------------------------- | ---------------------------------------------------------------------- |
| `mission-record.schema.json`      | Durable mission projection and bounded attempt history                 |
| `mission-control.schema.json`     | Create/show/list handler requests and results inside COMMAND channel 1 |
| `driver-capabilities.schema.json` | Time-bounded driver support fidelity and availability evidence         |
| `lifecycle-event.schema.json`     | Append-only, hash-linked lifecycle evidence with explicit provenance   |
| `semantic-validation.md`          | Cross-record and transition rules JSON Schema cannot express           |

`mission-control` is not a transport envelope and does not allocate another
IPC channel. A transport consumer first validates the existing COMMAND
envelope and then validates its mission handler payload against this family.

## Field map

| Contract        | Field group          | Fields                                                                                     |
| --------------- | -------------------- | ------------------------------------------------------------------------------------------ |
| Mission record  | Identity             | `mission_id`, `revision`, `goal`, `policy_id`                                              |
| Mission record  | Authority            | `initiator`, `authorizer`, `authorization_ref`, `supervisor`, `operating_role`             |
| Mission record  | Lifecycle            | `phase`, `terminal_reason`, `created_at`, `updated_at`, `deadline_at`                      |
| Mission record  | Deferred policy      | `lease_policy`, `budget_policy`, `recovery_policy`, `recovery_point_ref`                   |
| Mission record  | Execution projection | `harness_selection`, `attempts`, `current_attempt_id`                                      |
| Mission record  | Evidence             | `evidence_chain_id`, `terminal_entry_hash`                                                 |
| Attempt         | Durable identity     | `attempt_id`, `ordinal`, `generation`, `fencing_token_sha256`                              |
| Attempt         | Recovery             | `recovery_relation`, `predecessor_attempt_id`                                              |
| Attempt         | Observation          | `state`, `driver_id`, `harness_session_id`, timestamps, terminal reason, evidence ref      |
| Mission control | Replay/CAS           | `request_id`, `idempotency_key`, `expected_revision`                                       |
| Mission control | Handler              | `kind`, `operation`, closed operation-specific `body`                                      |
| Driver report   | Identity/validity    | report/driver identity, versions and digests, platform, observation/expiry, evidence ref   |
| Driver report   | Support              | independent availability plus per-operation fidelity, observation, enforcement, and replay |
| Lifecycle event | Chain                | mission/event IDs, sequence, previous/current hash, observed/recorded timestamps           |
| Lifecycle event | Trust                | typed source, producer version, assurance, evidence ref, closed typed payload              |

## Trust boundaries

- The server binds `initiator`, `authorizer`, `supervisor`, and
  `operating_role` from verified authority. A create request cannot supply
  those fields.
- `authorizer` identifies who approved; `authorization_ref` identifies the
  immutable decision. Neither substitutes for the other.
- Attestation objects are references to already verified evidence. Raw bearer
  tokens, passphrases, credentials, and chain-of-thought are never persisted.
  The record retains only verified claims and digests for context, token, and
  verification policy.
- A harness session identifier is operational evidence, not identity or
  authority proof.
- Driver and harness reports are claims. Kernel observations and verified
  attestations carry stronger provenance, but consumers still apply the
  semantic layer.
- Raw attempt fencing capabilities are never persisted. The mission projection
  carries only a generation and token digest; stale generations cannot mutate
  authoritative state.
- `mission.show` and `mission.list` return only records visible to the verified
  caller. List order is stable by creation instant then mission UUID; cursors
  are opaque and bound to that filtered snapshot.
- Mission records and lifecycle entries are committed atomically by storage
  implementations. The mission UUID is the evidence-chain key.
- A cancellation request is not a terminal observation. Implementations only
  emit terminal `cancelled` after the applicable termination evidence is
  recorded; uncertain loss remains non-success evidence.

## Wave 1 surface

The first consumer implements `mission.create`, `mission.show`, and
`mission.list`. A newly created record is in `created`, has revision zero,
contains no attempts, and has no authorizer. Lease, deadman, budget, driver,
and recovery execution fields may be null or disabled; their runtime
semantics are intentionally deferred.

## Validation

Run:

```sh
make check-mission-v0
```

The gate checks Draft 2020-12 schemas, conforming and negative fixtures, the
versioned semantic fixture manifest, and all cross-record rules. It never
soft-skips when the `jsonschema` dependency is unavailable.

Schema additions and semantic changes follow the repository schema bump
policy. Consumers must pin the exact schema identifier and semantic layer
version they implement.
