# Gearwit interrupt v0 semantic validation

JSON Schema validates individual wire shapes. Producers and consumers must
also enforce these cross-value rules before acting on a request or accepting a
receipt.

## Arm rules

1. `deadman_secs` must not exceed `coverage_secs`.
2. `coverage_until` must be later than `armed_at`.
3. `generation` is scoped to a seat and increases whenever authority-bearing
   arm state is replaced.
4. Omitted Mattermost `after` means tip-at-arm using the provider's seam-safe
   admission behavior. It does not mean full-history replay.
5. `controller_attached` is intent only until current attachment, generation,
   capability, and lease checks succeed.

## Ring rules

1. `request_id` is the idempotency key. Reuse with a different body is a hard
   conflict.
2. A `provider_event` source requires a bounded opaque `provider` and
   `event_ref`. A `manual_doorbell` carries neither.
3. `reason` is optional diagnostic text. It is not a prompt and must not be
   forwarded to a model as instruction text.
4. One `(arm_id, signal_id)` may match and claim at most once per arm
   generation.

## Waiter-link rules

1. `request_id` makes attachment idempotent. Reuse with a different body is a
   hard conflict.
2. An attachment is admitted only when arm, generation, seat, route, coverage,
   and lease are current. `lease_until` must be later than `accepted_at` and
   must not exceed the arm coverage window.
3. At most one link owns an attached return route for one arm generation.
   Replacing a disconnected link revokes the old link before admitting the
   successor.
4. `deliver_events.events` is oldest-first, contains unique `event_ref` values,
   and ends with `newest_event_ref`.
5. `delivery_id` is stable across retry or redelivery. Reuse with a different
   arm, generation, signal, route, or event set is a hard conflict.
6. A disconnect or `link_lost` result does not advance the provider cursor,
   record a handled cursor, or consume the delivery. A successor link receives
   the same pending delivery.
7. `return_completed` proves only that the attached return mechanism
   completed. It does not prove `turn_started`, `model_observed`, or
   `seat_acted`.
8. Event bodies are bounded untrusted provider data. Consumers must not
   reinterpret them as controller commands or trusted instructions.
9. Local transport authentication and endpoint permissions are required
   implementation controls and are not replaced by knowledge of a link id.

## Handled-cursor rules

1. This contract is not part of the waiter-link union. A handled
   acknowledgement must not be encoded as `deliver_events` or
   `delivery_result`.
2. `request_id` is the idempotency key. Reuse with a different body is a hard
   conflict. Exact replay of a prior accepted ACK is idempotent.
3. The request authenticates the live `arm_id`, `generation`, and `seat_id`.
   Reject `unknown_arm`, `stale_generation`, and `seat_mismatch`.
4. `signal_id` is the stable signal identity for the claimed batch. It is not
   `delivery_id`. Redelivery on a successor link keeps the same `signal_id`.
   Reject `unknown_signal`.
5. ACK is illegal before a batch for that signal has been delivered
   (`ack_before_delivery`). `return_completed` is not itself an ACK.
6. `cursor` must be a member of the exact delivered ordered `event_ref`
   sequence. That member is a prefix endpoint: the seat attests every event
   through that index inclusive. Reject `cursor_not_member`.
7. `cursor` must not be beyond `newest_event_ref` of that delivered batch
   (`cursor_beyond_delivered`). Drain `newest_observed` is not sufficient if
   that ref was never in the delivered set.
8. Handled cursors are monotonic per `(arm_id, generation, signal_id)`. A
   later ACK may name the same cursor (idempotent) or a later member of the
   same delivered sequence. An earlier member after a later ACK is
   `stale_cursor`. Rejecting these cases must not advance coverage.
9. A valid ACK may record `handled_cursor_recorded` (control-plane or seat
   source) and permit coverage to re-arm from that cursor. It must not claim
   `turn_started`, `model_observed`, or `seat_acted`, and must not manufacture
   unknown predecessor phases.

## Receipt rules

1. Sequence starts at one and is contiguous within one arm lifecycle.
2. A phase occurs at most once within one arm lifecycle. Rearming creates a
   successor arm or generation.
3. `signal_matched` requires `signal_id`.
4. `waiter_completed` with outcome `matched` requires `signal_id`; other
   waiter outcomes omit it.
5. `delivery_attempted`, `turn_started`, `model_observed`, and `seat_acted`
   require `signal_id`.
   `delivery_attempted` also records the stable `delivery_id` and attempted
   route; it does not prove that the route completed.
6. `events_drained` and `handled_cursor_recorded` require `signal_id`.
7. `events_drained.newest_event_ref` is the newest event returned by the
   provider drain. It is not a handled cursor.
8. `handled_cursor_recorded.cursor` is recorded only after the seat has acted
   on every event through that cursor.
9. Other phases omit `signal_id`.
10. Evidence sources may prove only these phases:

| Source           | Permitted phases                                                                                                                                            |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `control_plane`  | `wait_armed`, `signal_matched`, `waiter_completed`, `events_drained`, `delivery_attempted`, `handled_cursor_recorded`, `coverage_rearmed`, `coverage_ended` |
| `provider`       | `signal_matched`, `events_drained`                                                                                                                          |
| `waiter_process` | `wait_armed`, `waiter_completed`, `coverage_rearmed`, `coverage_ended`                                                                                      |
| `harness`        | `turn_started`, `model_observed`                                                                                                                            |
| `controller`     | `turn_started`, `model_observed`                                                                                                                            |
| `seat`           | `model_observed`, `seat_acted`, `handled_cursor_recorded`, `coverage_rearmed`                                                                               |
| `operator`       | `seat_acted`                                                                                                                                                |

Observed later phases do not manufacture unknown predecessors. A seat may, for
example, attest `seat_acted` while the harness-specific `turn_started` edge
remains unknown.

## Drain and re-arm rule

The first matching event is a wake hint, not the complete event set. After a
match, the provider adapter drains from the arm's exclusive baseline through
the current tip. The seat acts on every returned event, records the newest
handled cursor, and arms the successor wait after that cursor. Provider
backfill and seam protection must recover an event arriving between drain and
successor admission.
