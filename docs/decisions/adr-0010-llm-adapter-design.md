---
title: ADR-0010 LLM Adapter Design
description: Direct-to-frontier-model adapters with no abstraction intermediary; adapter is pure transport
---

# ADR-0010: LLM Adapter Design

Status: Accepted

## Context

The orchestrator needs to call LLMs to reason about tasks. The design choice is whether to use an abstraction library (OpenAI-compatible proxy, LiteLLM, Ollama API, etc.) or to call frontier model APIs directly with a thin per-model adapter.

## Decision

**Direct-to-frontier-model adapters. No abstraction intermediary.**

The `lanyte-llm` crate exposes a `LlmBackend` trait:

```rust
pub trait LlmBackend: Send + Sync {
    fn complete(&self, request: CompletionRequest) -> Result<CompletionResponse>;
    fn stream(&self, request: CompletionRequest) -> Result<Box<dyn Stream<Item = StreamChunk>>>;
    fn capabilities(&self) -> BackendCapabilities;
    fn health(&self) -> HealthStatus;
}
```

Each adapter implements `LlmBackend` directly against the provider's native API using `reqwest`. Context window management, retry logic, and token counting live in the orchestrator and adapter respectively — not in a shared abstraction layer.

### Claude adapter specifics (v1)

- **Model**: configured via `lanyte-common` config key `llm.claude.model` (default: `claude-sonnet-4-6`). Changed by config, not code.
- **API**: Anthropic Messages API, `POST /v1/messages`.
- **Auth**: API key injected at adapter init from the gateway secret store; never persisted by the adapter.
- **Retry**: bounded exponential backoff on `429` and selected upstream `5xx` (`500/502/503/504`), max 3 attempts, base delay 1 s with jitter.
  - Rationale: `500` is often a blanket "unknown failure" during partial upstream outages; a longer baseline backoff reduces load amplification and helps decorrelate concurrent agents from narrower/localized failures.
  - `500` uses a longer baseline backoff than other retryable statuses.
- **Streaming**: native server-sent events.

## Options Considered

### Option A: OpenAI-compatible proxy / abstraction layer (e.g. LiteLLM)

- Pros: Single API surface; easy model switching; community tooling.
- Cons: Abstraction layer is a dependency with its own release cadence and failure modes; OpenAI compatibility shims often lag frontier model features by weeks/months; introduces a network hop if proxy is external; adds surface for prompt injection at the proxy layer.

### Option B: Direct adapters (chosen)

- Pros: No abstraction layer failures; access to full native API including model-specific features (extended thinking, system prompt caching, tool use specifics); no dependency risk from intermediary; adapter code is small and auditable.
- Cons: Each new model requires a new adapter; no drop-in model switching without adapter work.

## Consequences

- Positive: Each adapter is ~200-400 lines of Rust, fully auditable as part of the TCB.
- Positive: Model-specific features (structured output, caching, extended context) are available as soon as the provider ships them, without waiting for an abstraction layer to catch up.
- Negative: Adding a second LLM provider (GPT-4o, Grok, Gemini) requires writing a new adapter. This is intentional — we do not want to accidentally commit to a multi-provider abstraction before we know which models matter.
- Risk: If the Anthropic Messages API makes a breaking change, only the Claude adapter needs updating. This is easier than a shared abstraction layer that must accommodate multiple providers simultaneously.
- Risk: Retrying on some upstream `5xx` can increase the chance of duplicate provider billing if the request was processed server-side but failed at the transport boundary. Lanyte keeps retries bounded and expects the orchestrator to handle sustained outages via higher-level scheduling.
- Note: The `LlmBackend` trait is the abstraction. The abstraction is the trait, not a library.

---

## Addendum: Multi-Provider Trait Contract (2026-02-27)

Status: Accepted (cxotech + entarch review)

### Context

The original ADR-0010 decision anticipated multiple adapters but shipped a single Claude adapter
(CRT-008) with a skeletal trait surface: `CompletionRequest { prompt, max_tokens }`,
`StreamChunk { text_delta }`, and an opaque `LlmError::Upstream { status, message }`.

Adding OpenAI and xAI/Grok backends (AGI-009, AGI-010) requires expanding the trait contract
before the orchestrator can route across providers. This addendum defines the expanded types,
the streaming normalization boundary, the error taxonomy, and the conformance gate. The core
decision — direct adapters, no intermediary — is unchanged.

### A. Canonical StreamEvent Enum

Each adapter normalizes its provider's SSE/streaming format into these variants. The orchestrator
consumes a typed event stream and never sees provider-specific wire formats.

```rust
pub enum StreamEvent {
    /// Incremental text output.
    TextDelta(String),

    /// A new tool call begins. `id` is adapter-assigned, unique within the response.
    ToolCallStart { id: String, name: String },

    /// Incremental JSON arguments for an in-progress tool call.
    ToolCallDelta { id: String, arguments_delta: String },

    /// Tool call complete. Concatenated `arguments_delta` values form valid JSON.
    ToolCallEnd { id: String },

    /// Extended thinking / chain-of-thought (Claude, OpenAI o-series).
    /// Named variant (not Annotation) because the orchestrator has distinct handling:
    /// display, token accounting, context management.
    ThinkingDelta(String),

    /// Token usage for the request. May arrive mid-stream or at end depending on provider.
    Usage { input_tokens: u32, output_tokens: u32 },

    /// Why the model stopped generating.
    StopReason(StopReason),

    /// Provider-specific content (citations, images, search results).
    /// Typed structs are deserialized from `payload` by orchestrator code that opts in.
    /// New provider features ship without enum changes.
    Annotation { kind: String, payload: serde_json::Value },

    /// Stream complete. No more events will follow.
    Done,
}

pub enum StopReason {
    EndTurn,
    MaxTokens,
    ToolUse,
    ContentFiltered,
}
```

**Design decisions:**

- **No `StreamEvent::Error` variant.** Errors are the `Err` side of the `Result` in the stream
  item type (`Item = Result<StreamEvent, LlmError>`). A dual error channel (both `Result::Err`
  and `StreamEvent::Error`) creates ambiguity about which path the orchestrator must handle.
  All `Ok(StreamEvent)` variants represent successfully decoded provider output.

- **`Annotation` replaces per-provider variants.** Provider-specific capabilities (search
  citations, image generation) are modeled as `Annotation { kind, payload }` rather than
  dedicated enum variants. This prevents enum churn when new provider features ship.

- **`ThinkingDelta` is a named variant** (not an Annotation) because extended thinking is a
  cross-provider capability (Claude extended thinking, OpenAI o-series reasoning tokens) and the
  orchestrator has distinct handling for it.

### B. Stream Return Type

```rust
fn stream(
    &self,
    request: CompletionRequest,
) -> Result<Pin<Box<dyn Stream<Item = Result<StreamEvent, LlmError>> + Send + 'static>>>;
```

This signature is binding. Rationale for each constraint:

- **`Pin<Box<...>>`** — required for `async` stream consumers. `Box<dyn Stream>` alone is not
  `Unpin` and cannot be polled without pinning.
- **`+ Send`** — the stream will be held across `.await` points in the orchestrator's `select!`
  loop; must be `Send` for multi-threaded tokio runtime.
- **`+ 'static`** — the stream must outlive the `&self` borrow. It captures owned state from the
  adapter, not references to it.
- **`Item = Result<StreamEvent, LlmError>`** — errors are the `Err` side, not a `StreamEvent`
  variant.

### C. CompletionRequest Expansion

The CRT-008 skeleton (`prompt: String, max_tokens: u32`) is replaced by a provider-agnostic
request that supports multi-turn conversation, tool use, and model parameters:

```rust
pub struct CompletionRequest {
    /// Conversation history. Replaces the flat `prompt` field.
    pub messages: Vec<Message>,

    /// Tool definitions available to the model.
    pub tools: Vec<ToolDefinition>,

    /// Results from previous tool calls (fed back in follow-up requests).
    pub tool_results: Vec<ToolResult>,

    /// Maximum output tokens.
    pub max_tokens: Option<u32>,

    /// Sampling temperature. Provider maps to its supported range.
    pub temperature: Option<f32>,

    /// System prompt. Representation varies by provider (top-level field vs system message);
    /// each adapter maps from this canonical field.
    pub system: Option<String>,

    /// Provider-specific streaming configuration (e.g., `include_usage` for OpenAI).
    pub stream_options: Option<StreamOptions>,
}

pub struct Message {
    pub role: Role,
    pub content: MessageContent,
}

pub enum Role {
    System,
    User,
    Assistant,
    Tool,
}

pub enum MessageContent {
    Text(String),
    /// Multi-part content (text + images, tool results, etc.)
    Parts(Vec<ContentPart>),
}
```

Each adapter maps `CompletionRequest` to its provider's request format. The adapter is the
translation layer — the orchestrator constructs provider-agnostic requests.

### D. Error Taxonomy

The CRT-008 error type (`LlmError::Upstream { status, message }`) is replaced by typed variants
that the orchestrator can match without string parsing:

```rust
pub enum LlmError {
    /// API key missing, invalid, or rejected by provider.
    AuthenticationFailed,

    /// Provider rate limit (HTTP 429). `retry_after` extracted from response headers
    /// when available.
    RateLimited { retry_after: Option<Duration> },

    /// Provider overloaded or temporarily unavailable (HTTP 503, 529).
    ServiceUnavailable,

    /// Requested model does not exist or is not available.
    InvalidModel,

    /// Request rejected for content policy reasons.
    ContentFiltered,

    /// HTTP transport or connection failure.
    Http(reqwest::Error),

    /// JSON parse failure on provider response.
    Json(serde_json::Error),

    /// Catch-all for unexpected provider responses. Preserves status + body for debugging
    /// without losing the typed cases above.
    Upstream { status: u16, message: String },

    /// Operation not supported by this adapter.
    Unsupported(String),
}
```

**Mapping rules (each adapter implements):**

| Provider signal                     | LlmError variant               |
| ----------------------------------- | ------------------------------ |
| HTTP 401 / 403 / invalid key        | `AuthenticationFailed`         |
| HTTP 429                            | `RateLimited { retry_after }`  |
| HTTP 503 / 529 / overloaded         | `ServiceUnavailable`           |
| Model not found (provider-specific) | `InvalidModel`                 |
| Content filter refusal              | `ContentFiltered`              |
| Anything else non-2xx               | `Upstream { status, message }` |

The orchestrator uses typed matching for retry decisions, circuit breaking, and user-facing
error messages. The `Upstream` variant is the escape hatch — new provider error codes don't
require immediate enum changes.

### E. BackendCapabilities Expansion

```rust
pub struct BackendCapabilities {
    /// Whether `stream()` is implemented.
    pub supports_streaming: bool,

    /// Whether the model supports tool use (function calling).
    pub supports_tools: bool,

    /// Whether the model supports extended thinking / chain-of-thought.
    pub supports_thinking: bool,

    /// Maximum context window in tokens. Used by the orchestrator for context management.
    pub max_context_tokens: u32,

    /// Maximum output tokens the model supports.
    pub max_output_tokens: u32,
}
```

Capabilities are static per adapter instance (determined by model at init time). The orchestrator
queries capabilities before routing requests — it will not send tool definitions to an adapter
that reports `supports_tools: false`.

### F. Conformance Gate

A backend is **orchestrator-eligible** when it passes all six conformance tests defined in
AGI-011. Until a backend passes conformance, the orchestrator must not route requests to it.

The six tests (CT-1 through CT-6):

1. **CT-1: Tool call round-trip** — prompt triggers tool call, tool result fed back, model
   produces final response incorporating the result.
2. **CT-2: Streaming text fidelity** — concatenated `TextDelta` values equivalent to
   non-streaming `complete()` output (normalized comparison in live mode, byte-identical in
   recorded mode).
3. **CT-3: Streaming tool calls** — well-formed event sequence: `ToolCallStart` before
   `ToolCallDelta` before `ToolCallEnd`, consistent IDs, concatenated arguments form valid JSON.
4. **CT-4: Stop reason classification** — `EndTurn`, `MaxTokens`, and `ToolUse` mapped correctly
   for each provider.
5. **CT-5: Timeout/cancellation** — dropping a stream cleans up adapter resources. Verified via
   `#[cfg(test)]` atomic task counter (increment on stream start, decrement on drop/completion).
6. **CT-6: Error classification** — invalid key → `AuthenticationFailed`, 429 → `RateLimited`,
   503/529 → `ServiceUnavailable`, bad model → `InvalidModel`.

**Test infrastructure:** dual-mode (live + recorded). Live mode makes real API calls and records
HTTP fixtures. Recorded mode replays fixtures — fast, deterministic, no API keys needed, runs on
every PR. Live mode is the source of truth; recorded mode is the regression gate.

### G. Retry Addendum

The original ADR specifies retry for the Claude adapter. This applies uniformly to all adapters:

- Bounded exponential backoff on `429` and selected `5xx` (500, 502, 503, 504).
- Max 3 attempts, base delay 1 s with jitter.
- `500` uses a longer baseline backoff (default 3 s) across all adapters, not just Claude.
- Adapters must use async `tokio::time::sleep`, not `thread::sleep` (required for cancellation
  semantics — dropping the future cancels the sleep).

### Consequences (addendum-specific)

- Positive: The trait contract is validated against three fundamentally different API shapes
  (Anthropic Messages, OpenAI Chat Completions, xAI Chat Completions) before the orchestrator
  depends on it.
- Positive: The conformance gate is a CI-enforced invariant, not an untested claim.
- Positive: `Annotation` escape hatch means new provider features ship without enum changes or
  cross-adapter coordination.
- Negative: The expanded `CompletionRequest` and `StreamEvent` are a breaking change to the
  CRT-008 skeleton. AGI-012 (Claude adapter conformance upgrade) absorbs this cost.
- Negative: Three adapters means three sets of fixture recordings to maintain. Fixture staleness
  (provider API changes) requires periodic live-mode regeneration.
- Note: Azure OpenAI is explicitly deferred. It requires deployment-name-in-path and
  api-version query parameters that are not a simple base_url override.

### References

- AGI-009: OpenAI-compatible backend MVP
- AGI-010: xAI/Grok native backend MVP
- AGI-011: Provider conformance harness (StreamEvent + CT-1..CT-6)
- AGI-012: Claude adapter conformance upgrade
