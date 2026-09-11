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
   `mention`, when true, is a further AND: only posts that mention **this
   bot** complete the wait. The provider adapter uses one canonical
   `mentions_bot` decision (trusted current-bot mention metadata when
   present, else an exact `@username` token; `@bot-suffix` is not a
   match). Non-matches advance the internal scan cursor only and are
   never match tips. Self-posts never match. The same helper applies to
   push, REST backfill, polling, reconnect, `--dm`, fan-in, and `--inbox`.
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

## `wait_dm_v1`

`wait_dm_v1` waits on one direct-message conversation selected by **exact
username**. Username resolution and create-if-missing (`GET
/users/username/{username}` then `POST /channels/direct`) run **inside**
daemon wait admission under the same absolute deadline as baseline bind,
ownership, subscribe/backfill, and block. It is a new capability and does
not alter `wait_channel_v3` or `wait_follow_v1`.

| Surface           | Contract                        |
| ----------------- | ------------------------------- |
| JSON-RPC method   | `wait_dm_v1`                    |
| Parameters        | `wait_dm_v1.params.schema.json` |
| Successful result | `wait_dm_v1.result.schema.json` |
| Error detail      | `wait_dm_v1.error.schema.json`  |

### Capability and compatibility

Method presence is the capability gate. Method-not-found (`-32601`) is a
hard capability failure (exit 2). A client must not fall back to
`wait_channel_v3`, `wait_channel_v2`, or a CLI preflight that resolves the
username then issues a second wait RPC.

There is no separate capability payload in v0. Do not add optional fields
to the deny-unknown `wait_channel_v3` / `wait_follow_v1` documents.

### Parameters and pre-provider validation

Before username lookup, direct-channel creation, baseline work, or wait
ownership, the daemon must validate:

1. `username` is non-empty, at most 256 UTF-8 bytes, and is **not** a
   waitable-peer shape: RFC UUID, Mattermost user-id (26-character id),
   or `{uid}__{uid}` DM channel name.
2. `username` is not the current bot identity (daemon-bound username).
   Do not trim or case-fold into a different identity. Do not search by
   display name.
3. `timeout_secs` is greater than zero.
4. `contains` and `pattern` follow `wait_channel_v3` filter rules.
5. An explicit `after` is a post id on that DM conversation (not an
   inbox cursor) and is bound after the DM channel exists, before
   registry acquisition.
6. There is no `team` and no `channel` field. Unknown properties refuse.

Unknown, inaccessible, or self targets use **one** diagnostic class:
"not a waitable peer". Creation of the DM channel sends no message.

Identity for `POST /channels/direct` is the daemon-bound bot user id
(no extra `whoami` required when already bound). Call order is exact
username lookup, then `POST /channels/direct`.

### Registry lifecycle

After direct-channel admission the daemon uses the **existing**
first-match engine and the **canonical channel id** ownership key from
`wait_channel_v3`. A legacy positional wait on the same DM name
(`{uid}__{uid}`) and `wait_dm_v1` for that peer conflict or
compare-and-replace as the same owner.

A peer post that races create-if-missing and admission is delivered by
the same subscribe → baseline/backfill rules as an existing channel.

### Successful result

A successful result contains `peer_username`, canonical `dm_name`, the
echoed `channel` (the DM name), and exactly one shared `Message`.
Callers must not reverse a channel UUID.

Error and CLI outcome mapping match `wait_channel_v3` (`-32601`
capability, `-32005` clean deadman, `-32007` input, `-32008` provider,
ownership `-32009` through `-32012`).

## `wait_dm_follow_v1`

`wait_dm_follow_v1` is the held-follow form of `wait_dm_v1`. Admission
is the same username resolve/create transaction. After the DM channel
is bound, the daemon invokes the existing held-follow runner once.
Stream records remain `wait_follow_v1.event` (that document is not
widened). The terminal result names `peer_username` and `dm_name`.

| Surface         | Contract                               |
| --------------- | -------------------------------------- |
| JSON-RPC method | `wait_dm_follow_v1`                    |
| Parameters      | `wait_dm_follow_v1.params.schema.json` |
| Stream record   | `wait_follow_v1.event.schema.json`     |
| Terminal result | `wait_dm_follow_v1.result.schema.json` |
| Error detail    | `wait_dm_follow_v1.error.schema.json`  |

Method-not-found is exit 2. A client must not emulate follow with
legacy one-shot calls or with `wait_follow_v1` after a CLI preflight.

`--dm` is mutually exclusive with positional `CHANNEL`, repeated
`--channel` fan-in, `--after-channel`, and `--team`. CLI help: "wait
for a DM from this user; do not pass a channel id."

## `wait_inbox_v1`

`wait_inbox_v1` waits on **any direct message** to this bot, including a
direct channel created while the wait is armed. It is a new capability.
Do not add inbox fields to `wait_channel_v3`, `wait_follow_v1`,
`wait_dm_v1`, or `wait_dm_follow_v1`.

| Surface           | Contract                           |
| ----------------- | ---------------------------------- |
| JSON-RPC method   | `wait_inbox_v1`                    |
| Parameters        | `wait_inbox_v1.params.schema.json` |
| Successful result | `wait_inbox_v1.result.schema.json` |
| Error detail      | `wait_inbox_v1.error.schema.json`  |

### Capability and compatibility

Method presence is the capability gate. Method-not-found (`-32601`) is a
hard capability failure (exit 2). A client must not fall back to N stacked
`wait_channel_v3` / `wait_dm_v1` calls, to `wait_channels_v1` fan-in, or to
the truncated human `list_dms` helper.

There is no team, channel, or username selector. Unknown properties refuse.

### Inbox cursor

`--after` is a versioned, bounded **inbox cursor**, not a Mattermost post
id. One post id is not an exclusive cursor across independent DM
histories, and `(create_at, post_id)` lexical order can miss a later
arrival in the same millisecond with a lower random id.

The opaque CLI/RPC string:

1. Starts with `inv1.` so it cannot be confused with a 26-character
   Mattermost post id.
2. Is at most 32 KiB encoded.
3. Binds the admitting **profile** and **daemon bot user id**.
4. Carries the provider watermark (`create_at`) plus the bounded set of
   already-observed post ids at that watermark (at most 128).
5. Is observation-only: it is not a capability token and never contains
   message bodies or a channel catalog.

Decode and fully validate the cursor **before** provider I/O. Wrong
profile, wrong bot, malformed, oversize, or unprovable cursors fail as
`cursor_uncertain` (`-32007`). A value shaped like a Mattermost post id
fails as input with a diagnostic that names the distinction: inbox
cursor, not Mattermost post id.

A decoded cursor is still **proven** against the authenticated type-`D`
catalog and bounded history after catalog/peer resolution and **before**
ownership/bind. A future watermark, a positive watermark with an empty
observed-id set, a positive watermark with no authenticated post at that
exact `create_at`, a missing or contradictory equal-watermark id, or any
other history-unprovable anchor fails `cursor_uncertain`. It must not
expire as a clean deadman. Only the valid empty cursor (watermark 0, no
observed ids) is admitted without that history proof. Honest cursors
never encode `watermark > 0` with an empty observed-id set; every
non-empty observed-id set must still be proven at that exact watermark.

Ordering is `(create_at, observed-id set at watermark)`. A candidate is
new when `create_at` is greater than the watermark, or equal to the
watermark and not in the observed-id set. The cursor advances only after
the corresponding record crosses the CLI sink boundary.

### Subscribe, catalog, and reconnect

With no `--after`, the daemon must subscribe to inbox-relevant push
**before** catalog and baseline work, snapshot the complete authenticated
type-`D` catalog, establish per-channel tips, then drain the buffered
push stream. Tip-at-arm must not have a catalog-to-subscribe seam.

Discovery paginates authenticated provider type `D` to completion and
excludes group DMs (`G`). The human `dms` helper (one unpaged request,
truncated to 20) is not a complete catalog. Exceeding 1,024 direct
channels in one catalog, or 512 retained backfill candidates total,
fails `capacity` rather than silently truncating. An exactly-full last
page is not proof of completion; the next page must be observed empty or
the wait fails closed.

WebSocket admission and reconnect catch-up include direct channels while
inbox is armed even when they are not in `monitored_channels`. A new-DM
post may be buffered while bounded channel-type/peer lookup completes.
Lookup failure, catalog overflow, provider lag, or an exhausted history
bound fails `capacity` or `cursor_uncertain`. It must not become a clean
deadman or a truncation-success.

### Ownership

Inbox occupies one profile-wide **DM-class** ownership key. While it is
live, `wait_dm_v1` and a positional wait that resolves to type `D`
conflict. Conversely, an active DM-specific wait blocks inbox admission.
`--replace-wait` / `replace_wait_id` may compare-and-replace **only**
another inbox wait id. It must not silently replace a peer-specific or
positional DM waiter (`wait_conflict_changed`).

Self-posts never wake. First matching peer post wins.

### Successful result

A successful result labels `peer_username`, `dm_name`, `matched_post_id`,
and `next_inbox_cursor` as four distinct fields. `matched_post_id` equals
the single `messages[0].id`. The cursor must not equal that post id and
must not match `^[a-z0-9]{26}$`. Callers must not reverse a channel UUID
and must not treat the cursor as a post id.

Error and CLI outcome mapping match `wait_channel_v3` (`-32601`
capability, `-32005` clean deadman, `-32007` input including
`cursor_uncertain` and `capacity`, `-32008` provider, ownership `-32009`
through `-32012`). Caps (1,024 DMs / 512 backfill / 32 KiB cursor / 128
equal-watermark ids) are fail-closed implementation defaults, not product
SLAs, and are not help-text promises.

## `wait_inbox_follow_v1`

`wait_inbox_follow_v1` is the held-follow form of `wait_inbox_v1`.
Admission, catalog, ownership, and cursor rules are the same. The daemon
invokes one inbox observer / waitprims registration, not N stacked
channel waits. Stream records are **`wait_inbox_follow_v1.event`**. Do
not widen or overload `wait_follow_v1.event` (`tip == sole message.id` is
false for an inbox cursor).

| Surface         | Contract                                  |
| --------------- | ----------------------------------------- |
| JSON-RPC method | `wait_inbox_follow_v1`                    |
| Parameters      | `wait_inbox_follow_v1.params.schema.json` |
| Stream record   | `wait_inbox_follow_v1.event.schema.json`  |
| Terminal result | `wait_inbox_follow_v1.result.schema.json` |
| Error detail    | `wait_inbox_follow_v1.error.schema.json`  |

Method-not-found is exit 2. A client must not emulate follow with one-shot
inbox calls or with `wait_follow_v1` after discovering DM names.

### Record order and cursor semantics

Every record carries `schema: "wait_inbox_follow_v1.event"` and the same
opaque `wait_id`. A valid stream contains:

1. exactly one `armed` receipt, written only after admission succeeds;
2. zero or more `backlog` or `live` records in observation order; and
3. at most one terminal `deadman`, `canceled`, `replaced`, or `failed`
   record.

The `armed` receipt has no post-id `tip` and no inbox cursor. Each
backlog/live record contains exactly one message and labels
`peer_username`, `dm_name`, `matched_post_id`, and `next_inbox_cursor`
separately. `matched_post_id` equals that message id. `next_inbox_cursor`
is the sink-acknowledged cursor after that record and is never a post id.
Live delivery is never truncated. Only backlog may set `truncated` true.

Terminal records carry only the last **proven** cursor as `inbox_cursor`
(omitted when none was sink-acknowledged). A later sink write/flush
failure closes the daemon connection immediately (exit 2) and must not
publish or persist a cursor beyond the last delivered record. Replay from
that last delivered cursor must recover the undelivered record.

`failed.reason_code` is a bounded local class. Inbox adds `capacity`
alongside `cursor_uncertain`. Raw provider detail is never stream data.

`--inbox` is mutually exclusive with positional `CHANNEL`, repeated
`--channel` fan-in, `--dm`, `--after-channel`, and `--team`. CLI help:
"wait for any DM to this bot; do not pass a channel id."
