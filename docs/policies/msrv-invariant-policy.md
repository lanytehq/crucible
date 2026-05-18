---
title: MSRV Invariant Policy
status: draft
version: 0.1.0
---

# Minimum Supported Rust Version (MSRV) Invariant Policy

This policy governs the Minimum Supported Rust Version invariant across Rust crates in the Lanyte ecosystem.

It answers two questions:

1. **What is the current MSRV?** Tracked in this policy's §Practice and propagated to per-crate `Cargo.toml` `rust-version` fields.
2. **When does MSRV move forward?** When transitive dependencies require it — never pin deps back to keep MSRV down.

## Default Disposition

**MSRV moves forward, not backward.** When a transitive dependency requires a newer Rust version, bump the workspace MSRV to match — do not pin the dep back to an older version to preserve the old MSRV.

## When This Policy Applies

All Rust crates in the Lanyte ecosystem:

- `lanyte` workspace crates (`lanyte-common`, `lanyte-telemetry`, `lanyte-gateway`, `lanyte-state`, `lanyte-llm`, `lanyte-executor`, `lanyte-orchestrator`, main binary)
- `stashvoy` (formerly `lanyte-ctx` pre-CRT-011F rename) — the agent-state CLI
- `lanyte-attest` — session attestation CLI
- `lanyte-verify` — tool verification library
- `ipcprims` (3leaps org) — IPC primitives library (transitively required by lanyte)
- `seclusor`, `chanvoy`, and other lanyte-ecosystem Rust release-shipping repos

Per-repo crate-level overrides are permitted only when a repo's release cadence makes lockstep MSRV bumps impractical (e.g., a repo with external Rust-version-pinned adopters). Default is workspace-consistent MSRV across the ecosystem.

## Practice

### Current MSRV

**Rust 1.85.0** for all lanyte ecosystem crates.

Per-crate `Cargo.toml` `rust-version` field is the **single source of truth** for that crate's MSRV. This policy file states the platform target; per-crate manifest is authoritative for build behavior.

Chanvoy currently lives at `rust-version = "1.89.0"` — ahead of the platform baseline because chanvoy's HTTP-client surface required a newer reqwest version. This is the expected pattern: per-repo manifests may sit ahead of the platform target when their dep graph requires it; they do not sit behind.

### Enforcement

Every workspace carries:

1. **`make msrv` target** that runs `cargo +<msrv> check --workspace --all-targets --all-features` to verify the workspace builds against the declared MSRV.
2. **CI MSRV job** in `.github/workflows/check.yml` (or equivalent) that runs `make msrv` on every PR.
3. **Workspace `Cargo.toml` `rust-version`** as the single source of truth; per-crate manifests inherit via `rust-version.workspace = true` where appropriate.

Reference implementation: `lanyte` workspace per CRT-010.

### Bump-forward discipline

When a transitive dependency requires a newer MSRV than the current declared version:

1. **Bump the workspace `rust-version`** to the minimum passing version.
2. **Update all per-crate `Cargo.toml` files** to reflect the new MSRV (`rust-version` field).
3. **Update this policy's "Current MSRV" line** with the new version in the same change.
4. **Update CI MSRV job comments** if they reference the version explicitly.
5. **Run `make pr-final`** (or equivalent platform gate) to verify the workspace + CI both pass at the new MSRV.

**Do not:**

- Pin a transitive dep back to an older version to preserve the old MSRV (creates a dependency-graph drift that compounds over time).
- Skip the MSRV bump and let CI carry a stale `rust-version` while reality has moved forward (creates a contract gap between declared MSRV and what the code actually requires).
- Use unstable Rust features in stable crates (this is a separate invariant; see [`schema-bump-policy.md`](./schema-bump-policy.md) for the "don't add stability surface without really good reason" pattern).

### What MSRV bumps look like

An MSRV bump lands as one of:

- **Routine bump** (workspace deps require it; no operator visibility needed): single PR updating `rust-version` + this policy's current-MSRV line; small commit; passes through normal review.
- **Coordinated bump** (multiple repos at once, or platform-significant version transition): briefly drafted as a CRT (or equivalent) brief; coordinates lockstep across repos. Reference [CRT-010](https://github.com/lanytehq/lanyte-productbook-internal/blob/main/content/projmgmt/core-runtime/index.md) for the original enforcement-introduction pattern.

## Cross-References

- **CRT-010** — original MSRV enforcement task in the `lanyte` workspace; established the `make msrv` + CI MSRV job pattern this policy carries forward.
- **`schema-bump-policy.md`** — sibling policy on "default-no" stability discipline for the schema surface. Similar shape: bump deliberately, not casually.
- **`release-signing-manual-baseline-policy.md`** — release builds use `cargo build --release --locked` per chanvoy PER-031 specialist findings; locked builds + workspace MSRV invariant together ensure released binaries match what was tested.
- **Galaxy-root `~/dev/lanytehq/AGENTS.md`** — previously carried the MSRV statement inline; now cites this policy (see Note below).

## Note on the galaxy-root AGENTS.md move

This policy supersedes the inline MSRV statement that previously lived at `~/dev/lanytehq/AGENTS.md` §Key Invariants. The galaxy-root AGENTS.md will be updated separately (it is a local-only file pending the org-root canonical-location queue item; dispatch carries that thread). The cite-pointer in galaxy-root AGENTS.md will read:

> - **MSRV**: governed by [MSRV Invariant Policy](https://github.com/lanytehq/lanyte-crucible/blob/main/docs/policies/msrv-invariant-policy.md). Current: Rust 1.85.0.

This is the "dual-edge" update dispatch flagged during PR 1 review: the policy lands here, the galaxy-root inline statement gets thinned to a cite. Implementation timing of the galaxy-root edge is separate from this PR.

## History

- **0.1.0 (2026-05-16)** — initial draft. Moves the MSRV statement from galaxy-root `~/dev/lanytehq/AGENTS.md` §Key Invariants into the platform-policy SSOT. Adds bump-forward discipline + per-repo MSRV inheritance pattern. Triggered by the PR 1 cross-repo SSOT framing from dispatch 2026-05-14.
