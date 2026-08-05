# Release Notes

**Content policy**: This file contains the most recent 3 releases (reverse chronological). Older releases are archived in `docs/releases/vX.Y.Z.md`.

## lanyte-crucible v0.0.1

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
