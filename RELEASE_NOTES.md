# Release Notes

Current release notes for Lanyte Crucible. For complete history, see
[CHANGELOG.md](CHANGELOG.md). Per-release archives live in
[docs/releases/](docs/releases/).

**Content policy**: keep the most recent 3 releases in this file
(reverse chronological). Older entries remain only under `docs/releases/`.

---

## v0.1.0 (2026-08-27)

**First public-track release of Lanyte Crucible.** GitHub slug
[`lanytehq/crucible`](https://github.com/lanytehq/crucible). Display name
unchanged.

- **Vessel identity** — clone and docs paths use `lanytehq/crucible`.
- **Public surface** — community health files, `LIFECYCLE_PHASE=alpha`,
  three-org crucible map, role-catalog split vs `3leaps/crucible`.
- **Indexes** — ADR index matches disk; IPC bootstrap list includes
  channel 260.
- **No schema bumps** — contract families are unchanged from `v0.0.1`.

See [docs/releases/v0.1.0.md](docs/releases/v0.1.0.md).

---

## v0.0.1 (2026-07-15)

First tagged release of the platform schema repository. The tag is
signed manually by the supervisor per the release-signing manual
baseline policy (`docs/policies/release-signing-manual-baseline-policy.md`);
CI never signs.

### Contract surface at this tag

| Family             | Version  | Contents                                                                                                                                                                                                                                                                                                                                             |
| ------------------ | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `agentic/dispatch` | v0       | **New.** `run-envelope.schema.json` (supervised harness-run envelope: discriminated outcome model, per-field trust taxonomy, bounded sensitive surfaces) + `harness-profile.schema.json` (capability/posture evidence with validity-condition expiry) + semantic-validation layer `dispatch/v0-semantics` 0.1.1 + conforming/negative fixture suites |
| `agentic`          | v0, v0.1 | role-prompt, ledger-entry, agent-state (unchanged this release)                                                                                                                                                                                                                                                                                      |
| `common`, `ipc`    | v0       | unchanged this release                                                                                                                                                                                                                                                                                                                               |

### Verification

```bash
make check     # repo guards + dispatch family gate (schema lint,
               # fixtures incl. negatives matched to stated reasons,
               # semantic suite, engagement-blind gate)
```

Consumers embedding the dispatch family should pin to this signed tag
and validate their pinned copies byte-for-byte (see the family README
for the dual-validator conformance expectations).

### Notes

- Schemas enforced through vendor structured-output boundaries follow
  the strictest-common-subset policy; tool-validated contract schemas
  use the portable core plus explicitly justified constructs — each
  construct is documented and justified in the family README
  (`schemas/agentic/dispatch/v0/README.md`).
- Fixture corpus is synthetic and engagement-blind: every identity and
  engagement label is a placeholder, never a real name; the validation
  gate enforces this.
- This release establishes the repository's release-documentation
  convention: `CHANGELOG.md` (Keep a Changelog format) and
  `RELEASE_NOTES.md` at the repo root, with per-release notes archived
  under `docs/releases/`.
