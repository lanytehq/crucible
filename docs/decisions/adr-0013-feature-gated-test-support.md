---
title: ADR-0013 Feature-Gated Test Support in Workspace Crates
description: Pattern for exposing test utilities to integration tests without polluting the production crate surface
---

# ADR-0013: Feature-Gated Test Support in Workspace Crates

Status: Accepted

## Context

Rust workspace crates often need shared test utilities — fixtures, helpers, mock spawners — that are used by both unit tests (inside `src/`) and integration tests (inside `tests/`). The language's `#[cfg(test)]` attribute only applies to unit tests within the crate; integration tests are compiled as separate crates and cannot access `#[cfg(test)]`-gated modules.

The naive fix — making `test_support` an unconditional `pub mod` — compiles test utilities into the production binary. This leaks test-only types into the public API surface and inflates the production artifact.

A subtler problem: Cargo's `required-features` on `[[test]]` and `[[bin]]` targets causes those targets to be **silently skipped** when the feature is not enabled. There is no warning. `cargo test --workspace` reports green even though gated tests never ran. This makes the failure mode invisible without explicit CI/Makefile discipline.

This ADR was motivated by [lanyte PR #11](https://github.com/lanytehq/lanyte/pull/11), where `lanyte-gateway`'s test harness and mock peer binary were initially exposed as unconditional public modules.

## Options Considered

### Option A: Unconditional `pub mod test_support`

- Pros: Simple. Integration tests just work.
- Cons: Test utilities ship in production. Public API surface includes test-only types. No compilation boundary between test and production code.

### Option B: Separate `lanyte-test-utils` crate

- Pros: Clean separation. No feature flags needed.
- Cons: Premature for a small workspace. Creates a new crate per consumer. Cross-crate test utilities need access to internal types, which forces either `pub` escalation or `#[doc(hidden)]` workarounds.

### Option C: Feature-gated module (chosen)

- Pros: Test utilities compile only when needed. Production surface stays clean. Works within the existing crate — no new crate overhead. Standard Rust pattern.
- Cons: Requires Makefile/CI discipline to enable the feature. Silent skip if misconfigured.

## Decision

All workspace crates that expose test utilities must follow this pattern:

### 1. Define the feature

```toml
# Cargo.toml
[features]
default = []
test-support = []
```

### 2. Gate the module

```rust
// src/lib.rs
#[cfg(any(test, feature = "test-support"))]
pub mod test_support;
```

`#[cfg(any(test, ...))]` ensures unit tests within the crate can use the module without the feature flag. The feature flag is for external consumers (integration tests, other crates).

### 3. Gate binary and test targets

```toml
[[bin]]
name = "mock_mlvoy"
path = "src/bin/mock_mlvoy.rs"
required-features = ["test-support"]

[[test]]
name = "gateway"
path = "tests/gateway.rs"
required-features = ["test-support"]
```

### 4. Enable in Makefile / CI

The workspace `Makefile` (or CI script) must forward the feature when running tests:

```makefile
test:
    cargo test --workspace --features lanyte-gateway/test-support
```

Every crate that adds a `test-support` feature must be added to this line. This is the critical discipline step — without it, gated tests silently skip.

### 5. Verify coverage

After adding a new `test-support` feature, confirm that `make check` output includes the gated test targets. Search for the test file name (e.g., `tests/gateway.rs`) in the output. If absent, the feature is not being forwarded.

## Consequences

- Positive: Production crate surface contains no test-only types or binaries.
- Positive: Test utilities are co-located with the code they test — no separate crate overhead.
- Positive: `#[cfg(any(test, feature = "test-support"))]` covers both unit and integration test paths with one gate.
- Negative: Makefile/CI must be maintained as new crates adopt the pattern. Forgetting to add a crate's feature causes silent test skipping.
- Risk: The silent-skip behavior is Cargo's design, not ours. New team members unfamiliar with this pattern may not realize their tests aren't running. This ADR and code review are the mitigations.
