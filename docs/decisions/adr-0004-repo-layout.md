---
title: ADR-0004 Repo Layout for Kitsites
description: One kitsite per repo, with a local workspace convention for sibling clones
---

# ADR-0004: Repo Layout for Kitsites

Status: Proposed

## Decision

1. A "kitsite" is a **documentation site built with Kitfly** (a repo containing `site.yaml`), not a special monorepo category.
2. Default model: **one kitsite per repo** (example: `lanyte-runbook`, `lanyte-productbook`).
3. Local development convention (recommended, not enforced):
   - clone related repos as siblings under a single parent folder (example: `~/dev/lanytehq/<repo>`).
4. We do **not** require repos to live under a `kitsites/` subfolder in GitHub (that pattern is a local workbench convenience only).
5. If a monorepo ever hosts multiple kitsites, it MUST NOT mix visibility classes:
   - do not combine public and `*-internal` sites in the same repo.

## Rationale

- Keeps governance and access control simple (public vs private is repo-level, aligns with `*-internal` naming).
- Minimizes accidental leakage by avoiding public/private content adjacency.
- Keeps Kitfly usage flexible (a repo like this one can expose docs via `docs/` with `docroot`, without being “a kitsite repo” structurally).

## Consequences

- Tooling should assume "sibling repos" as the common case, but support explicit paths.
- Docs should describe "kitsite = repo with `site.yaml`" rather than hardcoding filesystem layout.
