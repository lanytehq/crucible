---
title: Audience-Appropriate References Policy
status: draft
version: 0.1.0
---

# Audience-Appropriate References Policy

An artifact must be self-contained for the audience that actually reads it. A
reference the reader cannot resolve — an internal-only tracking identifier, a
private-repo path, a local-machine filesystem path — is noise to that reader, and
for external audiences it also leaks internal structure. **Write for the audience
of the artifact, not the author's context.**

This is the resolvability companion to the [Public Docs Redaction
Policy](./public-docs-redaction.md): that policy governs *sensitive* content
(security / attacker-enablement); this one governs *resolvability* (can the reader
make sense of what you referenced). Both reduce to "write for the public audience."

## Default Disposition

External-facing artifacts reference only what their audience can resolve.
Internal-only tracking identifiers and internal-only resources stay in
internal-audience surfaces. When unsure whether an artifact is external-facing,
treat it as external-facing.

## When Applies

When authoring or editing any artifact that may be read outside the internal team —
most acutely in repositories that are public or are about to become public. The
release that flips a repo from private to public is the natural enforcement point.

## Practice

References are governed by the audience of the surface they live on. Three tiers:

### Tier 1 — External-facing

Release notes, CHANGELOG, README, public documentation sites, CLI `--help`, error
messages, and issue/PR text in public repositories.

- Self-contained plain language: state *what changed and why* in terms the reader
  understands without internal context.
- Do **not** use load-bearing internal tracking identifiers, and do not reference
  internal-only resources (private repositories, internal documentation trees,
  local filesystem paths).
- An internal identifier may appear only as a clearly optional, non-load-bearing
  parenthetical that adds nothing the prose does not already carry — prefer
  omitting it.

### Tier 2 — Maintainer-facing, public-when-flipped

Commit messages, PR bodies, and source-code comments.

- The prose must stand alone: a reader without access to the internal tracker must
  understand the change.
- An internal tracking identifier as a trailing parenthetical or trailer, for
  traceability, is acceptable — it reads as ordinary project tracking.
- **No history rewrite is required.** Historical commits are grandfathered; the
  cost of rewriting early-stage history (broken hashes, signatures, cross-refs)
  exceeds the value, and a parenthetical identifier in `git log` is not a leak.

### Tier 3 — Internal-only

Internal productbook/runbook content and coordination channels. Internal
identifiers and internal references are used freely here; this is their home.

### Public-facing agent guidance and contributor docs

`AGENTS.md`, `CONTRIBUTING`, and prompt files (local or in-repo) follow Tier 1 once
their repository is public:

- They must be self-contained and reference only publicly resolvable resources —
  not private repositories, internal doc trees, or local-machine paths.
- A prompt/AGENTS file **should** reference this policy, but **audience-safely**:
  do not express the rule as a deny-list of internal identifier prefixes. Naming
  those prefixes both leaks the internal taxonomy and is meaningless to an outside
  reader — the same failure the policy exists to prevent. State the principle
  generically, e.g.: *"External-facing artifacts must be self-contained and must
  not rely on internal-only tracking identifiers or resources that external
  readers cannot resolve."*

This policy models its own rule: as a private SSOT document it may illustrate with
concrete internal examples; any **public** rendition states the principle
generically.

## Cross-References

- [`public-docs-redaction.md`](./public-docs-redaction.md) — sibling: sensitive-content redaction (security) vs. this policy's resolvability (comprehensibility).
- [`pr-body-vs-squash-commit-shape-policy.md`](./pr-body-vs-squash-commit-shape-policy.md) — the Tier-2 commit-vs-PR audience split; this policy generalizes that two-audience discipline to all reference use.
- **Public-citation mechanism (open):** how a *public* repo cites a galaxy policy whose SSOT lives in *private* crucible is unresolved — it is tracked with the org-root `AGENTS.md` canonical-location work. Until a publicly resolvable policy mirror exists, a public repo states the relevant rule inline (self-contained) rather than linking into private crucible.

## History

- **0.1.0 (2026-06-02)** — established at chanvoy's public-flip (v0.2.2 release), where release notes structured around internal brief identifiers surfaced the gap. Driver: external-facing artifacts must resolve for external readers, and the rule must itself avoid naming internal identifiers in any public rendition.
