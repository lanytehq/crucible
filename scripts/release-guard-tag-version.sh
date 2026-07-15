#!/usr/bin/env bash
# release-guard-tag-version.sh - Verify tag matches VERSION file
#
# Use in CI to ensure version consistency, or before tagging locally.
#
# Environment variables:
# - LANYTE_CRUCIBLE_RELEASE_TAG: override tag to check
# - LANYTE_CRUCIBLE_REQUIRE_TAG: set to 1 to fail if no tag found (for CI)

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

detect_tag() {
  if [[ -n "${LANYTE_CRUCIBLE_RELEASE_TAG:-}" ]]; then
    printf '%s' "${LANYTE_CRUCIBLE_RELEASE_TAG}"
    return 0
  fi
  # Try to detect from current HEAD
  git describe --tags --exact-match 2>/dev/null || true
}

main() {
  local root
  root="$(repo_root)"
  cd "$root"

  local version
  version="$(read_version)"

  local expected="v${version}"
  local tag
  tag="$(detect_tag)"

  if [[ -z "$tag" ]]; then
    if [[ "${LANYTE_CRUCIBLE_REQUIRE_TAG:-}" == "1" ]]; then
      echo "error: no exact tag found for HEAD and no LANYTE_CRUCIBLE_RELEASE_TAG provided" >&2
      exit 1
    fi
    echo "[--] release guard: no tag detected (set LANYTE_CRUCIBLE_REQUIRE_TAG=1 to enforce in CI)"
    exit 0
  fi

  if [[ "$tag" != "$expected" ]]; then
    echo "error: release tag/version mismatch" >&2
    echo "  tag:     $tag" >&2
    echo "  VERSION: $version (expected tag: $expected)" >&2
    exit 1
  fi

  echo "[ok] release guard: tag matches VERSION ($tag)"
}

main "$@"
