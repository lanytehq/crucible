---
title: Schema Bump Policy
status: draft
version: 0.1.0
---

# Schema Bump Policy

This policy governs changes to versioned schemas across the Lanyte platform — JSON Schema files in `schemas/` (this repository), embedded schema copies in `stashvoy`, `lanyte-attest`, and any future consumer that ships an embedded schema copy.

It answers two distinct questions:

1. **Should you change a versioned schema?** Default: no.
2. **If a change is justified, how do you do it safely?** Rules below.

## Default Disposition

**Do not bump versioned schemas unless there is a really good reason.**

The Lanyte schemas are still evolving conceptually. Each bump:

- Requires lockstep regen across every consumer that embeds the schema (`stashvoy`, `lanyte-attest`, future peers).
- Adds coordination tax to the team carrying the bump and to the consuming teams.
- Ratchets the surface before the design has settled.

This matches the convention many established Rust/protocol projects follow: hold schemas stable while the surrounding code is in flux; bump deliberately when the design has stabilized.

## When This Policy Applies

Any brief, PR, or change proposal that touches:

- `schemas/ipc/*.schema.json` (channel schemas)
- `schemas/agentic/v0/*.schema.json` (agent state, role prompt, capability)
- Any embedded schema copy in a consuming binary (e.g., `stashvoy/schemas/v0/`, `lanyte-attest` embedded schema)
- The `version` field of any of the above

## Bar for Bumping

A bump is justified only if **all** of the following hold:

1. **Real downstream consumer impact**, not author convenience. "I'd prefer a longer `maxLength`" or "this field name would read nicer" do not qualify.
2. **Cannot be resolved by a non-schema fix**. Before proposing a bump, evaluate whether better introspection (CLI surfaces, error messages), better documentation, or better tooling can resolve the friction without touching the schema.
3. **Sustained signal**, not single-author observation. A bump driven by one session's friction is insufficient; the issue must surface across multiple roles, sessions, or consumers.
4. **Documented evidence**. The bump proposal carries data — usage histograms, consumer breakage reports, sustained-friction memory entries — not just narrative.

**Burden of proof is on the proposer.** The default is "no bump." If reviewers cannot identify which of the four criteria the proposal satisfies, the proposal is incomplete.

## If a Bump Is Justified — Safe-Bump Rules

These rules apply to any bump that clears the bar above. They are not optional.

1. **Breaking by default**. Every peer or consumer that uses the channel/schema must be updated simultaneously. Coordinate the lockstep regen explicitly; do not land the bump without a confirmed plan for each consumer.

2. **`oneOf` for additions**. New message types or alternatives go through `oneOf` extension. Never remove or rename existing types without:

   - An ADR documenting the decision (`docs/decisions/`)
   - A migration plan for existing consumers

3. **Schema validation before committing**:

   ```bash
   ~/dev/3leaps/ipcprims/target/debug/ipcprims echo /tmp/test.sock \
     --validate schemas/ipc/
   ```

4. **`additionalProperties: false` on all schema objects**. `ipcprims` strict mode enforces this; be explicit in the schema regardless.

5. **Version-bump strategy**:

   - **Additive-only changes** (new optional fields, new `oneOf` alternatives, relaxed-but-compatible constraints): minor bump within the major version (e.g., `v0` → `v0.1`). Consumers continue to read older payloads.
   - **Breaking changes** (removed/renamed fields, tightened constraints, type changes): major bump (e.g., `v0` → `v1`). All consumers must regen and ship before the bump lands in production.

6. **Cross-consumer coordination**:

   - Identify every consumer that embeds the schema (`grep` the relevant schema filename across `~/dev/lanytehq/` + `~/dev/3leaps/` + `~/dev/fulmenhq/` worktrees).
   - File a tracking issue or wave-coordination thread in the relevant project board.
   - Land the bump only after each consumer has a regen PR queued and reviewed.

7. **Public-flip awareness**. If the schema lives in a repo that is or will be public, the bump becomes externally observable. Coordinate timing with any pending public-flip event (e.g., chanvoy v0.2.2's first-public-release window).

## Cross-References

- **Repo conventions**: `AGENTS.md` §Schema changes points to this policy.
- **Public-doc redaction**: `docs/policies/public-docs-redaction.md` — companion policy on what goes in public-visible schemas vs. internal-only.
- **ADR process**: `docs/decisions/adr-template.md` — required for non-additive bumps.

## History

- **0.1.0 (2026-05-12)** — initial draft. Triggered by CRT-011D drafting cycle and platform-wide "literally everyone hits this" signal on `stashvoy` checkpoint friction. Policy direction set by @3leapsdave 2026-05-12: "too early in dev and too noisy — leaving unless there is a really good reason." Dispatch concurred on three-tier docs split and pattern-setter review for the first policy file.
