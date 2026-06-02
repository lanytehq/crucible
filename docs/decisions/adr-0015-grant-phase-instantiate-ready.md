---
title: "ADR-0015: Grant phase must produce instantiate-ready artifacts"
---

# ADR-0015: Grant phase must produce instantiate-ready artifacts

## Status

Accepted

## Context

The skill executor lifecycle (see `docs/specs/skill-abi-v1.md`) runs
**load → describe → grant → execute** per invocation. The **grant** phase
sits between describe and execute: it reads the skill's declared
capabilities from the manifest, builds a capability-aware
`wasmtime::Linker` with deny stubs for every import the executor refuses
to back, and caches that linker on the loaded skill so the execute phase
can instantiate without rebuilding it.

SKL-004 landed the v1 grant phase (PR #15 on `lanytehq/lanyte`). During
review, three independent rounds of feedback (secrev, entarch, devrev)
found distinct classes of bug in which `build_grant` returned a
_successful_ grant artifact whose cached linker was **not actually
instantiable**:

1. Repeated `(module, name)` imports failed grant with a spurious
   duplicate-definition error (secrev).
2. Repeated `(module, name)` imports with different `FuncType`s silently
   used the first signature and deferred the type mismatch to instantiate
   time (entarch).
3. A home-grown `ValType` comparison collapsed distinct reference-type
   heap types into a single discriminant, allowing a different shape of
   the same class to slip past the guard (devrev).

Each round hardened the dedup guard, but the underlying recurring failure
mode was architectural, not code-local: the grant phase was _allowed_ to
produce artifacts that only failed later. There was no stated invariant
forcing grant to be a gate rather than a deferred check.

This ADR states that invariant so future host-function implementations,
tier-based policy layers, and any executor changes inherit the guardrail
without re-discovering it through review.

## Options Considered

### Option A — State the invariant as an ADR

- Pros: durable architectural rule; binds future work; discoverable from
  the ADR index; matches the crucible's existing pattern for governing
  executor behavior (ADR-0007, ADR-0013).
- Cons: another ADR to maintain.

### Option B — Amend `docs/specs/skill-abi-v1.md` only

- Pros: in-place near the lifecycle section; no new file.
- Cons: skill-abi-v1 governs the guest-facing ABI contract, not the
  executor's internal gating posture. Mixing the two muddies the scope of
  the spec and makes the invariant harder to cite as a binding rule in
  future reviews.

### Option C — Leave it as a comment in `grant.rs`

- Pros: zero ceremony.
- Cons: invisible outside the executor crate; future host-function work
  and tier-policy work would have no shared rule to cite; the three
  rounds of SKL-004 review would have been avoidable with a stated rule
  but not with a tucked-away comment.

## Decision

**The grant phase MUST produce only instantiate-ready artifacts.**

Concretely, for every return value of shape `Ok(Grant { linker, .. })`:

1. The cached linker MUST be able to instantiate the module it was built
   for, without any additional caller-side configuration, under the same
   engine that produced it.
2. Any condition the executor can detect at grant time that would later
   cause instantiation to fail MUST be surfaced as a grant error
   (`ExecutorError::LinkerError` or a more specific variant), not as a
   silent success.
3. When the executor uses wasmtime primitives whose semantics it does
   not own (e.g. type equality, subtyping, import resolution), it SHOULD
   delegate to the upstream contract (`FuncType::eq`, `ValType::eq`,
   `Module::imports`) rather than re-deriving them locally. Local
   re-derivation has historically introduced the exact class of
   false-positive grants this ADR forbids.

Corollaries:

- A grant that succeeds but whose cached linker cannot satisfy every
  alias of an import is a bug, regardless of whether the alias is shared,
  signature-mismatched, or reference-typed.
- A grant MAY reject inputs v1 does not support (e.g. non-function
  imports). Grant-time rejection is preferred over instantiate-time
  failure.
- Future executor work that adds real host functions, tier policies, or
  dynamic grant/revoke MUST preserve this invariant: every accepted grant
  is instantiate-ready under the engine it was built with.

## Consequences

- Positive: future executor changes inherit the gate-not-deferred-check
  posture by default; the "three rounds of review to find distinct
  reftype slip-paths" pattern does not repeat.
- Positive: the invariant is citable by reviewers (secrev, devrev,
  entarch) as a binding rule, not an ad-hoc preference.
- Negative: grant implementations become marginally more expensive —
  more validation, fewer short-circuits.
- Negative: enforcement is not machine-checkable in general; reviewers
  still need to apply judgment for executor changes that touch the
  linker or the import resolution path.
- Risks: engine-config drift. A grant built under one wasmtime `Config`
  may not instantiate under a different one if a future change permits
  the executor to run skills under multiple engines. This ADR's
  "under the same engine" clause is load-bearing; any multi-engine
  executor design MUST revisit it.

## References

- `docs/specs/skill-abi-v1.md` — lifecycle and ABI contract
- `lanytehq/lanyte` PR #15 (SKL-004 grant phase) — merged at commit
  `593025b`; forensic trail of the three review rounds that motivated
  this ADR lives in the PR body and the commit messages
  (`03c9353`, `abe7406`, `0239de2`)
- ADR-0007 — autonomy gate architecture (establishes the broader
  "gate, not deferred check" pattern this ADR extends to the executor
  boundary)
- `lanyte-productbook-internal/content/projmgmt/skills-infra/SKL-004-grant-phase.md`
  — the SKL-004 brief
