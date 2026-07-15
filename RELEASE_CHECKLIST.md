# Release Checklist (lanytehq/lanyte-crucible)

lanyte-crucible is the contract repository for the Lanyte platform: releases are
**signed git tags** (`vX.Y.Z`) that mark stable snapshots of schemas, role
definitions, specifications, policies, and decision records. No binaries are shipped.

Signing follows the
[release-signing manual baseline policy](docs/policies/release-signing-manual-baseline-policy.md):
the supervisor creates the signed tag **locally**; CI verifies the release surface and
drafts the GitHub Release, but never signs. Signing keys never touch CI.

## Variables (Quick Reference)

- `LANYTE_CRUCIBLE_RELEASE_TAG`: optional override tag (e.g., `v0.0.1`)
- `LANYTE_CRUCIBLE_GPG_HOMEDIR`: dedicated signing keyring directory (recommended)
- `LANYTE_CRUCIBLE_PGP_KEY_ID`: key id for signing. Set this to the
  **dedicated signing subkey** — the entry carrying the `[S]` usage flag in
  `gpg --list-secret-keys --keyid-format LONG` — suffixed with `!` to force
  exact selection (e.g. `<subkey-id>!`). Never the primary key and never an
  encryption (`[E]`) subkey. Where a keyring carries two `[S]` subkeys, the
  first is for manual operator use and the second is reserved for CI/CD
  automation if that is ever adopted (see the release-signing policy).
- `LANYTE_CRUCIBLE_TAGGER_NAME`: tagger name stamped on signed tag objects
- `LANYTE_CRUCIBLE_TAGGER_EMAIL`: tagger email stamped on signed tag objects
- `LANYTE_CRUCIBLE_ALLOW_NON_MAIN`: set to `1` to allow tagging from non-main branch
- `LANYTE_CRUCIBLE_REQUIRE_TAG`: set to `1` to make the tag/VERSION guard fail when
  HEAD carries no tag (used in CI)

> **Why `LANYTE_CRUCIBLE_`?** The prefix disambiguates this repository's release
> environment from other Crucible-style repositories and avoids generic environment
> variable names.

Note: These are not secrets and typically aren't stored in encrypted env bundles.

## Pre-Release

- [ ] `git status` is clean
- [ ] Quality gates pass: `make check` (repo guards + dispatch family gate) and
      `make quality` (lint)
- [ ] `CHANGELOG.md` updated (new `## [X.Y.Z] - YYYY-MM-DD` section; tag link added
      to the footer)
- [ ] `docs/releases/vX.Y.Z.md` created
- [ ] `RELEASE_NOTES.md` updated (keep only latest 3 entries)
- [ ] `VERSION` matches the intended tag
- [ ] All changes merged and pushed to `main`
- [ ] CI (`check` workflow) passes on `main`
- [ ] Guard: ensure tag/version match:
  ```bash
  make release-guard-tag-version
  ```

## Tagging (Signed Tag Required)

### 1. Set up GPG environment

```bash
# Enable pinentry prompts
export GPG_TTY="$(tty)"
gpg-connect-agent updatestartuptty /bye

# Point to dedicated signing keyring (recommended)
export LANYTE_CRUCIBLE_GPG_HOMEDIR="/path/to/signing-keyring"
export LANYTE_CRUCIBLE_PGP_KEY_ID="your-key-id"

# Stamp the tagger identity to match the signing key (required for a
# "Verified" badge on GitHub when signing with a shared/org key)
export LANYTE_CRUCIBLE_TAGGER_NAME="signing-key-identity-name"
export LANYTE_CRUCIBLE_TAGGER_EMAIL="uid-email-on-the-signing-key"

# Verify key is available
GNUPGHOME="${LANYTE_CRUCIBLE_GPG_HOMEDIR}" gpg --list-secret-keys --keyid-format=long
```

### 2. Create the signed tag (with safety checks)

```bash
make release-tag
```

The script performs these safety checks before creating the tag:

- Tag format validation (`vMAJOR.MINOR.PATCH`)
- Clean working tree required
- Must be on `main` branch (set `LANYTE_CRUCIBLE_ALLOW_NON_MAIN=1` to override)
- Tag must not already exist
- GPG signing key availability verified
- Automatic signature verification after creation

### 3. Verify the signed tag (optional manual check)

```bash
make release-verify-tag
# or:
git tag -v v$(cat VERSION)
```

Expected output includes:

- `gpg: Signature made ...`
- `gpg: Good signature from ...`

### 4. Push

```bash
git push origin main
git push origin v$(cat VERSION)
```

## Post-Release

- [ ] Verify tag appears on GitHub: https://github.com/lanytehq/lanyte-crucible/tags
- [ ] Verify the `release` workflow (`.github/workflows/release.yml`) runs on the tag
      push: it re-checks tag/VERSION consistency, release notes, CHANGELOG entry, and
      quality gates, then creates a **draft** GitHub Release from
      `docs/releases/vX.Y.Z.md`
- [ ] Review the draft release, then publish it:
  ```bash
  gh release edit v$(cat VERSION) --repo lanytehq/lanyte-crucible --draft=false
  ```
- [ ] Spot-check release notes render correctly

### Verify tag signature (optional)

**Local git** (most reliable):

```bash
git fetch --tags origin
git tag -v v$(cat VERSION)
```

**GitHub API** (CI-friendly):

```bash
TAG_SHA=$(gh api repos/lanytehq/lanyte-crucible/git/ref/tags/v$(cat VERSION) --jq .object.sha)
gh api repos/lanytehq/lanyte-crucible/git/tags/$TAG_SHA --jq .verification
```

**GitHub Web UI note**: A green "Verified" badge only appears if:

1. The signing public key is uploaded to the GitHub account
2. The tagger email matches a verified email on that account

Otherwise GitHub may show "Unverified" even though `git tag -v` succeeds locally.

## Rollback

If issues are discovered after release:

```bash
# Delete the draft/published GitHub release (if created)
gh release delete v<VERSION> --repo lanytehq/lanyte-crucible

# Delete remote tag
git push origin --delete v<VERSION>

# Delete local tag
git tag -d v<VERSION>

# If VERSION file needs revert
git revert <commit-hash>
```

## Release Tooling Reference

### Make Targets

| Target                           | Purpose                                       |
| -------------------------------- | --------------------------------------------- |
| `make release-tag`               | Create signed git tag with all safety checks  |
| `make release-verify-tag`        | Verify an existing signed tag                 |
| `make release-guard-tag-version` | Verify tag matches VERSION file (CI-friendly) |

### Scripts

All scripts are in `scripts/` and can be run directly if needed.

**`scripts/release-tag.sh`** - The primary release script. Safety checks:

1. Validates tag format (`vMAJOR.MINOR.PATCH`)
2. Ensures working tree is clean (no uncommitted changes)
3. Ensures on `main` branch (override with `LANYTE_CRUCIBLE_ALLOW_NON_MAIN=1`)
4. Ensures tag doesn't already exist
5. Verifies GPG signing key is available
6. Creates signed annotated tag
7. Automatically verifies signature after creation

**`scripts/release-guard-tag-version.sh`** - Version consistency check:

- Compares current git tag (or `LANYTE_CRUCIBLE_RELEASE_TAG` env var) against `VERSION` file
- Use in CI with `LANYTE_CRUCIBLE_REQUIRE_TAG=1` to enforce tag presence
- Exits 0 if match, exits 1 if mismatch

**`scripts/release-verify-tag.sh`** - Signature verification:

- Verifies GPG signature on the tag for `VERSION` (or `LANYTE_CRUCIBLE_RELEASE_TAG`)
- Respects `LANYTE_CRUCIBLE_GPG_HOMEDIR` for dedicated keyrings

---

_Adapted from established release-process patterns._
