---
title: DDR-0002 Agent Memory Contract Family
description: Agent memory entries as a durable-record/v1 profile, a memory-kind classifier dimension, and a per-kind registry
---

# DDR-0002: Agent Memory Contract Family

Status: Proposed

## Context

Agent seats keep more than resumable state. A seat needs its identity and
charter at session start, the week and day plan, open handoffs, decisions
with their evidence, facts it learned, pointers to the documents it acts on,
and where its credentials live. Today only checkpoints have a contract
(`agentic/v0.1/agent-state`). Each tool that adds another class of
information would otherwise define its own shapes, and the shapes would not
agree on authority, classification, or revision.

ADR-0009 sets the agent memory store strategy: append-only, supersession by
new entries, tamper-evident. 3leaps/crucible publishes `durable-record/v1`, a
store-independent record envelope with revisions, supersession by digest,
provenance, and classification. It also publishes classifier dimensions
(sensitivity, access tier, retention, volatility) that contracts reference by
key.

## Decision

1. **Entries are durable-record/v1 records.**
   `schemas/agentic/memory/v0/entry.schema.json` is a profile: it narrows
   the record (registered
   `payload_contract` tokens, `<role>.<scope>` streams) and adds no fields.
   A store that later holds durable-record records holds memory entries
   unchanged.
2. **Kinds are a classifier dimension.** The vocabulary is
   `config/classifiers/dimensions/memory-kind.dimension.json`, in the 3leaps
   dimension format, so any tool can name a kind by its key.
3. **Per-kind policy is a registry.** `config/agentic/memory/v0/kinds.json`
   sets each kind's payload contract, writer class (agent, maintainer,
   external), revision policy, carrier (payload or body), and classification
   floor. Writer class and classification belong to the registry; nothing in
   a payload grants authority. The writer's credential is the authority, and
   a write without one fails closed.
4. **Classification uses the 3leaps keys.** The enums are inlined and
   drift-checked against vendored, sha256-pinned copies of the 3leaps
   dimension definitions. Access tier meets the sensitivity floor; writers
   may raise classification and never lower it below the kind's floor;
   `unknown` is never a default.
5. **One revision digest.** sha256 over the RFC 8785 bytes of the whole
   entry. `digest-vectors.json` pins values every implementation must
   reproduce.
6. **Checkpoints stay as they are.** The checkpoint kind is registered as
   legacy. Its lane hash chain and stored values are not recomputed or
   reinterpreted.
7. **One secret-shaped name rule.** `common/v0/secret-keys.schema.json` owns
   the member-name pattern for values that must never be carried. Other
   families reference it rather than writing their own.

## Consequences

- New kinds are a registry entry, a dimension value, and a payload schema.
  Adding one is additive to this family.
- Tools that do not store memory can still reference kinds and the
  classifiers by key.
- The family depends on durable-record/v1, which is still experimental. The
  vendored copy pins the version this family was checked against; a
  durable-record change is picked up only by refreshing the vendor set and
  passing `check-memory-v0`.
- Retirement, idempotency, and revision conflicts are specified as rules for
  writers (`semantic-validation.md`), not as store receipts. Store receipts
  and journal semantics arrive with a durable-record stratum.

## References

- ADR-0009 Agent memory store v1 strategy
- `schemas/agentic/memory/v0/` (README, semantic-validation)
- `config/classifiers/README.md`
- 3leaps/crucible: durable-record/v1 contract, classifiers framework
