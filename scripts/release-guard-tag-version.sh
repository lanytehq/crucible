#!/usr/bin/env bash
# release-guard-tag-version.sh - Verify tag matches VERSION file
#
# Use in CI to ensure version consistency, or before tagging locally.
#
# Environment variables:
# - LANYTE_CRUCIBLE_RELEASE_TAG: the tag to check (required; never derived)

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

  # shellcheck source=scripts/release-env.sh
  source scripts/release-env.sh
  refuse_legacy_release_env

  local version
  version="$(read_version)"

  local expected="v${version}"
  local tag
  tag="$(require_release_tag)"

  if [[ "$tag" != "$expected" ]]; then
    echo "error: release tag/version mismatch" >&2
    echo "  tag:     $tag" >&2
    echo "  VERSION: $version (expected tag: $expected)" >&2
    exit 1
  fi

  echo "[ok] release guard: tag matches VERSION ($tag)"
}

main "$@"
