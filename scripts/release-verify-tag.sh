#!/usr/bin/env bash
# release-verify-tag.sh - Verify a signed git tag
#
# Environment variables:
# - LANYTE_CRUCIBLE_RELEASE_TAG: override tag to verify (default: v$(cat VERSION))
# - LANYTE_CRUCIBLE_GPG_HOMEDIR: dedicated signing keyring directory

set -euo pipefail

repo_root() {
  git rev-parse --show-toplevel
}

read_version() {
  if [[ ! -f VERSION ]]; then
    echo "error: VERSION file not found" >&2
    exit 1
  fi
  tr -d ' \t\r\n' <VERSION
}

main() {
  local root
  root="$(repo_root)"
  cd "$root"

  local version
  version="$(read_version)"

  local tag="${LANYTE_CRUCIBLE_RELEASE_TAG:-v${version}}"

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
