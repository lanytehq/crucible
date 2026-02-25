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
