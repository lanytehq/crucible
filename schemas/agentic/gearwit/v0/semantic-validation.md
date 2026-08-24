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

## Receipt rules

1. Sequence starts at one and is contiguous within one arm lifecycle.
2. A phase occurs at most once within one arm lifecycle. Rearming creates a
   successor arm or generation.
3. `signal_matched` requires `signal_id`.
4. `waiter_completed` with outcome `matched` requires `signal_id`; other
   waiter outcomes omit it.
5. `turn_started`, `model_observed`, and `seat_acted` require `signal_id`.
6. `events_drained` and `handled_cursor_recorded` require `signal_id`.
7. `events_drained.newest_event_ref` is the newest event returned by the
   provider drain. It is not a handled cursor.
8. `handled_cursor_recorded.cursor` is recorded only after the seat has acted
   on every event through that cursor.
9. Other phases omit `signal_id`.
10. Evidence sources may prove only these phases:

| Source           | Permitted phases                                                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `control_plane`  | `wait_armed`, `signal_matched`, `waiter_completed`, `events_drained`, `handled_cursor_recorded`, `coverage_rearmed`, `coverage_ended` |
| `provider`       | `signal_matched`, `events_drained`                                                                                                    |
| `waiter_process` | `wait_armed`, `waiter_completed`, `coverage_rearmed`, `coverage_ended`                                                                |
| `harness`        | `turn_started`, `model_observed`                                                                                                      |
| `controller`     | `turn_started`, `model_observed`                                                                                                      |
| `seat`           | `model_observed`, `seat_acted`, `handled_cursor_recorded`, `coverage_rearmed`                                                         |
| `operator`       | `seat_acted`                                                                                                                          |

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
