#!/usr/bin/env bash
# release-verify-tag.sh - Verify a signed release tag against the committed pin
#
# Verification uses only scripts/verify-pinned-tag.sh, which imports the
# committed public pin into a throwaway keyring and removes it afterwards. The
# default GPG keyring and any ambient GNUPGHOME are never consulted.
#
# Environment variables:
# - LANYTE_CRUCIBLE_RELEASE_TAG: the tag to verify (required; never derived)
# - LANYTE_CRUCIBLE_DECERNOR_BIN: absolute path to the designated checker
#     (required; see scripts/release-env.sh)
#
# Tags up to v0.3.0 predate the committed pins; verify those with the script in
# their own tagged commit.

set -euo pipefail

main() {
  cd "$(git rev-parse --show-toplevel)"

  # shellcheck source=scripts/release-env.sh
  source scripts/release-env.sh
  refuse_legacy_release_env
  local tag
  tag="$(require_release_tag)"
  resolve_release_decernor

  echo "Verifying tag signature: $tag"
  ./scripts/verify-pinned-tag.sh "$tag"
}

main "$@"
