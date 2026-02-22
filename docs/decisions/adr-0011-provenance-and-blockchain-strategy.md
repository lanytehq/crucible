---
title: ADR-0011 Provenance and Blockchain Strategy
description: Sigstore/Cosign as the v1 provenance anchor; blockchain as an optional additive layer from Sprint 5 onward
---

# ADR-0011: Provenance and Blockchain Strategy

Status: Accepted

## Context

Skill packages (`.lanyte-skill`) need provenance guarantees: who built it, when, from what source, and that it has not been tampered with. The question is whether a distributed ledger provides enough additional value in Sprint 1-4 to justify the integration cost, and if so, which chain and for what purpose.

## Decision

### v1 (Sprint 1-4): Sigstore/Cosign only

Skill package provenance is anchored via:
- **Sigstore/Cosign** — keyless signing using OIDC identity (GitHub Actions or maintainer identity). The signature is embedded in the `.lanyte-skill` package alongside the SBOM.
- The Cosign transparency log (Rekor) provides an append-only, publicly auditable record of all signatures.
- Skillsentry (the static analysis tool) verifies the signature before any grant phase begins.

This is sufficient for Sprint 1-4. No blockchain dependency.

### v1 schema: `chain_provenance` is optional and chain-agnostic

The skill package manifest includes a `chain_provenance` object:
```json
{
  "chain_provenance": {
    "chain": "arweave",
    "tx_id": "...",
    "anchored_at": "2026-02-22T..."
  }
}
```

The `chain` field is a string, not an enum, to avoid locking the schema to a specific chain. Tools that do not understand a given chain MUST treat the field as informational and not fail validation.

### Sprint 5+: Optional blockchain anchor

If provenance requirements evolve (e.g. compliance certification, cross-org skill sharing, economic primitives for skill authors), a blockchain anchor layer can be added additively:

- **Arweave**: preferred for provenance-only use cases (pay-once permanent storage; no smart contracts needed; ~$0.001 per KB; data is retrievable indefinitely).
- **Solana**: preferred if economic primitives are needed (token-gated skills, royalty payments to skill authors, on-chain skill registry with versioning).
- These are not mutually exclusive.

The choice is deferred until there is a concrete requirement. Adding blockchain support to lanyte-core is additive — it does not change the IPC schema (other than populating `chain_provenance`) and does not affect the trust model for installations that do not use it.

### What we will not do

- Require blockchain validation for skill installation in v1.
- Build a custom chain or consensus mechanism.
- Use a proof-of-work chain for anything (energy cost, finality latency).

## Consequences

- Positive: Sigstore/Cosign is free, keyless, and integrates with GitHub Actions — zero marginal cost for Sprint 1.
- Positive: Deferring blockchain avoids premature coupling to a specific chain's SDK and token economics.
- Positive: The `chain_provenance` field in the manifest means skill packages built in Sprint 1-4 can be retroactively anchored later without a schema change.
- Negative: Until blockchain anchoring is implemented, cross-org provenance depends on Sigstore Rekor's availability and the maintainer's OIDC identity. Rekor is not under Lanyte's control.
- Risk: If Arweave or Solana network conditions change significantly (fees, availability, governance), we may need to reassess. The chain-agnostic schema field protects against lock-in.
