---
title: ADR-0012 CLI stdout purity policy
---

# ADR-0012: CLI stdout purity policy

## Status

Proposed

## Context

Lanyte CLI tools are increasingly used in scripted and agentic pipelines where
output is piped directly to other commands. Mixing confirmation text and data on
stdout creates brittle integrations and parsing errors.

Recent `lanyte-ctx` adoption surfaced this directly:
- `resume` is consumed as JSON by downstream tools
- `checkpoint`/`init`/`validate` confirmations on stdout contaminated pipelines

The platform needs a consistent and predictable CLI output contract before
additional tools (`lanyte-attest`, future CLIs) ship.

Prior art:
- Unix CLI conventions (data on stdout, diagnostics on stderr)
- goneat command behavior
- gofulmen command behavior

## Options Considered

### Option A: Strict stdout purity policy

- Pros:
  - Reliable machine parsing for piped and captured outputs
  - Consistent UX across all Lanyte CLIs
  - Lower integration and automation risk
- Cons:
  - Requires small migration in tools that currently print confirmations to stdout

### Option B: Per-command ad hoc behavior

- Pros:
  - No immediate refactor requirement
- Cons:
  - Inconsistent behavior across CLIs
  - Ongoing ambiguity and regression risk
  - Harder policy enforcement in review

## Decision

Adopt **strict stdout purity** for all Lanyte CLI tools.

Policy:
- **stdout** is reserved for programmatic output only:
  - structured data (JSON, line-oriented machine-readable output)
  - raw content intentionally emitted by a command (for example, `resume`, `docs show`)
- **stderr** is used for everything else:
  - confirmations and status messages
  - diagnostics and warnings
  - errors
  - progress/logging output

Logging mechanism:
- Use environment-driven logging (`RUST_LOG`) for diagnostics in Rust CLIs.
- No requirement for dedicated `--verbose` flags in v1.

Scope:
- Applies to `lanyte-ctx`, `lanyte-attest`, and future Lanyte CLI binaries.
- Does not change exit code contracts; only output channel discipline.

## Consequences

- Positive:
  - Safer automation and composability in shell pipelines
  - Consistent cross-tool behavior and easier operator expectations
  - Cleaner testing model (stdout content tests vs stderr diagnostics tests)
- Negative:
  - Existing scripts that parse human confirmation from stdout must be updated
- Risks:
  - Regressions if new commands accidentally print diagnostics to stdout
  - Mitigation: add command-level tests for stdout/stderr behavior in each CLI repo
