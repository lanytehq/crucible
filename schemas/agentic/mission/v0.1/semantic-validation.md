# Mission v0 semantic validation layer

**Layer id:** `mission/v0.1-semantics`

**Layer version:** `0.2.3`

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
to test driver gating. No other top-level fixture fields are accepted.

The validator requires every fixture named in
`fixtures/semantic/manifest.json`, rejects manifest drift, and requires every
negative fixture to produce its declared rule identifier.

## Identity and chronology

| Rule    | Invariant                                                                                                                                 |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-M01 | Every mission, attempt, event, report, and request UUID is canonical lower-case UUID v4.                                                  |
| SEM-M02 | Every timestamp is a parseable RFC 3339 instant; mission update, attempt end, event, and capability-expiry ordering never moves backward. |
| SEM-M03 | `evidence_chain_id` equals `mission_id`; every event carries that mission ID.                                                             |
| SEM-M04 | Event sequences begin at one, increase by exactly one, and preserve the previous-entry hash link.                                         |
| SEM-M05 | `event_type` equals `payload.type`; the record terminal hash equals the terminal lifecycle entry hash.                                    |

## Authority and durable identity

| Rule    | Invariant                                                                                                                                                                          |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-A01 | A `created` mission has no authorizer. Authorization is bound only by a later verified event before an attempt becomes running.                                                    |
| SEM-A02 | Mission initiator, supervisor, and operating role never change across recovery, resume, or relaunch.                                                                               |
| SEM-A03 | No field name at any depth may carry raw token, passphrase, password, credential, secret, private key, or chain-of-thought material.                                               |
| SEM-A04 | A verified-attestation or operator-command event has a non-null evidence reference; harness or driver claims never establish authority.                                            |
| SEM-A05 | Every mutating control request has a caller-stable idempotency key. Replaying the same key and content returns the original result; reusing it with different content is rejected. |

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
| SEM-C01 | `cancel_requested` is not terminal. An attempt may become `cancelled` only after protocol `interrupted` or process `cleared`.                                                                                                                                                                                                   |
| SEM-C02 | Protocol-confirmed cancel is `turn/completed` `interrupted` bound to the exact attempt id, attempt generation, lease generation, harness thread, and harness turn. `request_accepted`, `unavailable`, `timeout`, and `unrelated_completion` cannot fold `cancelled`. Created-with-no-attempt may fold after `cancel_requested`. |
| SEM-C03 | Process fallback folds `cancelled` only on membership-verified `cleared` with kernel provenance and the current attempt fence. `kill_dispatched`, `survivors`, and `unknown` are non-success.                                                                                                                                   |
| SEM-C05 | Deadman silence is `unresponsive`. It is never inferred as `crashed`, `timed_out`, or `lost`.                                                                                                                                                                                                                                   |
| SEM-C06 | A terminal mission history ends with `mission_terminal` whose phase, reason, and hash bind the record.                                                                                                                                                                                                                          |
| SEM-L01 | `lease_generation` is an attempt-scoped fence. A later event on that attempt with a lower generation, or a mutation whose fence is not the attempt's current lease generation, cannot apply.                                                                                                                                    |
| SEM-L03 | At most one overdue `restart_reconciled` receipt exists per attempt and lease generation. A second application of that same overdue transition is a no-op.                                                                                                                                                                      |
| SEM-L04 | When `lease_policy.enabled` is false, attempt lease runtime fields are null. When enabled and live, wall deadlines and last observation are present.                                                                                                                                                                            |
| SEM-L05 | `last_observation_source` is never seat or Chanvoy activity.                                                                                                                                                                                                                                                                    |
| SEM-P01 | Codex protocol evidence stays driver/harness assurance. Process-membership probes stay kernel assurance. Reading bytes does not upgrade provenance.                                                                                                                                                                             |

See `wave3-transition-evidence.md` for the full matrix.

## Versioning

Adding a semantic rule is a minor version bump. Changing or removing a rule is
a major version bump. Consumers must reject a manifest whose layer identifier
or version differs from the implementation.
