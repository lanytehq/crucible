#!/usr/bin/env bash
# Negative controls for release-guard-tag-ruleset.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The source path is resolved relative to this script at runtime.
# shellcheck disable=SC1091
source "${script_dir}/release-guard-tag-ruleset.sh"

valid_ruleset='{
  "name": "Tag Publish Protection",
  "target": "tag",
  "source_type": "Repository",
  "source": "lanytehq/crucible",
  "enforcement": "active",
  "conditions": {"ref_name": {"exclude": [], "include": ["refs/tags/v*"]}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "creation"},
    {"type": "update"}
  ],
  "bypass_actors": [
    {"actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always"}
  ]
}'

expect_rejected() {
    local description="$1"
    local candidate="$2"
    if validate_ruleset_json "${candidate}" >/dev/null 2>&1; then
        echo "error: negative control was accepted: ${description}" >&2
        exit 1
    fi
    echo "[ok] rejected: ${description}"
}

validate_ruleset_json "${valid_ruleset}"
echo "[ok] accepted: exact publication policy"

expect_rejected "repository-admin bypass" \
    "$(jq '.bypass_actors += [{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]' <<<"${valid_ruleset}")"
expect_rejected "wrong tag-ref pattern" \
    "$(jq '.conditions.ref_name.include = ["refs/tags/*"]' <<<"${valid_ruleset}")"
expect_rejected "missing update protection" \
    "$(jq '.rules |= map(select(.type != "update"))' <<<"${valid_ruleset}")"
expect_rejected "additional required-status-check rule" \
    "$(jq '.rules += [{"type":"required_status_checks","parameters":{"required_status_checks":[]}}]' <<<"${valid_ruleset}")"
expect_rejected "inactive enforcement" \
    "$(jq '.enforcement = "disabled"' <<<"${valid_ruleset}")"
expect_rejected "missing API response" ""
expect_rejected "malformed API response" "not-json"

redacted_ruleset="$(jq 'del(.bypass_actors)' <<<"${valid_ruleset}")"
null_bypass_ruleset="$(jq '.bypass_actors = null' <<<"${valid_ruleset}")"
empty_bypass_ruleset="$(jq '.bypass_actors = []' <<<"${valid_ruleset}")"
expect_rejected "omitted bypass actors" "${redacted_ruleset}"
expect_rejected "null bypass actors" "${null_bypass_ruleset}"
expect_rejected "empty bypass actors" "${empty_bypass_ruleset}"

# There is no read-only mode to fall back to: the flag itself is refused.
if output="$(main --read-only 2>&1)"; then
    echo "error: --read-only was accepted" >&2
    exit 1
fi
if ! grep -qF 'the guard has one mode: the full policy' <<<"$output"; then
    echo "error: --read-only refused for the wrong reason: ${output}" >&2
    exit 1
fi
echo "[ok] rejected: --read-only argument"

# Require stable byte transport from jq when reading ruleset ids.
binary_ruleset="$(
    jq() {
        if [ "${1:-}" != -b ]; then
            echo 'error: ruleset ID producer omitted jq binary mode' >&2
            return 2
        fi
        command jq "$@"
    }
    gh() {
        case "${*: -1}" in
            'repos/lanytehq/crucible/rulesets?per_page=100')
                printf '%s\n' '[[{"id":123,"name":"Tag Publish Protection"}]]'
                ;;
            repos/lanytehq/crucible/rulesets/123) printf '%s\n' "$valid_ruleset" ;;
            *) return 2 ;;
        esac
    }
    resolve_live_ruleset
)"
if [[ "$binary_ruleset" != "$valid_ruleset" ]]; then
    echo 'error: binary-mode ruleset ID control failed' >&2
    exit 1
fi
# A failed GitHub read (for example an authentication error) must refuse as a
# read failure, never parse as an empty ruleset list.
expect_read_failure() {
    local description="$1" failing_call="$2" output
    if output="$(
        gh() {
            case "${*: -1}" in
                'repos/lanytehq/crucible/rulesets?per_page=100')
                    [ "$failing_call" = list ] && {
                        echo 'gh: Bad credentials (HTTP 401)' >&2
                        return 1
                    }
                    printf '%s\n' '[[{"id":123,"name":"Tag Publish Protection"}]]'
                    ;;
                repos/lanytehq/crucible/rulesets/123)
                    [ "$failing_call" = detail ] && {
                        echo 'gh: Bad credentials (HTTP 401)' >&2
                        return 1
                    }
                    printf '%s\n' "$valid_ruleset"
                    ;;
                *) return 2 ;;
            esac
        }
        resolve_live_ruleset 2>&1
    )"; then
        echo "error: ${description} was accepted" >&2
        exit 1
    fi
    if ! grep -q 'could not read .* from GitHub; the ruleset was not checked' <<<"$output"; then
        echo "error: ${description} refused for the wrong reason: ${output}" >&2
        exit 1
    fi
    if grep -q 'found 0' <<<"$output"; then
        echo "error: ${description} was reported as a missing ruleset" >&2
        exit 1
    fi
    echo "[ok] rejected: ${description}"
}
expect_read_failure "failed ruleset list read" list
expect_read_failure "failed ruleset detail read" detail

echo "[ok] tag-ruleset guard negative controls passed"
