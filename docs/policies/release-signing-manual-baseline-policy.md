---
title: Release Signing Manual Baseline Policy
status: draft
version: 0.1.0
---

# Release Signing Manual Baseline Policy

This policy governs signing in release pipelines across Rust release-shipping repositories in the Lanyte ecosystem (lanytehq, 3leaps, fulmenhq). It answers one question:

**Should release signing be automated in CI or run manually?** Default: **manual, the supervisor runs it locally.**

## Default Disposition

**Release signing is manual. The human supervisor (typically `@3leapsdave`) runs signing locally; CI builds and drafts the release, but does not sign.**

This is the baseline pattern across `seclusor`, `kitfly`, `sfetch`, `chanvoy` (v0.2.2+), and any future Rust release-shipping repo. The single exception across the galaxy is `fulmenhq/fulmen-toolbox`, which uses GHA-automated cosign — **not the pattern to mirror by default**.

## When This Policy Applies

Any Rust release-shipping repository in the Lanyte ecosystem that produces signed binary releases. Concretely: any repo whose release flow involves `minisign` / `gpg` / `cosign` signature production over release artifacts.

Applies to:

- Brief drafting for release infrastructure (signing rails, release workflows, RELEASE_CHECKLIST.md authoring)
- New-repo provisioning when release tooling is set up
- Reviewing release-related PRs

Does NOT apply to: pre-release CI checks (lints, tests, security scans — those stay in CI), build matrix and draft-release creation (CI continues to do this), or one-off package signing outside the release pipeline.

## Practice

### Pipeline shape

1. **Tag push** triggers `.github/workflows/release.yml`.
2. **CI builds cross-platform binaries** + creates **draft GitHub release** with binaries, checksums, public keys, release notes. **CI does not sign anything.**
3. **Supervisor runs locally**:
   ```
   make release-download   # pull draft artifacts
   make release-sign       # minisign + GPG over binaries + checksums
   make release-verify     # validate signatures locally
   make release-upload     # attach signed artifacts to draft release
   make release-undraft    # flip draft → published
   ```
4. **Release announcement** posted by the supervisor (channel announcement, social, etc.).

### Why manual

Signing keys carry passphrases that are not in CI secrets. Putting passphrase-protected keys in CI requires either:

- Stripping the passphrase (weakens at-rest protection), or
- Storing the passphrase as a CI secret (widens the trust surface to include CI runners, GitHub Actions infrastructure, and any workflow file that could exfiltrate the secret).

Neither trade is acceptable for the Lanyte release-trust posture. Manual signing keeps the passphrase in the supervisor's local environment.

The GPG key has a separate **automation-variant** intended for future GHA adoption. It has not been adopted across the galaxy. Adoption is a per-repo decision, not the platform default.

### New-repo signing-key provisioning

When a new repo enters the Tier-1 release pipeline:

- **Dispatch provisions** the signing key material (minisign + GPG) in the internal devsecops credential store for the repo. Do not document internal credential paths or key-material filenames in public-facing repo docs.
- Tier-1 release work cannot begin until provisioning is complete. Brief authoring can begin in advance; final fingerprint values pin at impl time after provisioning lands.
- Per-repo signing key material follows the internal dispatch-maintained convention; operators with a need to run signing consult the internal runbook/reference for the exact source path.

### When to propose GHA-automated signing

GHA-automated signing is a **separate downstream brief**, never bundled with headline signing work in the same PR. If automation is in scope for a specific repo:

1. File a dedicated brief framing it as "future automation candidate using the unused GHA-variant key" (or `cosign` if migrating from `minisign`/`gpg`).
2. Cite this policy as the baseline being deviated from.
3. Document the trust-surface trade in the brief's §Resolved Decisions.

The `fulmenhq/fulmen-toolbox` cosign exception exists as prior art — read its release surface as a reference, but do not mirror it by default.

## Cross-References

- **`schema-bump-policy.md`** — companion policy on a related "default-no" platform stance (schema bumps require really-good-reason justification; same shape as "GHA signing requires really-good-reason justification").
- **Per-repo `RELEASE_CHECKLIST.md`** files (e.g., chanvoy's per PER-030) — the operator-facing procedure that implements this policy. Each release-shipping repo carries its own checklist; this policy carries the platform-baseline contract.

## History

- **0.1.0 (2026-05-16)** — initial draft. Consolidates the prior session-memory reference on the manual-signing baseline into a platform-public policy. Triggered by the PR 1 cross-repo SSOT framing from dispatch 2026-05-14. Chanvoy v0.2.2 release infrastructure (PER-030 + PER-031) is the immediate consumer.
