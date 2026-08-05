---
title: Platform Policies
status: active
version: 0.1.0
---

# Platform Policies

`lanyte-crucible/docs/policies/` is the **platform-policy SSOT** for the Lanyte ecosystem. Policies here apply across **lanytehq, 3leaps, fulmenhq, enacthq, namelens, and any future galaxy-organization repositories** — schema rules, contributor conventions, release discipline, attribution invariants. Per-repo `AGENTS.md` files cite these policies; they do not duplicate the policy text.

This directory is the companion to `docs/specs/` (normative interface contracts) and `docs/decisions/` (ADRs). Policies describe **what rules apply when changing the surface**; specs describe **what the surface is**; ADRs describe **why a specific decision was made**.

## Active policies

| Policy                                                                                     | Topic                                                                                                                                             |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`public-docs-redaction.md`](./public-docs-redaction.md)                                   | What goes in public-visible docs vs. operationally sensitive details                                                                              |
| [`schema-bump-policy.md`](./schema-bump-policy.md)                                         | Default disposition + bar for bumping versioned schemas                                                                                           |
| [`commit-attribution-policy.md`](./commit-attribution-policy.md)                           | Commit + PR attribution conventions (Co-Authored-By, Drafted-By, anti-spoofing email format)                                                      |
| [`release-signing-manual-baseline-policy.md`](./release-signing-manual-baseline-policy.md) | Manual-signing baseline for Rust release-shipping repos; CI builds draft only                                                                     |
| [`pr-body-vs-squash-commit-shape-policy.md`](./pr-body-vs-squash-commit-shape-policy.md)   | Two-audience discipline: PR body for reviewers-now vs. squash-commit for git-log-readers-years-out                                                |
| [`msrv-invariant-policy.md`](./msrv-invariant-policy.md)                                   | Minimum Supported Rust Version invariant for lanyte crates; bump-forward discipline                                                               |
| [`audience-appropriate-references-policy.md`](./audience-appropriate-references-policy.md) | References must resolve for the artifact's audience; external-facing surfaces stay self-contained (no internal-only tracking IDs / private paths) |

_(Add rows as future policies land. Keep alphabetical or grouping by domain when count justifies it.)_

## Authoring conventions

When drafting a new policy:

- **Lowercase-kebab filename**: `<topic>-policy.md`.
- **Frontmatter**: `title`, `status` (`draft` → `active` on merge), `version` (semver, starts at `0.1.0`).
- **Section structure**: brief framing → Default Disposition (or equivalent statement) → When Applies → Bar (only if there's a justification gate) → Practice (generic name for the rules section) → Cross-References → History.
- **History block format**: `**{version} ({YYYY-MM-DD})** — {driver, one sentence}.` Append minor edits as new lines under the same version; bump version for substantive change.
- **Crucible-is-SSOT framing**: the policy lives here once; per-repo AGENTS.md files cite it. Do not duplicate the policy body across repos.

## Citing a policy from a repo AGENTS.md

The minimum-thin treatment is a cite + one-sentence default:

> ### {Topic}
>
> Governed by the [{Topic} Policy](https://github.com/lanytehq/lanyte-crucible/blob/main/docs/policies/{topic}-policy.md). Default: {one-sentence default}.

Expand the citation only when the policy is invoked frequently inside the citing repo (e.g., schema changes inside crucible itself warrant the topic-list expansion in `lanyte-crucible/AGENTS.md` §Schema changes). The high-water mark is "expand the thin-out only when the policy is invoked frequently inside the citing repo."

## History

- **0.1.0 (2026-05-16)** — README established alongside the first cross-repo policies pack (PR 2 of the policies/AGENTS.md split). Sibling to `schema-bump-policy.md` (landed PR 1, 2026-05-15). Formalizes the platform-policy SSOT framing dispatch flagged during PR 1 review.
- **0.1.0 (2026-06-02)** — added `audience-appropriate-references-policy.md`; established at chanvoy's public-flip when release notes structured around internal brief identifiers surfaced the gap.
- **0.2.0 (2026-07-15)** — audience-appropriate-references policy revised on two-lens review (Tier 2 excludes internal planning identifiers entirely; traceability relocated out of band per ADR-0017); pr-body-vs-squash-commit-shape policy aligned in the same change (PR body = short reviewer orientation, not a discovery snapshot).
