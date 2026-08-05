---
title: ADR-0017 Out-of-Band Planning Root
description: Planning and agent-guidance material lives outside repository trees under a conventional root; .gitignore is not a confidentiality gate
---

# ADR-0017: Out-of-Band Planning Root

Status: Proposed

## Context

Delivery work is coordinated through planning material — briefs, review
verdicts, capability maps, session handoffs, machine-local agent guidance —
that must never ship in a repository: it carries internal identifiers,
cross-engagement context, and operational detail that public-bound
repositories exclude by policy (see the [Audience-Appropriate References
Policy](../policies/audience-appropriate-references-policy.md)).

Two anti-patterns keep re-emerging when this material has no designated home:

1. **Planning files inside the repo tree, fenced by `.gitignore`.** A
   `.gitignore` entry is an _accident_ gate, not a confidentiality gate: one
   `git add -f`, one ignore-file refactor, one tool that walks the tree
   ignoring git semantics, and the material is committed or published. If
   content must never be committed, it must never live where a commit can
   reach it.
2. **Committed text referencing the out-of-band location.** A path to
   internal guidance inside a committed file leaks the internal layout and
   dangles for every external reader — a deny reference.

## Decision

1. **Out-of-band material lives outside every repository tree**, under a
   conventional per-org root:

   ```
   <devroot>/<repo-org>/planning/<repo-name>/   # per-repo planning corpus
   <devroot>/<repo-org>/                        # org-level agent guidance
                                                # (machine-local, never committed)
   ```

   where `<devroot>` is the developer root (conventionally `~/dev`).

2. **Roots are environment-variable addressable.** Tooling that needs these
   locations takes them from environment configuration (a developer-root
   variable and an out-of-band-root variable following the ecosystem's
   `*_DEVROOT`-style naming), never from hardcoded paths — the same pattern
   in use in client-facing data-engineering work. Concrete variable names
   bind per deployment; committed tooling refers to the variables, not to
   any specific machine's expansion of them.

3. **`.gitignore` is not a confidentiality gate.** It remains a hygiene tool
   for build artifacts and scratch files. Material that must not be
   committed lives outside the tree per (1); no confidentiality obligation
   may rest on an ignore rule.

4. **The reference direction is one-way.** Out-of-band material may point at
   repositories freely (branch names, commit hashes, PR numbers — this is
   where delivery-to-planning traceability lives). Committed repository
   content never points at out-of-band paths or the variables that locate
   them, beyond the generic statement permitted by the audience policy.

5. **Public-flip audits** (deny-reference scans over the repository corpus)
   verify (4) mechanically before a repository becomes public.

## Consequences

**Positive**

- Confidentiality stops depending on git discipline; the failure mode
  "planning file accidentally committed" becomes structurally impossible
  rather than procedurally discouraged.
- Traceability relocates cleanly: internal records point outward at public
  artifacts, so public artifacts never need to point inward.
- Tooling (dispatch runners, deny-reference scanners, future config-driven
  coordination) gets a stable, machine-readable convention for finding the
  corpus.

**Negative / costs**

- The corpus is per-machine until a sync/backup convention exists; loss of a
  working machine loses uncommitted planning state not otherwise replicated.
- One more environment convention to provision on new machines; mitigated by
  the env-var pattern (a single root variable) and existing machine-setup
  guidance.
