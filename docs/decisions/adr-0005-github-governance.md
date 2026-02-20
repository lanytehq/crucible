---
title: ADR-0005 GitHub Governance and Templates
description: How we use the org-level .github repo and upstream policy/templates
---

# ADR-0005: GitHub Governance and Templates

Status: Proposed

## Decision

1. We will create an org-level repo: `lanytehq/.github` (bootstrap private, target public).
2. `lanytehq/.github` will contain only public-safe content:
   - org profile (`profile/README.md`)
   - baseline community health files (`SECURITY.md`, `SUPPORT.md`, etc.)
   - optional reusable workflows (public-safe)
3. For issue/PR templates in project repos, we will vendor templates from upstream:
   - upstream source: `3leaps/oss-policies` `.github/` folder
   - method: copy (not symlink, not submodule)

## Rationale

- Org-level `.github` gives a consistent baseline without duplicating everything across repos.
- Vendoring per-repo templates avoids the confusion and brittleness of symlinks/submodules.
- We can start by referencing 3leaps OSS policies and migrate to Lanyte-specific policies later if needed.

## Consequences

- Each repo remains self-contained (CI and contributor flows do not rely on local filesystem layouts).
- We need a lightweight “sync templates” process later (candidate home: `lanyte-tools-internal`).
