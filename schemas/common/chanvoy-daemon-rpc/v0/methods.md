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
