---
title: ADR-0020 Release Identity Adoption
description: lanytehq/crucible adopts the 3leaps/crucible release-identity record (PDR-0008) and records its own choices and deviations
---

# ADR-0020: Release Identity Adoption

## Status

Proposed

## Context

3leaps/crucible PDR-0008 asks each repository that signs releases to commit
its public release identity in the tree, take every release input
explicitly, verify tags in CI against the committed pin, and record in its
own decision lane any control it does not meet.

Before this record, lanytehq/crucible signed tags but committed no pin. The
release scripts derived the tag from `VERSION`, used the default GPG keyring
when no keyring was named, and CI never checked the tag signature.

## Decision

Adopt PDR-0008 with the choices below.

### Public identity

- **OpenPGP key:** the estate release key, the same primary and signing
  subkey that 3leaps/crucible pins, in `docs/security/release-signing-keys.asc`.
- **Minisign key:** the lanytehq organization key, in
  `docs/security/crucible-minisign.pub`. Each organization has its own
  minisign key, so rotating one never touches another. It signs no crucible
  file today; it is pinned now so that a first signed asset does not also
  introduce a key.
- **Anchors:** `keys/expected-fingerprints.{txt,ndjson}`, derived by the
  checker and committed in the same change as the pins.
- **Tagger:** `config/release/tagger-identity.txt`.

### Inputs

| Variable                       | Use                                                  |
| ------------------------------ | ---------------------------------------------------- |
| `LANYTE_CRUCIBLE_RELEASE_TAG`  | Required for every release target; never derived     |
| `LANYTE_CRUCIBLE_DECERNOR_BIN` | Absolute path to decernor >= 0.1.8; no `PATH` lookup |
| `LANYTE_CRUCIBLE_GPG_HOMEDIR`  | Dedicated signing keyring; required to sign          |

Retired, unprefixed, and 3leaps (`THREELEAPS_CRUCIBLE_*`) variables are
refused, not ignored.

The signing keyring refuses the default keyring as named by both `gpgconf`
and the account home read from the user database. `gpgconf` derives its
default from `HOME`, so a relocated `HOME` would hide the real keyring from
`gpgconf` alone. Git signs with `gpg.program=gpg`, because a configured
program may ignore `GNUPGHOME`. The rule behind each of these checks: a
refusal that can be skipped, or that resolves through an input the caller
controls, is not a refusal.

### Checker and CI tools

- **Checker:** decernor 0.1.9 in CI, installed by the archive digest in
  `config/release/decernor-ci-sha256.txt`.
- **goneat:** installed in CI by the archive digest in
  `config/release/goneat-ci-sha256.txt`, replacing an unpinned
  `go install`. The version moves from v0.5.16 to **v0.6.5**. goneat rotated
  its minisign key at v0.6.1, so v0.5.16 is signed by a retired key. Pinning
  v0.6.5 keeps one current trust path. A retired key would have become a new
  trust root that its producer had already rotated out. The digests are
  in the pin file; goneat's current key is committed as
  `docs/security/fulmenhq-goneat-minisign.pub`, SHA-256
  `8d6f8404b2a48bdbca9bbc755e0b54e83c6e58dd3be2fe7219fc2c9d4c68913d`.
- **Stated residual:** GitHub's Ubuntu runners carry no minisign, so in CI
  the trust root is the committed digest. `make release-check-goneat-pin`
  checks those digests against goneat's signed `SHA256SUMS` before they are
  committed. The signature check is defence in depth; the digest path is not
  to be removed in its favor.

### Tag verification in CI

The `release` workflow's verify job installs the checker, restores the
annotated tag from `https://github.com/lanytehq/crucible.git` (never a
configured remote), and verifies it with `scripts/verify-pinned-tag.sh`.
Pins, anchors, and tagger identity are read from the tagged commit, never
from the working tree. A green run is a consistency signal, not release
authorization: the maintainer's signed tag authorizes publication.

### Version-tag ruleset

"Tag Publish Protection" (ruleset `25903946`): target tag, active,
`refs/tags/v*`, rules creation, deletion, non-fast-forward, and update;
only organization administrators may bypass, always. It matches
3leaps/crucible's. `make release-guard-tag-ruleset` reads it and requires the
full policy, bypass actors included.

The guard has **no read-only mode**. 3leaps/crucible's read-only mode treats
an omitted or empty bypass list as success. A credential that cannot see who
may bypass has not shown the boundary, so this repository does not adopt
that mode or the tag attestation that backs it.

### Tag push transport

Release tags are pushed over HTTPS to the fixed repository URL with the
maintainer's organization token through `gh auth git-credential`, with
other credential helpers cleared. They are not pushed through the clone's
`origin`. This is a lanytehq choice, not a PDR-0008 control. A tag ref must
land under the same identity CI verifies, and the organization token is that
identity on every clone, SSH or HTTPS.

The explicit URL is only explicit if nothing between the script and the
wire rewrites it. `make release-push-tag` therefore runs git with global and
system config ignored and injected configuration removed, which clears both
credential helpers and `url.*.insteadOf` for the invocation. It refuses
repository config that sets either, or any `http.*` option: `http.extraheader`
can carry a second credential that the bypass check never saw. gh sees only `GH_TOKEN`, never its stored
logins, and a missing token stops the push. Deleting a tag goes through the
same checks (`make release-delete-remote-tag`), since deletion is in the
ruleset too.

Bypass evidence, recorded 2026-10-26 by a read of
`repos/lanytehq/crucible/rulesets/25903946` with that token, with no tag
pushed: `current_user_can_bypass` is `"always"`. This is GitHub's own rule
evaluation for that credential, so it does not depend on reading the
account's organization role. It is provenance, not the guard: a push
target must assert on a fresh read of the same field before it pushes.

## Deviations

- **Publication profile:** the `create-release` job still drafts the GitHub
  release with `contents: write`, under 3leaps/crucible PDR-0004. Moving to
  maintainer-only publication (PDR-0010) is a separate decision.
- **Historical tags:** tags up to and including `v0.3.0` predate the pins;
  `verify-pinned-tag.sh` refuses them. Verify each with the scripts in its
  own commit. They are not re-signed.

### Controls

Each release guard has an offline control in `make check`, and each control
fails when its guard is removed. A refusal control asserts the stated reason,
not only a non-zero exit. A positive control asserts that it reached its
subject, not merely that nothing refused it. A control that stops at an
earlier check otherwise passes while testing nothing.

`scripts/test-release-tag-pinned.sh` drives the real signing path under a
terminal with a throwaway key, and requires `release-tag` to delete a tag that
does not verify against the committed pin. It needs a checker and a pty, so it
runs by hand (`make test-release-tag-pinned`) rather than in `make check`.

## Consequences

- Positive: a release tag is checked against keys committed in its own
  commit, by one pinned checker, in CI and locally. No release input falls
  back to a default.
- Negative: changing a key, the checker, or goneat is a reviewed change to
  committed pins, not an environment edit.
- Risks: the first tag after adoption is the end-to-end proof. Until it
  exists, CI tag verification has been exercised only on local clones.
