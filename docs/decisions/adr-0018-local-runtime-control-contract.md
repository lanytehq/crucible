---
title: Explicit local runtime-control contracts
---

# ADR-0018: Explicit local runtime-control contracts

## Status

Proposed

## Context

Chanvoy graceful runtime retirement requires bounded process-instance,
generation, correlation and outcome contracts. Numbered gateway channels carry
peer-domain messages; the chat channel does not authorize host process control.
A persisted record or an empty shutdown request cannot establish safe retirement.

## Options Considered

### Extend the numbered chat or control channel

Reuses registry loading but conflates peer-domain routing with local native
process authority and bootstrap transport.

### Select a consumer-specific local family explicitly

Keeps transport and authority boundaries distinct, at the cost of explicit
root validation and consumer conformance coverage.

## Decision

Place the Chanvoy runtime-control v1 family under `schemas/ipc/local/`, with
nine selected roots for RPC requests/responses, protocol errors, local missing-
acknowledgement reports, bootstrap, readiness and CLI lifecycle observations.
Keep numbered gateway schemas, CHAT260 and persisted runtime records independent.
Do not change directory-loader recursion or allocate a channel number.

Select roots by the trusted transport boundary. Enforce bounded strict parsing
in addition to schema validation. Pin consumer imports to an exact commit and
schema hashes. Contract placement does not activate a consumer implementation.

## Consequences

- Local consumers need explicit selected-root fixtures and strict parser tests.
- Received daemon facts cannot become native process-death proof by a body label.
- Missing acknowledgement and unavailable counts remain unknown, never zero or
  permission to force retirement.
- Compatibility, native handoff, lease and retirement qualification remain
  separate consumer obligations. No force, signal or successor option is added.
