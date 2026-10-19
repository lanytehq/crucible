---
title: ADR-0014 Transport Reliability Policy
description: Cross-cutting retry, backoff, jitter, timeout, and connection management rules for all point-to-point communication paths
---

# ADR-0014: Transport Reliability Policy

Status: Accepted

## Context

Lanyte has multiple communication paths that share the same reliability concerns:

- **LLM provider backends** (Claude, Grok, OpenAI) — HTTP to external APIs
- **Peer IPC** (mlvoy, chanvoy, future peers) — UDS or HTTP to co-located services
- **External service bridges** (IMAP/SMTP via mlvoy, Mattermost/Slack via chanvoy) — HTTP/TCP to third-party providers
- **Internal RPC** (gateway ↔ orchestrator, orchestrator ↔ state store) — UDS within the instance

Each path has independently evolved its own retry, timeout, and backoff behavior. The Claude and Grok adapters now share similar patterns (exponential backoff, jitter, 500-class baseline), but this convergence happened through code review, not policy. Without a governing ADR, each new path will re-derive these decisions, and divergence will accumulate.

ADR-0010 addendum section G established retry norms for LLM adapters specifically. This ADR elevates those norms to a cross-cutting policy and extends coverage to timeouts, TLS, connection management, streaming, idempotency, and observability.

### Forces

- **Herd behavior**: Multiple agents retrying simultaneously against a degraded upstream amplifies load. Jitter is not optional.
- **Billing risk**: Retrying non-idempotent requests against LLM providers can cause duplicate billing. Retry eligibility must be explicit.
- **Test determinism**: Retry behavior with real jitter is non-deterministic. Tests need a seeded path.
- **Operational visibility**: Without consistent retry logging, diagnosing "why did this take 12 seconds" requires adapter-specific investigation.
- **Security surface**: TLS, certificate validation, and credential handling in transport are trust-boundary decisions.

## Decision

The following policies are **required defaults with narrow override room**. A backend or peer path may diverge from a specific default only when the divergence is documented in that component's code and justified by a provider constraint. Divergence from the structural rules (e.g., "jitter is required") is not permitted without a follow-on ADR.

### 1. Scope

This ADR governs:

| Path class            | Examples                                      | Transport                     |
| --------------------- | --------------------------------------------- | ----------------------------- |
| LLM provider backends | Claude, Grok, OpenAI adapters                 | HTTPS to external API         |
| Peer bridges          | mlvoy (IMAP/SMTP), chanvoy (Mattermost/Slack) | HTTP/TCP to external provider |
| Inter-service IPC     | gateway ↔ orchestrator, orchestrator ↔ state  | UDS or local TCP              |
| Control plane calls   | lanyte-attest daemon, health checks           | UDS or local HTTP             |

Excluded:

- **Non-idempotent writes without replay protection.** A mail send (`gate_token`-guarded), a Mattermost post, or any operation that causes externally visible side effects must not be retried unless the protocol provides idempotency keys or the operation is explicitly documented as safe to replay.
- **User-facing interactive flows.** CLI commands that prompt for input are not governed by automatic retry.

### 2. Retry Eligibility

#### Retryable

| Signal                                    | Rationale                                   |
| ----------------------------------------- | ------------------------------------------- |
| Connect failure / DNS resolution failure  | Transient network issue                     |
| Request timeout (no response received)    | Upstream may not have processed the request |
| HTTP 429 (Too Many Requests)              | Explicit rate limit; retry after backoff    |
| HTTP 500 (Internal Server Error)          | Often transient during partial outages      |
| HTTP 502 (Bad Gateway)                    | Upstream proxy failure                      |
| HTTP 503 (Service Unavailable)            | Upstream overloaded                         |
| HTTP 504 (Gateway Timeout)                | Upstream proxy timeout                      |
| HTTP 529 (Overloaded, Anthropic-specific) | Provider-specific overload signal           |

#### Non-retryable

| Signal                              | Rationale                                              |
| ----------------------------------- | ------------------------------------------------------ |
| HTTP 400 (Bad Request)              | Malformed request; retrying won't fix it               |
| HTTP 401 / 403 (Auth failure)       | Credentials are wrong; retrying amplifies lockout risk |
| HTTP 404 (Not Found)                | Resource doesn't exist                                 |
| HTTP 422 (Validation failure)       | Application-level rejection                            |
| Content filter / policy rejection   | Model-level refusal; deterministic                     |
| Invalid model / contract errors     | Configuration error                                    |
| JSON parse failure on response body | Adapter or provider bug; not transient                 |

#### Server Retry-After

When a `429` response includes a `Retry-After` header, the specified delay **overrides** the local backoff calculation for that attempt. The jitter is still added on top. If `Retry-After` specifies a delay longer than the maximum per-attempt sleep cap, the cap applies — the adapter should not sleep indefinitely on a server's instruction.

### 3. Backoff Algorithm

**Exponential backoff with bounded jitter.**

```
sleep_duration = min(base_delay * 2^(attempt-1), max_per_attempt_sleep) + jitter
```

For HTTP 500 specifically, `base_delay_500` is used instead of `base_delay`, with a floor of `base_delay` (whichever is larger). Rationale: 500 often indicates a broader upstream issue where immediate retry adds load to an already-struggling service.

#### Required defaults

| Parameter               | Default | Override room                                                                                                                                                  |
| ----------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `max_attempts`          | 3       | May increase to 5 for peer IPC on local transport. Must not exceed 5 without ADR amendment.                                                                    |
| `base_delay`            | 1s      | May decrease to 100ms for local UDS paths where latency budget is tight.                                                                                       |
| `base_delay_500`        | 3s      | May increase. Must not decrease below `base_delay`.                                                                                                            |
| `max_per_attempt_sleep` | 30s     | May decrease. Must not increase without ADR amendment.                                                                                                         |
| `total_retry_budget`    | 90s     | The sum of all retry sleeps for a single request must not exceed this. If the budget is exhausted, fail immediately. May decrease for latency-sensitive paths. |

### 4. Jitter Policy

Jitter is **required** on all retry paths. Retrying without jitter is a policy violation — it creates correlated retry storms when multiple agents hit the same upstream.

| Parameter       | Default                                | Rule                                                                                                                                 |
| --------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `max_jitter`    | 250ms                                  | Additive. Added to the computed backoff delay.                                                                                       |
| Jitter mode     | Additive bounded                       | Jitter is `rand(0, max_jitter)`, added to backoff. Not full-jitter (which replaces backoff).                                         |
| Production seed | Per-process entropy                    | Must include at least: process ID, current time, and a per-instance counter. Must not use a fixed seed in production.                |
| Test seed       | Deterministic                          | Tests must be able to supply a fixed `jitter_seed` for reproducibility. The jitter generator must accept an optional seed parameter. |
| Generator       | Dependency-free xorshift or equivalent | Security-grade randomness is not required. The generator must produce visually uniform distribution across the jitter range.         |

### 5. Timeouts

| Parameter             | Default | Scope                                                                                                                      |
| --------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------- |
| `connect_timeout`     | 10s     | TCP/TLS handshake. Applies to all paths.                                                                                   |
| `request_timeout`     | 60s     | Total time for a non-streaming request (connect + send + receive).                                                         |
| `stream_idle_timeout` | 30s     | Maximum silence between SSE events or stream chunks. Not a whole-request timeout — streaming requests may run for minutes. |
| `shutdown_timeout`    | 5s      | Grace period for in-flight requests during process shutdown. After this, connections are dropped.                          |

**Streaming vs unary distinction:** `request_timeout` applies to `complete()` (unary). For `stream()`, only `connect_timeout` and `stream_idle_timeout` apply. A streaming request has no whole-request timeout — the stream runs until `Done`, error, or drop.

**Cancellation:** Dropping a stream handle must abort the underlying transport promptly (within one event-loop tick). Adapters must not leak background tasks or connections after the consumer drops the stream. This is enforced by CT-5 (conformance test).

### 6. Idempotency and Replay

| Rule                                     | Detail                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Semantically read-only requests          | May be retried, but the caller must accept that a transport-level timeout does not prove the upstream failed to process the request. LLM completions are semantically read-only (they produce output but don't mutate caller-visible state), but provider-side effects (billing, server-side tool execution, web search) may still occur on a retry after an ambiguous failure. Adapters retry these because the alternative — failing on every transient timeout — is worse, but the duplicate-execution risk is accepted, not absent. |
| Side-effecting requests                  | Must not retry unless the protocol provides idempotency keys or the operation has documented replay safety.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Ambiguous transport failures             | When a request times out or the connection breaks after the request was fully sent, the adapter cannot know whether the upstream processed it. For LLM completions, retry is permitted because the cost of duplicate execution (extra billing, redundant tool calls) is lower than the cost of failing. For side-effecting operations (sends, posts, mutations), retry is forbidden unless the protocol guarantees idempotency.                                                                                                         |
| `previous_response_id` (Grok)            | Continuation semantics. The follow-up request is idempotent with respect to the response chain — safe to retry.                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `gate_token` operations (mlvoy, chanvoy) | Not safe to retry without checking whether the gated action completed. The peer must provide a status query or the caller must accept at-most-once semantics.                                                                                                                                                                                                                                                                                                                                                                           |
| Partial stream failure                   | If a streaming response fails mid-stream after emitting events, the adapter must surface the error through the stream's `Result::Err` path. The orchestrator decides whether to re-request — the adapter does not automatically retry a partially-consumed stream.                                                                                                                                                                                                                                                                      |

### 7. TLS Transport

| Rule                         | Detail                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Off-host traffic             | TLS required. No exceptions for "internal" traffic that crosses a network boundary.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Minimum version              | TLS 1.2. Prefer 1.3 where supported.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Certificate validation       | Required. System CA store by default.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Hostname verification        | Required. No `danger_accept_invalid_hostnames`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Custom CA / enterprise proxy | Must be supported for deployment behind enterprise proxies. The mechanism depends on the TLS backend: `reqwest` with `native-tls` respects system env vars (`SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`); `reqwest` with `rustls` requires explicit certificate loading via the client builder (e.g., `reqwest::Certificate::from_pem`). Adapters must document which TLS backend they use and provide a configuration path (env var, config key, or CLI flag) for injecting custom CA certificates. Adapter code must not disable certificate validation as a workaround for custom CA needs. |
| Loopback / dev / test        | Plaintext allowed only for `127.0.0.1` / `::1` / UDS paths. Mock servers in tests may use plaintext HTTP on loopback.                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

### 8. Connection Management

| Parameter                | Default                                                                                                                        | Rationale                                        |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| `pool_max_idle_per_host` | 8                                                                                                                              | Sized for concurrent streaming + sync requests.  |
| Keepalive                | reqwest/hyper default (HTTP/2 with keep-alive)                                                                                 | Don't disable unless provider requires HTTP/1.1. |
| Retry across connections | Retries may reuse pooled connections or establish new ones. No special handling required — reqwest handles this transparently. |
| DNS refresh              | Not explicitly managed. Connection pool eviction on idle timeout handles stale DNS for long-running processes.                 |

### 9. Streaming-Specific Rules

1. **Drop = abort.** Dropping a stream handle must cancel the underlying HTTP response and any spawned tasks within one event-loop tick.
2. **No automatic reconnect.** If a stream fails mid-way, the adapter surfaces the error. The orchestrator decides whether to re-request. Silent reconnect risks duplicate output.
3. **Backpressure.** The default channel policy is **bounded** with a documented queue depth and overflow strategy (backpressure or drop-oldest). LLM adapter streams are an explicit exception: they may use unbounded channels because output rates are bounded by model inference speed (not network bandwidth). Any non-LLM streaming path (peer bridges, IPC event streams) must use bounded channels unless it documents why unbounded buffering is safe for its specific producer rate profile.
4. **Partial results.** Events emitted before a mid-stream error are valid and already consumed by the orchestrator. The error applies to the remainder of the stream, not retroactively to prior events.

### 10. Observability

#### Required logging on retry

Each retry attempt must log (at `WARN` level):

- Attempt number and max attempts
- HTTP status code or error class
- Computed sleep duration (backoff + jitter)
- Whether `Retry-After` was honored
- Request target (URL path, not query parameters or body)

#### Redaction rules

- API keys, bearer tokens, and authorization headers must never appear in logs.
- Request/response bodies must not be logged at `WARN` or `INFO`. Debug-level body logging must redact fields matching `*key*`, `*token*`, `*secret*`, `*password*`.

#### Required metrics (when metrics infrastructure is available)

- `request_attempts_total` — counter by path, outcome (success/retryable_failure/terminal_failure)
- `request_duration_seconds` — histogram by path, including retry time
- `retry_after_honored_total` — counter of times `Retry-After` was used
- `stream_cancellation_total` — counter of streams dropped before `Done`

#### Trace correlation

- Each outbound request lifecycle must have an internal `request_id` (or equivalent correlation field) that appears in all log lines and metrics for that request, including retries. This must not be an API key or session token.
- The `request_id` is for **internal observability only**. It must not be transmitted on the wire to third-party providers unless the target protocol explicitly supports or benefits from a client-supplied correlation identifier (e.g., a provider-defined `X-Request-Id` header). Leaking internal correlation state off-box exposes tracing topology and may conflict with provider contracts or future signature schemes.

### 11. Test Requirements

1. **Deterministic retry tests.** Use fixed `jitter_seed` to make retry timing reproducible. Every adapter must have at least one test that verifies retry behavior with a mock server returning retryable errors.
2. **Mock transport coverage.** Each retryable class (429, 500, 502, 503, 504) and each non-retryable class (401, 400) must have a unit test verifying correct behavior (retry vs immediate failure).
3. **Drop/cancel test.** CT-5 pattern: verify that dropping a stream releases adapter resources (tasks, connections). Use `#[cfg(test)]` atomic counters.
4. **Live-provider smoke tests.** Optional, gated behind env vars (API keys). Not in CI secrets path. Must not fail the build if the key is absent — skip with a message.

### 12. Configurability

| Category                                                     | Rule                                                                                                                        |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| Structural rules (jitter required, TLS off-host, drop=abort) | **Not configurable.** These are policy, not tuning knobs.                                                                   |
| Numeric defaults (delays, timeouts, pool sizes)              | **Configurable per backend** within the override room specified in this ADR.                                                |
| Override documentation                                       | Any override must be documented in the adapter/peer code with a comment referencing this ADR and stating the justification. |
| New paths                                                    | Any new communication path added to Lanyte must comply with this ADR at introduction. There is no grace period.             |

## Decision Table: Concrete Defaults

| Parameter                | Value            | Status           |
| ------------------------ | ---------------- | ---------------- |
| `max_attempts`           | 3                | Required default |
| `base_delay`             | 1s               | Required default |
| `base_delay_500`         | 3s               | Required default |
| `max_jitter`             | 250ms            | Required default |
| `jitter_mode`            | Additive bounded | Required         |
| `connect_timeout`        | 10s              | Required default |
| `request_timeout`        | 60s              | Required default |
| `stream_idle_timeout`    | 30s              | Required default |
| `shutdown_timeout`       | 5s               | Required default |
| `max_per_attempt_sleep`  | 30s              | Required default |
| `total_retry_budget`     | 90s              | Required default |
| `pool_max_idle_per_host` | 8                | Required default |
| `min_tls_version`        | 1.2              | Required         |

## Relationship to ADR-0010

ADR-0010 addendum section G established retry norms for LLM adapters. This ADR supersedes section G for retry/backoff policy and extends coverage to all transport paths. ADR-0010's other sections (trait design, conformance gate, error taxonomy) remain in effect.

The Claude and Grok adapters partially comply as of PR #15 (2026-03-20). They implement: retry eligibility, exponential backoff, 500-class baseline, bounded additive jitter with deterministic test seed, connect/request timeouts, connection pooling, drop-abort, and mock transport coverage. Two new caps introduced by this ADR are **not yet enforced**:

- `max_per_attempt_sleep` (30s) — adapters do not currently cap individual sleep durations
- `total_retry_budget` (90s) — adapters do not currently track cumulative retry time

These must be added as a follow-up before this ADR moves from Proposed to Accepted. New adapters (AGI-009/OpenAI) and new peers (chanvoy, future peers) must comply fully at introduction.

## Consequences

- Positive: Every new communication path starts with known-good defaults. No re-derivation of retry policy.
- Positive: Jitter is mandatory — eliminates a class of outage-amplification bugs before they're written.
- Positive: "Required defaults with narrow override room" prevents drift while allowing justified provider-specific tuning.
- Positive: Test requirements are concrete — deterministic jitter seed, mock coverage per error class, drop/cancel verification.
- Negative: Peer paths (mlvoy, chanvoy) that don't yet exist must adopt this policy at creation. This front-loads design work.
- Negative: The `max_per_attempt_sleep` and `total_retry_budget` caps require a follow-up patch to existing Claude/Grok adapters before this ADR can be accepted.
- Risk: The "no automatic reconnect for streams" rule means a network blip during a long streaming response requires the orchestrator to detect and re-request. This is intentional — silent reconnect risks duplicate output — but increases orchestrator complexity.

## References

- ADR-0010: LLM Adapter Design (section G superseded for retry policy)
- AGI-010: Grok adapter (reference implementation of jitter, 500-baseline, citations)
- AGI-012: Claude adapter (reference implementation of jitter, backoff)
- CT-5: Stream cancellation conformance test
- STD-006: Peer contract spec (future — will reference this ADR for transport behavior)
