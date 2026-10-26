# Verifying a release

This directory is the public identity for lanytehq/crucible releases: the
keys and fingerprints a verifier checks. Nothing here is secret. The layout
follows the 3leaps/crucible release identity record (PDR-0008).

Words used on this page:

- A **release** is a GPG-signed annotated Git tag (`vX.Y.Z`). It is not a
  download, and it is not a checksum file.
- A **pin** is a public key file committed in this repository. A check uses
  the committed copy, never a key fetched from somewhere else.
- An **anchor** is the committed fingerprint of a pin. The checker
  recomputes the fingerprint from the pin and requires the same value.
- The **checker** is decernor 0.1.8 or newer. It computes and compares
  fingerprints. It does not sign the tag.

## What a release carries

A crucible release is a **GPG-signed annotated Git tag** (`vX.Y.Z`). Crucible
publishes no release assets: there are no `SHA256SUMS` or `SHA512SUMS`
files. Their absence is expected, not a failed download. The tag signature
is the only release signature.

## Files

| File                                       | What it is                                                                                              |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `release-signing-keys.asc`                 | Public OpenPGP export: the approved primary key and exactly one signing subkey. This key signs the tag. |
| `crucible-minisign.pub`                    | Minisign public pin for lanytehq releases. It signs no crucible release file.                           |
| `../../keys/expected-fingerprints.txt`     | Two anchors, in order: the OpenPGP primary fingerprint, then the minisign public-blob SHA-256.          |
| `../../keys/expected-fingerprints.ndjson`  | The checker's fingerprint records for the same two keys.                                                |
| `../../config/release/tagger-identity.txt` | The exact tagger name and email a release tag must carry.                                               |

## Which keys these are

The OpenPGP key is the estate release signing key, the same key that signs
3leaps/crucible releases. Its signing subkey signs every tag.

The minisign key belongs to the lanytehq organization. Other organizations
have their own minisign keys, so this pin differs from the one 3leaps
repositories commit. It signs no crucible file today. It is committed
because the checker verifies both keys as a pair and fails if either does
not match its anchor, and so that a first signed download does not also
introduce a new key.

## What to trust

Before you accept the files in this directory, obtain these three values
from a maintainer channel you already trust:

- the OpenPGP primary fingerprint
- the exact signing subkey
- the minisign public-blob fingerprint

A key that arrives beside the signature it is supposed to check is not an
independent check.

## How a tag is checked

Verification reads the pins and anchors from the **tagged commit**, as the
blobs stored in that commit. It does not read a working tree you have
edited, and it does not read the environment. It imports
`release-signing-keys.asc` into an empty keyring and requires one good,
unexpired signature by the pinned signing subkey. The tagger name and email
must match `config/release/tagger-identity.txt`. GitHub's "verified" flag is
an additional check, not a substitute.

## Checker

The anchors are derived and verified by **decernor 0.1.8 or newer**. The
minisign fingerprint covers the decoded public blob, not its comment line
or the whole file. Anchors are derived twice and compared; they are never
typed by hand.

Creating or verifying a release tag takes the checker from
`LANYTE_CRUCIBLE_DECERNOR_BIN`: an absolute path to a regular, executable,
non-symlink file. There is no fallback to `PATH`.

To verify a tag locally:

```bash
export LANYTE_CRUCIBLE_DECERNOR_BIN=/absolute/path/to/decernor
./scripts/verify-pinned-tag.sh vX.Y.Z
```

To check that the committed anchors match the committed exports:

```bash
make release-check-anchors
```

Tags up to and including `v0.3.0` predate these pins: their tagged commits
hold no `docs/security/` or `keys/` files, so this check refuses them. Verify
one of those tags with the release scripts from its own commit. Historical
tags are not re-signed.

## Authorization

A passing tag workflow shows that the checks agreed. It does not authorize
the release. The maintainer's signed tag authorizes publication.
