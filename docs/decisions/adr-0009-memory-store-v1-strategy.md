---
title: ADR-0009 Agent Memory Store v1 Strategy
description: SQLite with application-enforced INSERT-only policy as the hot-tier memory store; defers a purpose-built immutable store library
---

# ADR-0009: Agent Memory Store v1 Strategy

Status: Accepted

## Context

Agent memory must be:
- **Append-only** — entries are never overwritten, only superseded by later entries
- **Tamper-evident** — the hash chain (per ADR-0008) makes modification detectable
- **Queryable** — fast lookup by time, topic, association, and agent ID
- **Bounded** — eviction to warm/cold tier prevents unlimited growth

The question is whether SQLite (already a dependency for state storage) is adequate, or whether a purpose-built immutable store is needed.

## Decision

Use **SQLite WAL mode with application-enforced INSERT-only policy** for the hot tier.

Enforcement mechanism:
1. The `lanyte-state` crate opens the DB in WAL mode.
2. On schema migration, it installs triggers that raise errors on `UPDATE` and `DELETE` against the `memory_entries` table.
3. Supersession is modelled as a new INSERT with a `supersedes_id` foreign key, not as an UPDATE.
4. The hash chain is maintained in application code (`lanyte-state` computes `prev_hash` before inserting).
5. No external process or user has direct DB write access; all access is through the `lanyte-state` API.

### Eviction to warm/cold

When the hot tier exceeds its size limit, the oldest entries are exported to the warm tier (compressed file segments on local disk) and removed from SQLite. Removal from SQLite is the one permitted DELETE — executed by the eviction subsystem only, audited, and logged before removal.

### Deferred: `memprims` library

A purpose-built immutable append-only store (`3leaps/memprims` or `3leaps/auditprims`) would provide structural enforcement rather than application-level enforcement. This is deferred until one of these triggers occurs:
- Multi-agent shared memory with cross-agent chain verification is required.
- Compliance certification requires structural (not application-level) immutability guarantees.
- The application-enforcement layer experiences a correctness failure in production.

## Options Considered

### Option A: SQLite + application-level enforcement (chosen)

- Pros: SQLite is already a planned dependency; WAL mode is proven; familiar tooling; queryable with full SQL.
- Cons: Enforcement is application-level, not structural; a bug in the `lanyte-state` crate could permit writes.

### Option B: Append-only log file with separate index

A plain file where each record appends the hash of the previous. A separate SQLite index is maintained for queries.

- Pros: Simpler, tamper-evident structurally.
- Cons: Two systems to maintain; the index can drift from the log; atomic append+index update requires careful locking.

### Option C: `memprims` library (deferred)

A new 3leaps library providing a structured immutable store API.

- Pros: Structural enforcement; reusable beyond Lanyte; could be audited independently.
- Cons: Engineering cost for a v1 need that SQLite can cover adequately; delays other work.

### Option D: Content-addressed store (git objects model)

Entries stored by SHA-256 hash of their content. An index tracks associations.

- Pros: Inherently immutable; familiar model.
- Cons: Not natively queryable; requires separate index; git itself is overkill.

## Consequences

- Positive: Immediate progress without a new library; SQLite is battle-tested.
- Positive: The abstraction boundary (the `lanyte-state` crate API) means the storage backend can be swapped later without changing the orchestrator.
- Negative: Application-level INSERT-only enforcement is weaker than structural enforcement; requires careful code review of the `lanyte-state` crate.
- Risk: Trigger-based enforcement can be circumvented by a sufficiently privileged SQLite connection. The mitigation is that `lanyte-state` is the only code that opens the memory DB, and this is enforced by process isolation (TCB boundary).
