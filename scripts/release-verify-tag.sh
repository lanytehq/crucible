#!/usr/bin/env bash
# release-verify-tag.sh - Verify a signed git tag
#
# Environment variables:
# - LANYTE_CRUCIBLE_RELEASE_TAG: the tag to verify (required; never derived)
# - LANYTE_CRUCIBLE_GPG_HOMEDIR: dedicated signing keyring directory

set -euo pipefail

repo_root() {
  git rev-parse --show-toplevel
}

main() {
  local root
  root="$(repo_root)"
  cd "$root"

  # shellcheck source=scripts/release-env.sh
  source scripts/release-env.sh
  refuse_legacy_release_env

  local tag
  tag="$(require_release_tag)"

  # Set up GPG homedir if specified
  if [[ -n "${LANYTE_CRUCIBLE_GPG_HOMEDIR:-}" ]]; then
    if [[ ! -d "${LANYTE_CRUCIBLE_GPG_HOMEDIR}" ]]; then
      echo "error: GPG homedir '${LANYTE_CRUCIBLE_GPG_HOMEDIR}' is not a directory" >&2
      exit 1
    fi
    export GNUPGHOME="${LANYTE_CRUCIBLE_GPG_HOMEDIR}"
  fi

  echo "Verifying tag signature: $tag"
  if git verify-tag "$tag" 2>/dev/null; then
    echo ""
    echo "[ok] Tag verified: $tag"
  else
    echo "error: tag verification failed for $tag" >&2
    exit 1
  fi
}

main "$@"
