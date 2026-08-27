# Chanvoy daemon RPC v0 method catalog

## `wait_channels_v1`

`wait_channels_v1` waits on two through eight explicit channels under one
absolute deadline and returns the first eligible peer message. The method is a
new capability; it does not alter `wait_channel` or `wait_channel_v2`.

| Surface           | Contract                              |
| ----------------- | ------------------------------------- |
| JSON-RPC method   | `wait_channels_v1`                    |
| Parameters        | `wait_channels_v1.params.schema.json` |
| Successful result | `wait_channels_v1.result.schema.json` |
| Error detail      | `wait_channels_v1.error.schema.json`  |

### Capability and compatibility

Method presence is the capability gate. A daemon which does not implement the
method returns JSON-RPC method-not-found code `-32601`. A client must treat
that response as a hard capability failure (exit 2), advise the operator to
cycle an outdated daemon, and must not spawn multiple legacy waits, discard
arms, or retry through `wait_channel_v2`.

There is no separate capability payload in v0. Implementations must not invent
one or claim support based only on CLI version or daemon generation metadata.

### Parameters and pre-provider validation

Before provider I/O, the daemon must validate:

1. `arms` contains two through eight entries.
2. Every arm carries an explicit non-empty `team` and `channel`. Each is at
   most 256 code points in the schema and 256 UTF-8 bytes at runtime, before
   provider-specific validation.
3. No two arms resolve to the same canonical channel id. Schema
   `uniqueItems` rejects byte-identical duplicates; canonical duplication is
   an additional runtime invariant.
4. Every explicit `after` is non-empty, at most 256 code points in the schema
   and 256 UTF-8 bytes at runtime, and is bound to its arm's resolved channel.
5. `contains` and `pattern` are non-empty when present. Each source is at most
   256 UTF-8 bytes. JSON Schema `maxLength` is a code-point bound, so the byte
   bound remains mandatory runtime validation. The two filters combine with
   logical AND.
6. `pattern` compiles within the implementation's 64 KiB regex-size limit.
7. `timeout_secs` is greater than zero.

An omitted or null `after` means tip-at-arm with seam protection. An omitted
or null filter means that filter is inactive.

### Successful result

A successful daemon result contains:

- `mode: "fan_in"`;
- the canonical selector for every armed channel;
- `matched_channel`, which must equal exactly one entry in `channels`; and
- exactly one full shared `Message`.

The winner for initial backfill is the earliest eligible candidate ordered by
`(create_at, post_id, channel_id)`. At the live edge, the first eligible event
accepted by the daemon wins. No global Mattermost ordering is claimed.

### Error and CLI outcome mapping

The daemon retains the existing `{code, message}` JSON-RPC error detail.
Messages are constructed locally, bounded, and redacted: an arm-specific
message may name the requested `team/channel` selector and error class, but
must not include provider bodies, credentials, private URLs, or unrelated
channel ids.

|     Code | Meaning                                                             | CLI outcome                            |
| -------: | ------------------------------------------------------------------- | -------------------------------------- |
| `-32601` | method absent on an older daemon                                    | hard capability failure, exit 2        |
| `-32005` | all arms were healthy and silent until the shared deadline          | clean deadman, exit 1                  |
| `-32007` | invalid wait input                                                  | hard failure, exit 2                   |
| `-32008` | provider state remained unproven at the deadline                    | hard provider-degraded failure, exit 2 |
| `-32000` | other terminal resolution, binding, identity, or permission failure | hard failure, exit 2                   |

Only `-32005` may be projected by the CLI as `timeout: true`. A successful
RPC result is always a match. Hard failures must never carry
`timeout: true`.

The CLI match projection uses the successful result unchanged. Its clean
deadman projection is:

```json
{
  "mode": "fan_in",
  "timeout": true,
  "timeout_secs": 1200,
  "channels": [
    { "team": "org-example", "channel": "release-floor" },
    { "team": "org-example", "channel": "feature-brief" }
  ]
}
```

### All-or-nothing seam invariant

The daemon validates, subscribes once, resolves and binds all arms, snapshots
omitted baselines, backfills, then consumes live events. Failure of any arm
cancels the whole operation; no partial waiter remains.

An event delivered after subscription but before an arm's omitted-baseline
snapshot completes is retained and evaluated as post-arm activity. A later
snapshot must not erase it. Each retained event is evaluated at most once per
arm, and duplicate delivery cannot create duplicate results. The daemon
cancels the subscription and all losing arm state before every return.

The operation is cursor- and attention-neutral. It does not acknowledge,
post, mark read, or advance persistent state. The daemon's own posts never
match.

## `wait_channel_v3`

`wait_channel_v3` waits on one channel under an absolute deadline and
enforces **one active wait per profile daemon + canonical channel**. It
is a new capability; it does not alter `wait_channel`, `wait_channel_v2`,
or `wait_channels_v1`.

| Surface           | Contract                             |
| ----------------- | ------------------------------------ |
| JSON-RPC method   | `wait_channel_v3`                    |
| Parameters        | `wait_channel_v3.params.schema.json` |
| Successful result | `wait_channel_v3.result.schema.json` |
| Error detail      | `wait_channel_v3.error.schema.json`  |

### Capability and compatibility

Method presence is the capability gate. A daemon which does not implement
the method returns JSON-RPC method-not-found code `-32601`. A client that
claims single-waiter ownership must treat that response as a hard
capability failure (exit 2), advise the operator to cycle an outdated
daemon, and **must not** fall back to `wait_channel_v2` or `wait_channel`.

There is no separate capability payload in v0.

A new daemon that still serves `wait_channel` / `wait_channel_v2` must
pass those requests through the same in-memory registry with
`replace_wait_id = null`. Legacy clients gain refuse-default behavior
and cannot replace a wait.

### Parameters and pre-provider validation

Before provider I/O other than canonical resolve and explicit `--after`
binding, the daemon must validate:

1. `channel` is non-empty. Schema `maxLength` is a code-point bound; the
   runtime additionally enforces a 256 UTF-8 byte limit.
2. `timeout_secs` is greater than zero.
3. `contains` and `pattern` are non-empty when present. Each source is at
   most 256 UTF-8 bytes. `pattern` compiles within the implementation's
   64 KiB regex-size limit. The two filters combine with logical AND.
4. An explicit `after` is non-empty and is bound to the resolved channel
   before registry acquisition.
5. `replace_wait_id`, when present, is a non-empty string at most 64
   code points. A malformed, stale, absent, or other-channel value does
   not cancel anything; it is `wait_conflict_changed`.

An omitted or null `after` means tip-at-arm with seam protection after
the waiter is admitted. An omitted or null `replace_wait_id` is default
refusal if the key is already owned.

### Registry lifecycle

The registry is memory-only and keyed by **canonical channel id** inside
one profile daemon:

```text
key = (profile daemon, canonical channel_id)
```

It is not a host-global lock and is not persisted across daemon restart.

1. Validate timeout and filters.
2. Resolve the channel and bind any explicit `after`.
3. Acquire the registry key **before** subscribe or backfill.
4. A generation-checked scope guard releases the key on every terminal
   path: match, deadman, hard error, client disconnect, cancellation,
   panic/task abort, and daemon shutdown.
5. Default concurrent acquire on the same key returns `wait_already_active`.
6. `--replace-wait` is compare-and-replace on the current id only. On
   match, the daemon cancels the old waiter and waits up to **five
   seconds** (also bounded by any shorter remaining request deadline)
   for cleanup acknowledgement before admitting the new waiter.
7. The new waiter must not subscribe until that acknowledgement.
8. Unconfirmed cleanup returns `wait_replace_unconfirmed`, does not arm
   the new waiter, and leaves the old generation ownership-visible. A
   late old guard may release that generation but must never delete a
   newer admitted generation.

Different canonical channel ids may wait concurrently. Textual aliases
that resolve to the same channel id conflict. Fan-in multi-key
acquisition is out of scope for this method.

### Successful result

A successful daemon result contains the requested `channel`, exactly one
shared `Message`, and may include `wait_id` and `replaced_wait_id` as
optional diagnostics. It must not set `timeout` and must not omit the
triggering message.

The CLI match projection uses `messages[0].id` as the fire id. There is
no top-level match id.

### Error and CLI outcome mapping

|     Code | `data.class`               | CLI outcome                            |
| -------: | -------------------------- | -------------------------------------- |
| `-32601` | (none)                     | hard capability failure, exit 2        |
| `-32012` | `wait_replace_unconfirmed` | hard ownership failure, exit 2         |
| `-32011` | `wait_replaced`            | displaced waiter, exit 2               |
| `-32010` | `wait_conflict_changed`    | hard ownership failure, exit 2         |
| `-32009` | `wait_already_active`      | hard ownership failure, exit 2         |
| `-32008` | (none)                     | hard provider-degraded failure, exit 2 |
| `-32007` | (none)                     | hard input failure, exit 2             |
| `-32005` | (none)                     | clean deadman, exit 1                  |
| `-32000` | (none)                     | hard failure, exit 2                   |

Only `-32005` may be projected by the CLI as `timeout: true`. Ownership
codes are never deadman and never carry `timeout: true`.

Ownership `data` may name canonical team/channel, opaque wait ids, and
`started_at_ms`. It must not include filter text, baseline post ids,
message bodies, provider URLs, credentials, command lines, or pids.

The operation is cursor- and attention-neutral. Replacement and refusal
do not acknowledge, post, mark read, or advance persistent state.

## `wait_follow_v1`

`wait_follow_v1` is a process-held, single-channel wait. It binds once and
streams records conforming to `wait_follow_v1.event.schema.json` over one
long-lived local daemon connection. It is a new capability and does not alter
the one-shot `wait_channel_v3` method.

| Surface         | Contract                            |
| --------------- | ----------------------------------- |
| JSON-RPC method | `wait_follow_v1`                    |
| Parameters      | `wait_follow_v1.params.schema.json` |
| Stream record   | `wait_follow_v1.event.schema.json`  |
| Terminal result | `wait_follow_v1.result.schema.json` |
| Error detail    | `wait_follow_v1.error.schema.json`  |

Method presence is the capability gate. Method-not-found is exit 2; a client
must not emulate follow with legacy one-shot calls.

### Scope and transport

Version 1 accepts exactly one explicit channel. A client must reject fan-in
before daemon admission; it must not collapse per-arm anchors into the
document's scalar `tip`. Multi-channel follow requires a later document with
per-arm cursor semantics.

The daemon invokes the held-follow runner once. It must not implement follow
by repeatedly calling a first-match runner. One runner retains the same bind
across backlog and live bursts until deadline, cancellation, replacement, or a
terminal arm posture. The existing Chanvoy observer and event bus remain the
only provider observation path; this capability does not add a provider
socket, polling acknowledgement, or agent-wait wire kind.

Each burst is written before the runner asks for another burst. The write is
the backpressure boundary. Buffering all bursts until terminal, acknowledging
between bursts, or silently discarding same-instant events violates the
contract. Closing the client connection cancels the same runner and releases
its registry lease.

### Record order and cursor semantics

Every record carries `schema: "wait_follow_v1.event"` and the same opaque
`wait_id`. A valid stream contains:

1. exactly one `armed` receipt, written only after admission succeeds;
2. zero or more `backlog` or `live` records in observation order; and
3. at most one terminal `deadman`, `canceled`, `replaced`, or `failed` record.

The `armed` receipt is the first record. An eligible event observed in the same
turn as a terminal posture is emitted before the terminal record. No record
follows a terminal record.

An empty channel at arm has no provider post id. The armed record therefore has
no `tip`, and an internal empty-at-arm sentinel must never be projected as a
resumable `--after` value. When compare-and-replace admits the new waiter, its
armed record carries `replaced_wait_id`. The displaced waiter's terminal record
and terminal result carry `replaced_by_wait_id`.

Each backlog/live record contains exactly one message from the single armed
channel. Two quick posts therefore produce two ordered records on unchanged
binds; the adapter does not coalesce them. `tip` equals that message id and is
the exclusive `--after` baseline for a later new follow. Only backlog may set
`truncated` true. In that case, additional eligible messages remain for later
records in the same held follow; truncation never means discard.
The stream has no `matched_channel` field; the single selector is fixed by the
method parameters. Fan-in and per-arm projection are not v1.

### Terminal and CLI outcome mapping

| Record or condition            | CLI outcome                                     |
| ------------------------------ | ----------------------------------------------- |
| `deadman`                      | clean deadline, exit 1                          |
| `canceled` after local SIGINT  | interrupted, exit 130                           |
| `replaced`                     | displaced waiter, exit 2                        |
| `failed`                       | hard provider/ownership/daemon failure, exit 2  |
| capability/input/open failure  | no armed receipt; hard failure, exit 2          |
| later sink write/flush failure | close the daemon connection immediately, exit 2 |

Only `deadman` is a timeout. A hard failure must never be projected as a
timeout. `failed.reason_code` is a bounded local class and must not carry raw
provider detail. When the selected sink itself fails, a terminal record cannot
be guaranteed; connection closure is the fail-loud cancellation signal.

Pre-admission ownership errors retain the `wait_channel_v3` compare-and-replace
codes and bounded payloads: `-32009` already active, `-32010` conflict changed,
and `-32012` replacement cleanup unconfirmed. Capability, input, provider, and
other hard errors carry no free-form `data`. Confirmed displacement is a
`replaced` terminal record and terminal result, which the CLI maps to exit 2.

The CLI requires exactly one explicit sink: `--out PATH` or
`--follow-stdout`. It opens and validates `--out` before daemon admission:
append mode, regular file, no symlink following, and mode 0600. A sink-open
failure cannot acquire a wait lease. Later write or flush failure closes the
connection immediately so the daemon cancels the held runner and releases the
lease.

Filters, exclusive `--after`, self-post ignore, websocket-degraded admission,
single-waiter ownership, and compare-and-replace retain the `wait_channel_v3`
semantics. Follow is cursor- and attention-neutral: it does not acknowledge,
post, mark read, or advance persistent state.
