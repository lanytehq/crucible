# Mission v0 semantic validation layer

**Layer id:** `mission/v0.1-semantics`

**Layer version:** `0.2.8`

**Applies to:**

- `https://schemas.3leaps.dev/agentic/mission/v0.1/mission-record.schema.json`
- `https://schemas.3leaps.dev/agentic/mission/v0.1/mission-control.schema.json`
- `https://schemas.3leaps.dev/agentic/mission/v0.1/driver-capabilities.schema.json`
- `https://schemas.3leaps.dev/agentic/mission/v0.1/lifecycle-event.schema.json`

JSON Schema checks individual document shapes. This layer defines identity,
ordering, transition, capability, and trust invariants across a mission
history. Any violated rule fails the history.

Semantic fixtures use this closed top-level form:

```json
{
  "kind": "mission-history",
  "mission": {},
  "events": [],
  "driver_capabilities": [],
  "before": {},
  "after": {},
  "required_capabilities": []
}
```

`before` and `after` are optional recovery snapshots used only to test durable
identity preservation. `required_capabilities` is an optional closed list used
to test driver gating. `control_records` is an optional closed list of mutating
control bindings (`operation`, `idempotency_key`, `request_fingerprint`,
`original_result_hash`, `evidence_ref`) used to test SEM-A05. No other
top-level fixture fields are accepted.

The validator requires every fixture named in
`fixtures/semantic/manifest.json`, rejects manifest drift, and requires every
negative fixture to produce its declared rule identifier.

## Identity and chronology

| Rule    | Invariant                                                                                                                                         |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-M01 | Every mission, attempt, event, report, and request UUID is canonical lower-case UUID v4.                                                          |
| SEM-M02 | Every timestamp is a parseable RFC 3339 instant; mission update, attempt end, event, and capability-expiry ordering never moves backward.         |
| SEM-M03 | `evidence_chain_id` equals `mission_id`; every event carries that mission ID.                                                                     |
| SEM-M04 | Event sequences begin at one, increase by exactly one, and preserve the previous-entry hash link.                                                 |
| SEM-M05 | `event_type` equals `payload.type`; the record terminal hash equals the terminal lifecycle entry hash.                                            |
| SEM-M06 | Mission `updated_at` is at or after the final recorded lifecycle time. A terminal attempt `ended_at` is at or after every event for that attempt. |

## Authority and durable identity

| Rule    | Invariant                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-A01 | A `created` mission has no authorizer. Authorization is bound only by a later verified event before an attempt becomes running. That event's authorizer `kind`, `subject`, and `attestation_ref` plus `authorization_ref` must equal the durable attested principal (`kind`, `subject`, `attestation.trust_ref`) and decision. An unrelated attestation cannot authorize.                                                                                                                                              |
| SEM-A02 | Mission initiator, supervisor, and operating role never change across recovery, resume, or relaunch.                                                                                                                                                                                                                                                                                                                                                                                                                   |
| SEM-A03 | No field name at any depth may carry raw token, passphrase, password, credential, secret, private key, or chain-of-thought material.                                                                                                                                                                                                                                                                                                                                                                                   |
| SEM-A04 | A verified-attestation or operator-command event has a non-null evidence reference; harness or driver claims never establish authority. `cancel_requested.source.subject` must equal the authorized principal (`authorizer.subject`, or `initiator.subject` when still created).                                                                                                                                                                                                                                       |
| SEM-A05 | Every mutating control request has a caller-stable idempotency key, a canonical `request_fingerprint`, and an `original_result_hash`. The fingerprint hashes the request with those two hash fields omitted; the result hash hashes the original result with `original_result_hash` omitted. One key maps to one fingerprint and one original result. Reuse of the key with a different fingerprint or result hash is rejected. Each `cancel_requested` evidence ref must name the matching `control_records` binding. |

## Mission and attempt transitions

| Rule    | Invariant                                                                                                                                                                                         |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-T01 | Mission phase transitions follow the state graph below; terminal phases have no outgoing transition.                                                                                              |
| SEM-T02 | Attempt state transitions follow the attempt graph below; terminal attempts have no outgoing transition.                                                                                          |
| SEM-T03 | At most one attempt is live (`starting`, `running`, `waiting`, `unresponsive`, or `cancelling`).                                                                                                  |
| SEM-T04 | `current_attempt_id` identifies that live attempt; it is null when no attempt is live.                                                                                                            |
| SEM-T05 | A terminal mission has no live attempt and carries the matching terminal reason and evidence hash.                                                                                                |
| SEM-T06 | Attempt ordinals are unique and contiguous. `initial` has no predecessor; `resumes` and `relaunches` name an earlier attempt.                                                                     |
| SEM-T07 | A successor attempt may be created only after its predecessor is terminal and recorded as `replaced`.                                                                                             |
| SEM-T08 | Attempt generations are unique and increasing. Driver observations and operations must carry the current server-issued generation and fence; stale generations cannot change authoritative state. |
| SEM-T09 | Attempt-scoped lifecycle events resolve to a durable attempt. `attempt_created` binds id, ordinal, generation, recovery relation, and predecessor to that record.                                 |

Mission graph:

```text
created -> active | suspended | cancelled | failed
active -> waiting | recovery_pending | suspended | completed | cancelled |
          failed | deadline_exceeded | budget_exhausted
waiting -> active | recovery_pending | suspended | cancelled | failed |
           deadline_exceeded | budget_exhausted
recovery_pending -> active | suspended | cancelled | failed |
                    deadline_exceeded | budget_exhausted
suspended -> active | cancelled | failed | deadline_exceeded |
             budget_exhausted
terminal -> no transition
```

Attempt graph:

```text
starting -> running | cancelling | failed | crashed | timed_out | lost
running -> waiting | unresponsive | cancelling | completed | failed |
           crashed | timed_out | lost
waiting -> running | unresponsive | cancelling | completed | failed |
           crashed | timed_out | lost
unresponsive -> running | cancelling | replaced | failed | crashed | timed_out | lost
cancelling -> cancelled | failed | crashed | timed_out | lost
terminal -> no transition
```

## Driver capability evidence

| Rule    | Invariant                                                                                                                                                                                       |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-D01 | Capability names occur once per report; support fidelity and availability remain separate dimensions.                                                                                           |
| SEM-D02 | Evidence is current only when the observed executable version and platform match its validity condition and the observation has not expired. Missing or unprobeable live evidence fails closed. |
| SEM-D03 | A mission cannot enter `active`, and a restored attempt cannot enter `running`, when a required capability is unavailable, unknown, lossy, or unsupported.                                      |
| SEM-D04 | A recovery relation of `resumes` requires usable `resume`; `relaunches` requires usable `identify`, `cancel`, and `terminal_status`.                                                            |

## Cancel, lease, and restart (Wave 3)

| Rule    | Invariant                                                                                                                                                                                                                                                                                                                       |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-C01 | `cancel_requested` is not terminal. Every `protocol_cancel_attempted` and `process_termination_attempted` requires an earlier same-fence attested `cancel_requested`, independent of outcome or mission phase. An attempt may become `cancelled` only after protocol `interrupted` or process `cleared`.                        |
| SEM-C02 | Protocol-confirmed cancel is `turn/completed` `interrupted` bound to the exact attempt id, attempt generation, lease generation, harness thread, and harness turn. `request_accepted`, `unavailable`, `timeout`, and `unrelated_completion` cannot fold `cancelled`. Created-with-no-attempt may fold after `cancel_requested`. |
| SEM-C03 | Process fallback folds `cancelled` only on membership-verified `cleared` with kernel provenance and the current attempt fence. `kill_dispatched`, `survivors`, and `unknown` are non-success.                                                                                                                                   |
| SEM-C05 | Deadman silence is `unresponsive`. It is never inferred as `crashed`, `timed_out`, or `lost`.                                                                                                                                                                                                                                   |
| SEM-C06 | A terminal mission history ends with `mission_terminal` whose phase, reason, and hash bind the record.                                                                                                                                                                                                                          |
| SEM-C08 | A fence may emit at most one `cancel_requested` receipt. Exact replay produces no new edge.                                                                                                                                                                                                                                     |
| SEM-C09 | When attempts exist, mission `cancelled` must bind a cancelled attempt with matching proof.                                                                                                                                                                                                                                     |
| SEM-C10 | Each cancelled attempt has a kernel-observed `attempt_state_changed` to `cancelled` after its same-fence `cancel_requested` and matching proof. Cause is `protocol_interrupt` when the proof is protocol `interrupted`, or `process_exit` when the proof is membership `cleared`. `mission_terminal` follows that edge.         |
| SEM-L01 | Lease fences are reconstructed at-event. A mutation whose prior generation does not match the running projection at that point is stale. Historic lower generations that already folded are valid.                                                                                                                              |
| SEM-L03 | At most one overdue `restart_reconciled` receipt exists per attempt and running lease generation.                                                                                                                                                                                                                               |
| SEM-L04 | When `lease_policy.enabled` is false, attempt lease runtime fields are null. When enabled and live, wall deadlines and last observation are present.                                                                                                                                                                            |
| SEM-L05 | `last_observation_source` is never seat or Chanvoy activity.                                                                                                                                                                                                                                                                    |
| SEM-L06 | Result deadlines derive from `observed_at` plus policy. Process probe may move deadman only.                                                                                                                                                                                                                                    |
| SEM-L07 | `deadman_fired` / `expired` / overdue restart occur at or after the running deadline at that point.                                                                                                                                                                                                                             |
| SEM-L08 | Each tick prior tuple matches the running projection; the final projection matches the attempt record (generation, both deadlines, last observation).                                                                                                                                                                           |
| SEM-L09 | Kernel clock cannot renew. Fire/expire and restart receipts are kernel-observed.                                                                                                                                                                                                                                                |
| SEM-L10 | `renewed` must move a permitted clock later. A consumed `(attempt, generation, kind, deadline)` fire/expire cannot be emitted again.                                                                                                                                                                                            |
| SEM-L11 | An enabled lease requires a durable `lease_started` generation-1 anchor before later ticks.                                                                                                                                                                                                                                     |
| SEM-P01 | Codex protocol evidence stays driver/harness assurance. Process-membership probes stay kernel assurance. Reading bytes does not upgrade provenance.                                                                                                                                                                             |

See `wave3-transition-evidence.md` for the full matrix.

## Versioning

Adding a semantic rule is a minor version bump. Changing or removing a rule is
a major version bump. Consumers must reject a manifest whose layer identifier
or version differs from the implementation.
