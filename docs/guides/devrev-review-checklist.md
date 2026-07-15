---
title: Devrev Review Checklist
description: Global review checklist for devrev agents — use on every PR to catch common cross-cutting concerns without keeping all ADRs in context
---

# Devrev Review Checklist

Use this checklist on every PR review. It covers cross-cutting concerns from ADRs,
specs, and conventions that are easy to miss without re-reading every document.

Not every item applies to every PR. Skip items that don't apply. Flag items that
should apply but don't.

---

## Configuration (CFG-001)

- [ ] Config paths use `$LANYTE_CONFIG_ROOT` convention (platform-native default via
      `dirs::config_dir()/lanytehq/`), not hardcoded `~/.config/lanytehq/`
- [ ] New config fields have env var overrides with `LANYTE_` prefix
- [ ] Config provenance is tracked (which layer provided each value)
- [ ] Secrets are in `secrets.toml` / `secrets.age`, not in `config.toml`
- [ ] No secrets in code, logs, or commit history

## IPC and Schemas (STD-001/003/006)

- [ ] New IPC message types have schemas in crucible before implementation
- [ ] Schemas use `additionalProperties: false` (strict mode)
- [ ] `request_id` (UUID v4) on every request/response pair
- [ ] `delegation_id` on operations that need scoping
- [ ] `gate_token` on side-effect verbs (post, send, create, delete, archive)
- [ ] Error envelope uses typed `error_code` + `message` + `retryable`
- [ ] Peer identity is connection-bound (STD-006), not self-asserted in payloads

## Executor and Skills (STD-004)

- [ ] Skills are untrusted — executor validates all inputs at the boundary
- [ ] Fresh instance per invocation (no state between invocations)
- [ ] Resource limits (fuel, memory, time) are executor-owned, not skill-controlled
- [ ] Guest memory reads are bounds-checked (ptr + len <= memory size)
- [ ] Guest buffers are freed exactly once, including on error paths
- [ ] `skill_id` validates against channel 259 schema pattern

## Transport Reliability (ADR-0014)

- [ ] Retry uses bounded exponential backoff with jitter
- [ ] Only retryable status codes are retried (429, 502, 503, 504)
- [ ] No silent reconnect on streaming paths
- [ ] Timeout is enforced on all external calls

## LLM Adapters (ADR-0010)

- [ ] `LlmBackend` trait stays transport-focused — no selection/routing logic inside adapters
- [ ] Provider selection goes through `ConfiguredBackends`, not hardcoded in adapters
- [ ] API keys come from config/secrets, never hardcoded
- [ ] Streaming normalizes to canonical `StreamEvent` enum

## Attribution and Process

- [ ] Agent commits have `Co-Authored-By` + `Role` + `Committer-of-Record`
- [ ] Agent PRs have `Drafted-By` + `Role` + `PR-of-Record` footer
- [ ] No direct pushes to main — PR required
- [ ] MSRV matches workspace `Cargo.toml` `rust-version`
- [ ] `make pr-final` passes (or equivalent CI gate)

## TCB Boundary

- [ ] Gateway is a router — no business logic in gateway
- [ ] Peer input is validated at the IPC boundary before acting on it
- [ ] Only lanyte core (Rust workspace) is trusted
- [ ] No `unsafe` without secrev review

## Audit and Observability (AGI-006)

- [ ] Side-effect actions emit audit events
- [ ] Audit records include correlation IDs for end-to-end tracing
- [ ] Error paths produce structured errors, not panics or silent failures
