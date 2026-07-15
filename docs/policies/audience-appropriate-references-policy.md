---
title: Audience-Appropriate References Policy
status: draft
version: 0.2.0
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
out-of-band internal surfaces. When unsure whether an artifact is
external-facing, treat it as external-facing.

**The test is public resolvability, not internality.** A reference is
acceptable on a public-bound surface exactly when the artifact's audience can
resolve it: repository issue/PR numbers, commit hashes, public specifications,
and role names from the published role catalog are resolvable and therefore
fine — including in attribution trailers. An internal planning identifier or a
private path is not resolvable and therefore is not.

## When Applies

When authoring or editing any durable artifact in a repository that is public
or **public-bound** (intended to become public — the default for
Lanyte-ecosystem platform repositories, including this one). Enforcement
begins at the **first durable artifact**, not at the public flip: history is
immutable, so contamination written today is contamination shipped later. The
flip itself is an audit checkpoint (deny-reference scan over the corpus), not
the start of the obligation.

## Practice

References are governed by the audience of the surface they live on. Three tiers:

### Tier 1 — External-facing

Release notes, CHANGELOG, README, public documentation sites, CLI `--help`, error
messages, and issue/PR text in public repositories.

- Self-contained plain language: state *what changed and why* in terms the reader
  understands without internal context.
- Do **not** use internal tracking identifiers in any form, and do not reference
  internal-only resources (private repositories, internal documentation trees,
  local filesystem paths). There is no "optional parenthetical" allowance on
  this tier: if the prose needs the identifier, the prose is not self-contained;
  if it does not, the identifier is pure leak surface.

### Tier 2 — Maintainer-facing, public-when-flipped

Commit messages, PR bodies, branch names, and source-code comments in public or
public-bound repositories.

- The prose must stand alone: a reader without access to internal trackers must
  fully understand the change.
- **Prospectively, internal planning identifiers do not appear on these
  surfaces at all** — not as parentheticals, not as trailers, not in branch
  names. Traceability is not lost; it is **relocated**: the mapping from
  delivered work to internal planning records lives in the out-of-band
  planning corpus (see [ADR-0017](../decisions/adr-0017-oob-planning-root.md)),
  which records branch names, commit hashes, and PR numbers on the internal
  side of the boundary. The public artifact never needs to point inward,
  because the internal record points outward.
- Publicly resolvable references remain welcome: issue/PR numbers, commit
  hashes, public spec citations, and bare role names in attribution trailers
  (the role catalog is published; a role name is a resolvable reference, not
  an opaque identifier).
- **No history rewrite.** Commits predating this rule are grandfathered; the
  cost of rewriting history (broken hashes, signatures, cross-refs) exceeds
  the value, and a legacy parenthetical identifier in `git log` is noise, not
  a leak. The public-flip audit notes grandfathered instances rather than
  scrubbing them.

### Tier 3 — Internal-only

Internal productbook/runbook content, coordination channels, and the
out-of-band planning corpus. Internal identifiers and internal references are
used freely here; this is their home — and specifically the home of the
delivery-to-planning traceability that Tier 2 excludes from committed text.

### Public-facing agent guidance and contributor docs

`AGENTS.md`, `CONTRIBUTING`, and prompt files (local or in-repo) follow Tier 1 once
their repository is public:

- They must be self-contained and reference only publicly resolvable resources —
  not private repositories, internal doc trees, or local-machine paths.
- **Committed text never references out-of-band guidance or planning paths**
  (machine-local `AGENTS.local.md` files, the out-of-band planning corpus, or
  the environment variables that locate them). An out-of-band path in a
  committed file is a deny reference: it leaks the internal layout and
  dangles for every external reader. The out-of-band side may point at the
  repo freely; the repo never points back.
- A prompt/AGENTS file **should** reference this policy, but **audience-safely**:
  do not express the rule as a deny-list of internal identifier prefixes. Naming
  those prefixes both leaks the internal taxonomy and is meaningless to an outside
  reader — the same failure the policy exists to prevent. State the principle
  generically, e.g.: *"External-facing artifacts must be self-contained and must
  not rely on internal-only tracking identifiers or resources that external
  readers cannot resolve."*

This policy models its own rule: it is written to be publicly readable as-is —
principles stated generically, no internal identifier taxonomy enumerated.

## Cross-References

- [`public-docs-redaction.md`](./public-docs-redaction.md) — sibling: sensitive-content redaction (security) vs. this policy's resolvability (comprehensibility).
- [`pr-body-vs-squash-commit-shape-policy.md`](./pr-body-vs-squash-commit-shape-policy.md) — the durable-vs-snapshot audience split for PR bodies and squash commits; aligned to this policy at its 0.2.0 revision (PR bodies are minimal public surfaces, not traceability stores).
- [`adr-0017-oob-planning-root.md`](../decisions/adr-0017-oob-planning-root.md) — where relocated traceability lives: the out-of-band planning corpus layout and the principle that `.gitignore` is not a confidentiality gate.
- **Public citation:** this repository is public-bound; once flipped, galaxy policies are cited by their canonical public URL. Until a given consumer repo can resolve that link for its own audience, it states the relevant rule inline (self-contained) rather than linking into a private tree.

## History

- **0.2.0 (2026-07-15)** — tightened to match hardened delivery practice, on
  two-lens review of the original draft: Tier 1 parenthetical allowance
  removed; Tier 2 rewritten to exclude internal planning identifiers entirely
  (commits, PR bodies, branch names) with traceability relocated to the
  out-of-band planning corpus; branch names added as a Tier 2 surface;
  out-of-band paths declared deny references in committed text; resolvability
  stated as the governing test (role names and public references explicitly
  fine); enforcement moved from public-flip to first durable artifact;
  private-SSOT rendition language removed (repository is public-bound).
- **0.1.0 (2026-06-02)** — established at chanvoy's public-flip (v0.2.2 release), where release notes structured around internal brief identifiers surfaced the gap. Driver: external-facing artifacts must resolve for external readers, and the rule must itself avoid naming internal identifiers in any public rendition.
