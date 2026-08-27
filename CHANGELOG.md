# Changelog

All notable changes to Lanyte Crucible are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**Content policy**: This file carries the most recent ~10 releases. Older
entries are archived in `docs/releases/vX.Y.Z.md`.

## [0.0.1] - 2026-07-15

First tagged release of Lanyte Crucible, the contract repository for the
Lanyte platform: JSON schemas, agent role definitions, platform policies,
and architecture decision records. The tag is signed manually per the
release-signing manual baseline policy
(`docs/policies/release-signing-manual-baseline-policy.md`); CI never
signs. Full release notes in
[`docs/releases/v0.0.1.md`](docs/releases/v0.0.1.md). (Date finalized at
tag time.)

### Added

- **`agentic/dispatch` v0 contract family** — new this release; the
  contracts for a supervised harness-run seam:
  - `run-envelope.schema.json` — one supervised harness run,
    discriminated by outcome, with a per-field trust taxonomy and
    size-bounded sensitive surfaces.
  - `harness-profile.schema.json` — capability/posture evidence as data,
    with validity-condition expiry (a runtime relation, never a stored
    boolean; consumers fail closed).
  - `semantic-validation.md` — versioned semantic layer
    (`dispatch/v0-semantics` 0.1.1) for the invariants JSON Schema
    cannot express.
  - Conforming and negative fixture suites; every negative fixture must
    fail for its stated reason, not merely somehow. Fixtures are
    synthetic and engagement-blind: identity and engagement labels are
    placeholders, enforced by the validator.
  - Family validator (`scripts/validate-dispatch-v0.py`), wired into the
    default `make check` gate as `check-dispatch-v0`.
- **`agentic` v0 / v0.1 schemas** — `role-prompt` (agent role
  definitions), `ledger-entry` (attribution ledger lines with on-disk
  hash chaining), and `agent-state` (structured session checkpoints;
  v0.1 revision raises prose-field bounds), with fixture suites.
- **`common` v0 schemas** — `naming` (shared conventions for role slugs,
  instance names, and scope paths, referenced across schema families).
- **`ipc` v0 schemas** — JSON Schema 2020-12 contracts for the core
  gateway boundary: control/handshake, command, telemetry, error, and
  per-peer channels.
- **Role catalog** (`config/agentic/roles/`) — role definitions for AI
  agent sessions on the platform, each validated against the role-prompt
  schema.
- **Policies pack** (`docs/policies/`) — commit attribution,
  release-signing manual baseline, PR-body vs squash-commit shape, MSRV
  invariant, schema bump, public-docs redaction, and
  audience-appropriate references.
- **Decision records** (`docs/decisions/`) — architecture decision
  records with index, covering repo layout, governance, schema design
  patterns, autonomy gating, audit-event integrity, transport
  reliability, agent-critical file handling, and more.
- **Specifications** (`docs/specs/`) — peer service contract, agent
  coordination bootstrap, agent identity attestation, skill ABI, and
  agent-session conventions.
- **Release rails** — `RELEASE_CHECKLIST.md` (operator procedure for
  signed-tag releases), `make release-tag` / `release-verify-tag` /
  `release-guard-tag-version` targets backed by safety-checked scripts,
  and a tag-push `release` workflow that re-verifies the release surface
  and drafts the GitHub Release. Tags are signed locally by the
  supervisor per the release-signing manual baseline policy; CI never
  signs.

[0.0.1]: https://github.com/lanytehq/crucible/releases/tag/v0.0.1
