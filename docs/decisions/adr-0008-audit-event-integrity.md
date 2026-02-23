---
title: ADR-0008 Audit Event Integrity via Wire-Level Hash Chain
description: How tamper-evidence is achieved for the audit log by carrying prev_hash in telemetry frames
---

# ADR-0008: Audit Event Integrity via Wire-Level Hash Chain

Status: Accepted

## Context

Lanyte agents must produce an auditable record of every consequential action. The audit log must be tamper-evident: if an entry is modified or deleted after the fact, the corruption must be detectable. The question is where the hash chain is managed and anchored.

## Decision

The hash chain is managed **at the wire level** by the emitting peer, not by core alone.

Each `audit_event` message on the TELEMETRY channel (3) carries:

- `entry_id` — UUID v4 unique to this entry
- `prev_hash` — SHA-256 (lowercase hex) of the canonical JSON encoding of the previous `audit_event` emitted by this peer. The genesis entry uses `"0" * 64`.

Core:

1. Receives the `audit_event` frame.
2. Looks up the most recently stored entry for this `peer_id`.
3. Computes `SHA-256(canonical_json(previous_entry))` and compares to `prev_hash`.
4. Rejects the frame if the hash does not match (logs the rejection, notifies admin).
5. Stores the entry and its hash in the hot tier (SQLite WAL).

Each peer maintains its own chain. Chains are not merged (multi-peer chain merging is a future concern if cross-agent shared memory is required).

### Canonical JSON encoding

The SHA-256 input is the JSON encoding of the stored entry object, keys sorted lexicographically, no trailing whitespace. This must be specified precisely in the implementation guide to avoid hash mismatches across platforms.

## Options Considered

### Option A: Core maintains hash chain independently

Peers emit plain audit events; core assigns sequence numbers and computes the hash chain itself.

- Pros: Simpler peer implementation; peers cannot forge chain.
- Cons: Chain can only detect corruption that occurs after core receives the event. If core itself is compromised, the chain provides no evidence. The peer's own audit log is not independently verifiable.

### Option B: Wire-level prev_hash (chosen)

Peers compute and carry prev_hash.

- Pros: An independently stored copy of peer audit logs (e.g. offloaded to cold storage) can be verified without core. Tampering with core's stored chain can be detected by comparing against the peer's own records.
- Cons: More complex peer implementation. A peer that loses its state cannot continue its chain (must start a new chain, which is detectable).

### Option C: Blockchain anchoring (deferred to Sprint 5+)

Periodic Merkle root committed to Arweave or Solana for external verifiability.

- See ADR-0011 for the provenance and blockchain strategy.

## Consequences

- Positive: Audit entries are verifiable independently of core's integrity.
- Positive: Chain breaks are detectable — a peer that emits a bad `prev_hash` is immediately flagged.
- Negative: Peer implementations must maintain their own prev_hash state persistently. Stateless peer restarts require a chain-reset protocol (emit with `prev_hash = "0"*64`, note the discontinuity).
- Risk: Canonical JSON encoding must be exactly specified. A cross-platform hash mismatch (e.g. due to float serialisation or key ordering differences) will cause valid entries to be rejected.
