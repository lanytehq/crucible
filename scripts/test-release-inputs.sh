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

echo
echo "release input controls: ${pass} passed, ${fail} failed"
((fail == 0))
