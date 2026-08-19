# Wave 3 transition and evidence matrix

Companion to `mission/v0.1`. This table is the semantic contract for lease,
deadman, and `mission.cancel`. JSON Schema cannot express these rows alone.

Clocks: persist RFC3339 wall instants (`lease_expires_at`, `deadman_at`,
`last_observed_at`). Live elapsed work uses a monotonic clock (runtime). Seat
or Chanvoy activity never renews either wall deadline.

`lease_generation` is a lease epoch / CAS fence. It is not attempt
`generation`. Stale `lease_generation` cannot apply timer or cancel work.

`sysprims` process-tree kill is a fallback behind capability
`local_process_termination`. It is not a new IPC channel.

## Protocol-confirmed (literal)

A successful JSON-RPC response to Codex `turn/interrupt` is
`request_accepted` only.

**Protocol-confirmed** cancellation requires a matching `turn/completed` for
the exact `threadId` + `turnId` with status `interrupted`, bound to the
current attempt `generation` and fence. That outcome is recorded as
`protocol_cancel_attempted.outcome = interrupted`.

Missing active turn, unsupported interrupt, RPC timeout, or an unrelated
`turn/completed` stay non-terminal (`unavailable`, `timeout`,
`unrelated_completion`). The idle App Server process after a confirmed
interrupt is cleanup, not proof of the interrupted turn.

## Who renews what

| Clock              | Renewed by                                                                                                                   | Never renewed by                 |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| `lease_expires_at` | Kernel, when it still holds supervision and accepts a `driver_event` or `harness_event` for this attempt                     | Seat, Chanvoy, operator presence |
| `deadman_at`       | Kernel: `last_observed_at + lease_policy.deadman_seconds` on an accepted `driver_event`, `harness_event`, or `process_probe` | Seat, Chanvoy, operator presence |

`kernel_clock` may fire a `lease_tick` edge (expired / deadman_fired). It
does not pretend to be harness liveness.

## Assurance

| Evidence                             | `source.kind`                           | Allowed `assurance`                      |
| ------------------------------------ | --------------------------------------- | ---------------------------------------- |
| Codex protocol bytes                 | `driver_reported` or `harness_reported` | `claim` or `driver_observed`             |
| Process-membership probe / tree reap | `kernel_observed`                       | `kernel_observed` or `resource_attested` |
| Operator `mission.cancel`            | `operator_command`                      | `resource_attested` with evidence_ref    |

The kernel reading a driver byte stream does not upgrade it to
`kernel_observed`.

`lease_tick` is emitted only on a semantic edge (`renewed`, `deadman_fired`,
`expired`). Scheduler wakes with no edge produce no receipt. A second
`lanyte serve` restart after an overdue reconcile emits no new
`restart_reconciled` receipt.

## Matrix

| Trigger                                         | Clock / source                     | Attempt edge                            | Mission edge                              | Evidence                                                           | Retry                        | Restart                                                      |
| ----------------------------------------------- | ---------------------------------- | --------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------ | ---------------------------- | ------------------------------------------------------------ |
| `mission.cancel` on `created`, no attempt       | operator_command / attested caller | none                                    | `created → cancelled`                     | `cancel_requested` (null attempt) then `mission_terminal`          | exact idempotent replay      | no-op; already terminal                                      |
| `mission.cancel` on live attempt                | operator_command                   | `* → cancelling`                        | stay live or later `cancelled`            | `cancel_requested` only; **not** terminal                          | replay returns same progress | resume `cancelling` pipeline; stale lease_generation dropped |
| JSON-RPC `turn/interrupt` accepted              | driver_reported                    | stay `cancelling`                       | unchanged                                 | `protocol_cancel_attempted` `request_accepted`                     | may wait for completed       | same; do not fold                                            |
| Matching `turn/completed` `interrupted`         | driver_reported / harness_reported | `cancelling → cancelled`                | `* → cancelled`                           | `protocol_cancel_attempted` `interrupted` (thread+turn+generation) | no                           | persist terminal; second restart no new receipt              |
| No turn id / unsupported interrupt              | driver_reported                    | stay `cancelling`                       | unchanged                                 | `protocol_cancel_attempted` `unavailable`                          | take fallback policy         | do not claim protocol success                                |
| Interrupt RPC timeout                           | driver_reported                    | stay `cancelling`                       | unchanged                                 | `protocol_cancel_attempted` `timeout`                              | take fallback policy         | same                                                         |
| Unrelated `turn/completed`                      | driver_reported                    | stay `cancelling`                       | unchanged                                 | `protocol_cancel_attempted` `unrelated_completion`                 | take fallback policy         | same                                                         |
| `sysprims` kill sent                            | kernel_observed                    | stay `cancelling`                       | unchanged                                 | `process_termination_attempted` `kill_dispatched`                  | wait for membership          | non-success; not `cancelled`                                 |
| Membership-verified tree empty                  | kernel_observed                    | `cancelling → cancelled`                | `* → cancelled`                           | `process_termination_attempted` `cleared`                          | no                           | persist terminal                                             |
| Survivors after kill                            | kernel_observed                    | stay `cancelling` or `lost`             | maybe `recovery_pending`                  | `process_termination_attempted` `survivors`                        | policy                       | non-success                                                  |
| Reap outcome unknown                            | kernel_observed                    | stay `cancelling` or `lost`             | maybe `recovery_pending`                  | `process_termination_attempted` `unknown`                          | policy                       | non-success                                                  |
| Deadman silence (`now >= deadman_at`)           | kernel_clock                       | `running\|waiting → unresponsive`       | `recovery_pending`                        | `lease_tick` `deadman_fired`                                       | observe again                | reconcile once if overdue                                    |
| Lease wall expiry (`now >= lease_expires_at`)   | kernel_clock                       | `* → timed_out` when policy says so     | `recovery_pending` or `deadline_exceeded` | `lease_tick` `expired`                                             | no silent success            | reconcile once                                               |
| Accepted driver/harness observe                 | driver_event / harness_event       | stay live; may `unresponsive → running` | stay live                                 | `lease_tick` `renewed` only if a deadline moved                    | n/a                          | restore runtime from disk                                    |
| Observed exit/signal                            | process_probe or driver            | `* → crashed` or truthful terminal      | `recovery_pending` or `failed`            | attempt_state_changed; not `unresponsive`                          | n/a                          | persist terminal                                             |
| Transport uncertainty                           | driver_reported                    | `* → lost`                              | `recovery_pending`                        | no quiet success                                                   | retry observe                | persist `lost`                                               |
| Unauthorized cancel                             | missing attestation                | no edge                                 | no edge                                   | reject; no lifecycle fold                                          | n/a                          | n/a                                                          |
| Stale `expected_revision` or `lease_generation` | caller / timer                     | no edge                                 | no edge                                   | reject                                                             | refresh                      | drop stale work                                              |
| Exact cancel replay                             | same idempotency key+body          | no new edge                             | no new edge                               | return original progress                                           | n/a                          | n/a                                                          |
| First serve restart, overdue lease              | kernel_clock                       | apply one edge                          | apply one edge                            | one `restart_reconciled` `overdue=true`                            | n/a                          | second restart: no receipt                                   |

Fold `cancelled` only from: (1) created-with-no-attempt after `cancel_requested`,
(2) protocol `interrupted` as defined above, or (3) process `cleared`.
