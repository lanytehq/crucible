#!/usr/bin/env bash
# Controls for explicit release inputs (scripts/release-env.sh and the release
# scripts that source it). Each case runs in a disposable repository with a
# scrubbed environment and asserts the script fails before any side effect: no
# tag is created.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

# A throwaway repository holding copies of the release scripts and a VERSION
# file, so no case can touch this checkout or its tags.
new_repo() {
  local repo="$WORK/repo-$1"
  mkdir -p "$repo/scripts"
  cp "$ROOT"/scripts/release-env.sh "$ROOT"/scripts/release-tag.sh \
    "$ROOT"/scripts/release-verify-tag.sh "$ROOT"/scripts/release-guard-tag-version.sh \
    "$repo/scripts/"
  printf '1.2.3\n' >"$repo/VERSION"
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid add -A
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -q -m init
  printf '%s\n' "$repo"
}

# Run a script with only the given variables set: the developer's own release
# variables cannot leak in.
run_scrubbed() {
  local repo="$1" script="$2"
  shift 2
  (cd "$repo" && env -i PATH="$PATH" HOME="$WORK/home" "$@" bash "scripts/$script")
}

# A refusal must be for the stated reason: the expected message appears on
# stderr. Without this, a script that fails for an unrelated cause (no TTY, no
# signing key) would pass every control and prove nothing.
assert_refuses() {
  local label="$1" script="$2" reason="$3"
  shift 3
  local repo
  repo="$(new_repo "$pass-$fail")"
  if run_scrubbed "$repo" "$script" "$@" >"$WORK/out" 2>"$WORK/err"; then
    echo "[FAIL] expected refusal: $label" >&2
    fail=$((fail + 1))
    return
  fi
  if ! grep -qF -- "$reason" "$WORK/err"; then
    echo "[FAIL] $label: refused for a different reason (wanted: $reason)" >&2
    sed 's/^/       /' "$WORK/err" >&2
    fail=$((fail + 1))
    return
  fi
  if [[ -n "$(git -C "$repo" tag -l)" ]]; then
    echo "[FAIL] $label: refused but a tag was created" >&2
    fail=$((fail + 1))
    return
  fi
  echo "[ok] refuses before side effects: $label"
  pass=$((pass + 1))
}

assert_accepts() {
  local label="$1" script="$2"
  shift 2
  local repo
  repo="$(new_repo "$pass-$fail")"
  if run_scrubbed "$repo" "$script" "$@" >"$WORK/out" 2>"$WORK/err"; then
    echo "[ok] accepts: $label"
    pass=$((pass + 1))
  else
    echo "[FAIL] expected success: $label" >&2
    cat "$WORK/err" >&2
    fail=$((fail + 1))
  fi
}

mkdir -p "$WORK/home"

# The tag is never derived: VERSION is present in every repository.
for script in release-tag.sh release-verify-tag.sh release-guard-tag-version.sh; do
  assert_refuses "$script: no LANYTE_CRUCIBLE_RELEASE_TAG (VERSION present)" "$script" "LANYTE_CRUCIBLE_RELEASE_TAG is required"
  assert_refuses "$script: bare RELEASE_TAG only" "$script" "retired, unprefixed, or other-repository release variable set" RELEASE_TAG=v1.2.3
  assert_refuses "$script: bare RELEASE_TAG beside the prefixed tag" "$script" "retired, unprefixed, or other-repository release variable set" \
    RELEASE_TAG=v1.2.3 LANYTE_CRUCIBLE_RELEASE_TAG=v1.2.3
  assert_refuses "$script: other repository's tag variable" "$script" "retired, unprefixed, or other-repository release variable set" \
    THREELEAPS_CRUCIBLE_RELEASE_TAG=v1.2.3 LANYTE_CRUCIBLE_RELEASE_TAG=v1.2.3
  assert_refuses "$script: retired LANYTE_CRUCIBLE_REQUIRE_TAG" "$script" "retired, unprefixed, or other-repository release variable set" \
    LANYTE_CRUCIBLE_REQUIRE_TAG=1 LANYTE_CRUCIBLE_RELEASE_TAG=v1.2.3
  assert_refuses "$script: malformed tag" "$script" "invalid release tag" LANYTE_CRUCIBLE_RELEASE_TAG=1.2.3
  assert_refuses "$script: leading-zero tag" "$script" "invalid release tag" LANYTE_CRUCIBLE_RELEASE_TAG=v1.02.3
done

# A well-formed explicit tag must still agree with VERSION.
assert_refuses "release-tag.sh: explicit tag that does not match VERSION" release-tag.sh \
  "does not match VERSION" LANYTE_CRUCIBLE_RELEASE_TAG=v9.9.9
assert_refuses "release-guard-tag-version.sh: explicit tag that does not match VERSION" \
  release-guard-tag-version.sh "release tag/version mismatch" LANYTE_CRUCIBLE_RELEASE_TAG=v9.9.9

# The guard accepts an explicit tag that matches VERSION (the CI path).
assert_accepts "release-guard-tag-version.sh: explicit matching tag" \
  release-guard-tag-version.sh LANYTE_CRUCIBLE_RELEASE_TAG=v1.2.3

# Signing keyring (release-tag only). These checks run before any TTY or key
# lookup, so each refusal is reachable and asserted by its message.
OK_TAG=LANYTE_CRUCIBLE_RELEASE_TAG=v1.2.3
DED="$WORK/dedicated-keyring"
mkdir -p "$DED" "$WORK/fakehome" "$WORK/realhome/.gnupg"
ln -s "$DED" "$WORK/keyring-link"
REAL_GNUPG="$(python3 -I -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')/.gnupg"

assert_refuses "keyring: unset" release-tag.sh \
  "LANYTE_CRUCIBLE_GPG_HOMEDIR is required" "$OK_TAG"
assert_refuses "keyring: relative path" release-tag.sh \
  "must be an absolute path to an existing, non-symlink directory" "$OK_TAG" \
  LANYTE_CRUCIBLE_GPG_HOMEDIR=relative/keyring
assert_refuses "keyring: missing directory" release-tag.sh \
  "must be an absolute path to an existing, non-symlink directory" "$OK_TAG" \
  LANYTE_CRUCIBLE_GPG_HOMEDIR="$WORK/no-such-dir"
assert_refuses "keyring: symlink" release-tag.sh \
  "must be an absolute path to an existing, non-symlink directory" "$OK_TAG" \
  LANYTE_CRUCIBLE_GPG_HOMEDIR="$WORK/keyring-link"
# The account's real .gnupg is refused even when HOME points elsewhere: gpgconf
# follows HOME, so only the account-home anchor catches this.
if [[ -d "$REAL_GNUPG" ]]; then
  assert_refuses "keyring: real default with HOME relocated (no .gnupg)" release-tag.sh \
    "resolves to the default GPG keyring" "$OK_TAG" \
    LANYTE_CRUCIBLE_GPG_HOMEDIR="$REAL_GNUPG"
fi
assert_refuses "keyring: GNUPGHOME names a different directory" release-tag.sh \
  "GNUPGHOME is set to a different directory" "$OK_TAG" \
  LANYTE_CRUCIBLE_GPG_HOMEDIR="$DED" GNUPGHOME="$WORK/fakehome"
# GNUPGHOME equal to the dedicated keyring is allowed, and the default is
# resolved with GNUPGHOME unset. Were it not scrubbed, gpgconf would report the
# dedicated keyring as the default and refuse it. The run fails later (no key),
# so the control asserts only that no keyring refusal was the reason.
keyring_accepted_with_gnupghome() {
  local repo
  repo="$(new_repo "$pass-$fail")"
  run_scrubbed "$repo" release-tag.sh "$OK_TAG" LANYTE_CRUCIBLE_GPG_HOMEDIR="$DED" GNUPGHOME="$DED" \
    >"$WORK/out" 2>"$WORK/err" || true
  if grep -qE "LANYTE_CRUCIBLE_GPG_HOMEDIR|GNUPGHOME|default GPG keyring" "$WORK/err"; then
    echo "[FAIL] keyring: GNUPGHOME equal to the dedicated keyring was refused" >&2
    sed 's/^/       /' "$WORK/err" >&2
    fail=$((fail + 1))
  elif [[ -n "$(git -C "$repo" tag -l)" ]]; then
    echo "[FAIL] keyring: GNUPGHOME control created a tag" >&2
    fail=$((fail + 1))
  else
    echo "[ok] accepts: keyring: GNUPGHOME equal to the dedicated keyring (default resolved without it)"
    pass=$((pass + 1))
  fi
}
keyring_accepted_with_gnupghome
assert_refuses "keyring: other repository's keyring variable" release-tag.sh \
  "retired, unprefixed, or other-repository release variable set" "$OK_TAG" \
  LANYTE_CRUCIBLE_GPG_HOMEDIR="$DED" THREELEAPS_CRUCIBLE_GPG_HOMEDIR="$DED"

# git must sign with plain gpg.
assert_refuses_gpg_program() {
  local repo
  repo="$(new_repo "$pass-$fail")"
  git -C "$repo" config gpg.program /usr/bin/false
  if run_scrubbed "$repo" release-tag.sh "$OK_TAG" LANYTE_CRUCIBLE_GPG_HOMEDIR="$DED" \
    >"$WORK/out" 2>"$WORK/err"; then
    echo "[FAIL] expected refusal: configured gpg.program" >&2
    fail=$((fail + 1))
  elif ! grep -qF "release signing requires plain gpg" "$WORK/err"; then
    echo "[FAIL] configured gpg.program: refused for a different reason" >&2
    sed 's/^/       /' "$WORK/err" >&2
    fail=$((fail + 1))
  elif [[ -n "$(git -C "$repo" tag -l)" ]]; then
    echo "[FAIL] configured gpg.program: a tag was created" >&2
    fail=$((fail + 1))
  else
    echo "[ok] refuses before side effects: configured gpg.program"
    pass=$((pass + 1))
  fi
}
assert_refuses_gpg_program

# Designated checker (decernor): explicit absolute path, no fallback.
check_decernor() {
  local label="$1" reason="$2"
  shift 2
  if env -i PATH="$PATH" "$@" bash -c 'source "$1"; resolve_release_decernor' _ \
    "$ROOT/scripts/release-env.sh" >"$WORK/out" 2>"$WORK/err"; then
    echo "[FAIL] expected refusal: $label" >&2
    fail=$((fail + 1))
  elif ! grep -qF -- "$reason" "$WORK/err"; then
    echo "[FAIL] $label: refused for a different reason (wanted: $reason)" >&2
    sed 's/^/       /' "$WORK/err" >&2
    fail=$((fail + 1))
  else
    echo "[ok] refuses: $label"
    pass=$((pass + 1))
  fi
}
printf '#!/bin/sh\necho "notdecernor 9.9.9"\n' >"$WORK/impostor"
chmod +x "$WORK/impostor"
# A well-formed decernor identity, only below the minimum version, so the
# version comparison is what refuses it.
cat >"$WORK/old-decernor" <<'FAKE'
#!/bin/sh
if [ "$2" = "-e" ]; then
  printf 'Version: 0.1.0\nCommit: abc1234\nBuild Date: 2026-01-01\nGo Version: go1.24\nGofulmen: 0.1.0\nCrucible: 0.1.0\n'
else
  echo "decernor 0.1.0"
fi
FAKE
chmod +x "$WORK/old-decernor"
ln -s "$WORK/impostor" "$WORK/decernor-link"
check_decernor "checker: unset" "LANYTE_CRUCIBLE_DECERNOR_BIN is required"
check_decernor "checker: relative path" "must be an absolute path to a regular, executable, non-symlink file" \
  LANYTE_CRUCIBLE_DECERNOR_BIN=bin/decernor
check_decernor "checker: symlink" "must be an absolute path to a regular, executable, non-symlink file" \
  LANYTE_CRUCIBLE_DECERNOR_BIN="$WORK/decernor-link"
check_decernor "checker: not decernor" "is not decernor" \
  LANYTE_CRUCIBLE_DECERNOR_BIN="$WORK/impostor"
check_decernor "checker: below minimum version" "decernor >= 0.1.8 required" \
  LANYTE_CRUCIBLE_DECERNOR_BIN="$WORK/old-decernor"

# Digest-pinned tool install (release-fetch-tool.sh). A fake curl serves a
# local archive, so no case touches the network; each repository commits the
# pin file its case needs.
mkdir -p "$WORK/fakebin" "$WORK/archive"
cat >"$WORK/fakebin/curl" <<'FAKE'
#!/bin/sh
# Serve $FAKE_ARCHIVE for any URL; honor --output.
while [ $# -gt 0 ]; do
  if [ "$1" = "--output" ]; then cp "$FAKE_ARCHIVE" "$2"; exit 0; fi
  shift
done
exit 1
FAKE
chmod +x "$WORK/fakebin/curl"
printf '#!/bin/sh\necho "goneat v0.6.5"\n' >"$WORK/archive/goneat"
chmod +x "$WORK/archive/goneat"
tar -czf "$WORK/goneat_v0.6.5_linux_amd64.tar.gz" -C "$WORK/archive" goneat
good_digest="$(cd "$WORK" && { sha256sum goneat_v0.6.5_linux_amd64.tar.gz 2>/dev/null || shasum -a 256 goneat_v0.6.5_linux_amd64.tar.gz; } | awk '{print $1}')"

check_fetch() {
  local label="$1" reason="$2" pins="$3"
  local repo="$WORK/fetch-$pass-$fail"
  mkdir -p "$repo/scripts" "$repo/config/release" "$repo/dest"
  cp "$ROOT/scripts/release-fetch-tool.sh" "$ROOT/scripts/release-env.sh" "$repo/scripts/"
  printf '%s' "$pins" >"$repo/config/release/goneat-ci-sha256.txt"
  git -C "$repo" init -q -b main
  if (cd "$repo" && env -i PATH="$WORK/fakebin:$PATH" HOME="$WORK/home" \
    FAKE_ARCHIVE="$WORK/goneat_v0.6.5_linux_amd64.tar.gz" \
    bash scripts/release-fetch-tool.sh goneat linux_amd64 "$repo/dest") >"$WORK/out" 2>"$WORK/err"; then
    if [[ -z "$reason" ]]; then
      echo "[ok] accepts: $label"
      pass=$((pass + 1))
    else
      echo "[FAIL] expected refusal: $label" >&2
      fail=$((fail + 1))
    fi
  elif [[ -n "$reason" ]] && grep -qF -- "$reason" "$WORK/err"; then
    if [[ -e "$repo/dest/goneat" ]]; then
      echo "[FAIL] $label: refused but left a binary installed" >&2
      fail=$((fail + 1))
    else
      echo "[ok] refuses: $label"
      pass=$((pass + 1))
    fi
  else
    echo "[FAIL] $label: wrong outcome (wanted: ${reason:-success})" >&2
    sed 's/^/       /' "$WORK/err" >&2
    fail=$((fail + 1))
  fi
}
check_fetch "fetch: pinned digest" "" \
  "${good_digest}  goneat_v0.6.5_linux_amd64.tar.gz"$'\n'
check_fetch "fetch: archive differs from the pinned digest" "does not match the pinned" \
  "$(printf '0%.0s' {1..64})  goneat_v0.6.5_linux_amd64.tar.gz"$'\n'
check_fetch "fetch: no pin for the platform" "expected exactly one pinned goneat archive" \
  "${good_digest}  goneat_v0.6.5_darwin_arm64.tar.gz"$'\n'
check_fetch "fetch: two pins for the platform" "expected exactly one pinned goneat archive" \
  "${good_digest}  goneat_v0.6.5_linux_amd64.tar.gz"$'\n'"${good_digest}  goneat_v0.6.6_linux_amd64.tar.gz"$'\n'
check_fetch "fetch: malformed digest" "malformed digest" \
  "ABC  goneat_v0.6.5_linux_amd64.tar.gz"$'\n'

echo
echo "release input controls: ${pass} passed, ${fail} failed"
((fail == 0))
