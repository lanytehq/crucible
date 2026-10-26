# Release Checklist (lanytehq/crucible)

Lanyte Crucible is the contract repository for the Lanyte platform: releases are
**signed git tags** (`vX.Y.Z`) that mark stable snapshots of schemas, role
definitions, specifications, policies, and decision records. No binaries are shipped.

Signing follows the
[release-signing manual baseline policy](docs/policies/release-signing-manual-baseline-policy.md):
the supervisor creates the signed tag **locally**; CI verifies the release surface and
drafts the GitHub Release, but never signs. Signing keys never touch CI.

## Variables (Quick Reference)

- `LANYTE_CRUCIBLE_RELEASE_TAG`: the release tag (e.g., `v0.3.1`). **Required** for
  every release target; it is never derived from `VERSION`, `git describe`, or the
  branch. It must match `VERSION`.
- `LANYTE_CRUCIBLE_GPG_HOMEDIR`: dedicated signing keyring directory. **Required**
  to sign; the default GPG keyring is refused, as are an inherited `GNUPGHOME`
  naming a different directory and a `gpg.program` other than `gpg`.
- `LANYTE_CRUCIBLE_DECERNOR_BIN`: absolute path to decernor 0.1.8 or newer.
  **Required** to verify a tag or check the anchors; there is no `PATH` lookup.
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
- Retired, unprefixed, and 3leaps (`THREELEAPS_CRUCIBLE_*`) release variables are
  **refused**, not ignored, including the former `LANYTE_CRUCIBLE_REQUIRE_TAG`
  (see `scripts/release-env.sh`).

> **Why `LANYTE_CRUCIBLE_`?** The prefix disambiguates this repository's release
> environment from other Crucible-style repositories and avoids generic environment
> variable names.

Note: These are not secrets and typically aren't stored in encrypted env bundles.

## After a feature PR merges

- [ ] Run the post-merge epilogue (dry-run first) to drop the task worktree and
      prune — see [docs/guides/post-merge-epilogue.md](docs/guides/post-merge-epilogue.md):
  ```bash
  make post-merge-epilogue WORKTREE=/abs/path/to/task-wt BRANCH=feature/name
  make post-merge-epilogue WORKTREE=... BRANCH=... MAIN_CHECKOUT=... APPLY=1 CONFIRM=1
  ```
- [ ] Prefer `gh run list` / `gh run watch` for CI status (not `gh pr checks`)

## Pre-Release

- [ ] `git status` is clean
- [ ] Quality gates pass: `make check` (repo guards + dispatch family gate +
      epilogue controls) and `make quality` (lint)
- [ ] `CHANGELOG.md` updated (new `## [X.Y.Z] - YYYY-MM-DD` section; tag link added
      to the footer)
- [ ] `docs/releases/vX.Y.Z.md` created
- [ ] `RELEASE_NOTES.md` updated (keep only latest 3 entries)
- [ ] `VERSION` matches the intended tag
- [ ] All changes merged and pushed to `main`
- [ ] CI (`check` workflow) passes on `main`
- [ ] Guard: ensure tag/version match:
  ```bash
  export LANYTE_CRUCIBLE_RELEASE_TAG=vX.Y.Z   # the tag you intend to create
  make release-guard-tag-version
  ```
- [ ] Committed pins match their anchors:
  ```bash
  export LANYTE_CRUCIBLE_DECERNOR_BIN=/absolute/path/to/decernor
  make release-check-anchors
  ```
- [ ] Version-tag ruleset is the full policy (bypass actors included):
  ```bash
  direnv exec . make release-guard-tag-ruleset
  ```

## Tagging (Signed Tag Required)

### 1. Set up GPG environment

```bash
# Enable pinentry prompts
export GPG_TTY="$(tty)"
gpg-connect-agent updatestartuptty /bye

# Dedicated signing keyring (required; never the default keyring)
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
export LANYTE_CRUCIBLE_RELEASE_TAG=vX.Y.Z   # required; must match VERSION
make release-tag
```

The script performs these safety checks before creating the tag:

- `LANYTE_CRUCIBLE_RELEASE_TAG` is set (never derived) and matches `VERSION`;
  retired or unprefixed release variables are refused
- Tag format validation (`vMAJOR.MINOR.PATCH`)
- Clean working tree required
- Must be on `main` branch (set `LANYTE_CRUCIBLE_ALLOW_NON_MAIN=1` to override)
- Tag must not already exist
- Dedicated signing keyring and plain `gpg` required
- GPG signing key availability verified
- Automatic signature verification after creation

### 3. Verify the signed tag against the committed pin

```bash
make release-verify-tag
```

This imports `docs/security/release-signing-keys.asc` from the tagged commit
into a throwaway keyring and requires one good signature by the pinned signing
subkey, with the committed tagger identity. Your own keyring is not consulted.

### 4. Push

Push the tag ref only, over HTTPS with the org token, so the push does not
depend on the clone's `origin` URL (an SSH remote is common on maintainer
clones):

```bash
direnv exec . git -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
  push https://github.com/lanytehq/crucible.git "refs/tags/${LANYTE_CRUCIBLE_RELEASE_TAG}"
```

## Post-Release

- [ ] Verify tag appears on GitHub: https://github.com/lanytehq/crucible/tags
- [ ] Verify the `release` workflow (`.github/workflows/release.yml`) runs on the tag
      push: it verifies the tag against the pin in the tagged commit (decernor and
      goneat installed by digest), re-checks tag/VERSION consistency, release notes,
      CHANGELOG entry, and quality gates, then creates a **draft** GitHub Release from
      `docs/releases/vX.Y.Z.md`
- [ ] Review the draft release, then publish it:
  ```bash
  gh release edit "${LANYTE_CRUCIBLE_RELEASE_TAG}" --repo lanytehq/crucible --draft=false
  ```
- [ ] Spot-check release notes render correctly

### Verify tag signature (optional)

**Against the committed pin** (independent check, from a separate clone):

```bash
export LANYTE_CRUCIBLE_DECERNOR_BIN=/absolute/path/to/decernor
./scripts/verify-pinned-tag.sh "${LANYTE_CRUCIBLE_RELEASE_TAG}"
```

Tags up to and including `v0.3.0` predate the pins; verify those with the
scripts in their own commit.

**GitHub API** (CI-friendly):

```bash
TAG_SHA=$(gh api repos/lanytehq/crucible/git/ref/tags/"${LANYTE_CRUCIBLE_RELEASE_TAG}" --jq .object.sha)
gh api repos/lanytehq/crucible/git/tags/$TAG_SHA --jq .verification
```

**GitHub Web UI note**: A green "Verified" badge only appears if:

1. The signing public key is uploaded to the GitHub account
2. The tagger email matches a verified email on that account

Otherwise GitHub may show "Unverified" even though `git tag -v` succeeds locally.

## Rollback

If issues are discovered after release:

```bash
# Delete the draft/published GitHub release (if created)
gh release delete v<VERSION> --repo lanytehq/crucible

# Delete remote tag
git push origin --delete v<VERSION>

# Delete local tag
git tag -d v<VERSION>

# If VERSION file needs revert
git revert <commit-hash>
```

## Release Tooling Reference

### Make Targets

| Target                           | Purpose                                                     |
| -------------------------------- | ----------------------------------------------------------- |
| `make release-tag`               | Create signed git tag with all safety checks                |
| `make release-verify-tag`        | Verify a tag against the committed pin                      |
| `make release-guard-tag-version` | Verify tag matches VERSION file (CI-friendly)               |
| `make release-check-anchors`     | Re-derive the fingerprint anchors with decernor and compare |
| `make release-guard-tag-ruleset` | Verify the live version-tag ruleset, full policy only       |
| `make release-check-goneat-pin`  | Admit goneat CI digests against goneat's signed checksums   |

### Scripts

All scripts are in `scripts/` and can be run directly if needed.

**`scripts/release-tag.sh`** - The primary release script. Safety checks:

1. Requires `LANYTE_CRUCIBLE_RELEASE_TAG` (never derived); refuses retired or
   unprefixed release variables; validates `vMAJOR.MINOR.PATCH` and that it
   matches `VERSION`
2. Ensures working tree is clean (no uncommitted changes)
3. Ensures on `main` branch (override with `LANYTE_CRUCIBLE_ALLOW_NON_MAIN=1`)
4. Ensures tag doesn't already exist
5. Verifies GPG signing key is available
6. Creates signed annotated tag
7. Automatically verifies signature after creation

**`scripts/release-guard-tag-version.sh`** - Version consistency check:

- Compares `LANYTE_CRUCIBLE_RELEASE_TAG` (required) against the `VERSION` file;
  there is no `git describe` fallback
- CI passes the pushed tag explicitly: `LANYTE_CRUCIBLE_RELEASE_TAG="${GITHUB_REF_NAME}"`
- Exits 0 if match, exits 1 if mismatch or the tag is missing

**`scripts/release-verify-tag.sh`** - Signature verification:

- Verifies `LANYTE_CRUCIBLE_RELEASE_TAG` (required) with
  `scripts/verify-pinned-tag.sh`: pins, anchors, and tagger identity from the
  tagged commit, a throwaway keyring, and the checker from
  `LANYTE_CRUCIBLE_DECERNOR_BIN`

Adoption choices and deviations: [ADR-0020](docs/decisions/adr-0020-release-identity-adoption.md).

---

_Adapted from established release-process patterns._
