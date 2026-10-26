#!/usr/bin/env bash
# release-guard-tag-ruleset.sh - Verify the version-tag publication boundary
#
# Reads the "Tag Publish Protection" ruleset of lanytehq/crucible through gh
# and requires the complete policy, bypass actors included: target tag,
# active, include only refs/tags/v*, rules creation/deletion/non_fast_forward/
# update, and only organization administrators may bypass, always.
#
# There is no read-only mode. A response that omits bypass_actors or returns
# an empty list fails: a credential that cannot see who may bypass has not
# shown the boundary. A failed GitHub read is reported as a read failure,
# never as a missing ruleset.
#
# Usage: release-guard-tag-ruleset.sh   (gh credential from the org root)

set -euo pipefail

readonly EXPECTED_REPOSITORY="lanytehq/crucible"
readonly EXPECTED_RULESET_NAME="Tag Publish Protection"

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: ${command_name} not found in PATH" >&2
        exit 1
    fi
}

validate_ruleset_json() {
    local ruleset_json="${1:-}"
    local failed=0

    assert_shape() {
        local description="$1"
        local filter="$2"
        if ! jq -e "${filter}" >/dev/null 2>&1 <<<"${ruleset_json}"; then
            echo "error: tag ruleset ${description}" >&2
            failed=1
        fi
    }

    assert_shape "must be named '${EXPECTED_RULESET_NAME}'" \
        ".name == \"${EXPECTED_RULESET_NAME}\""
    assert_shape "must belong to repository '${EXPECTED_REPOSITORY}'" \
        ".source_type == \"Repository\" and .source == \"${EXPECTED_REPOSITORY}\""
    assert_shape "must target tags and be active" \
        '.target == "tag" and .enforcement == "active"'
    assert_shape "must include only refs/tags/v* with no exclusions" \
        '.conditions == {"ref_name":{"exclude":[],"include":["refs/tags/v*"]}}'
    assert_shape "must contain only creation, deletion, non-fast-forward, and update protections" \
        '(.rules | length) == 4 and
         ([.rules[].type] | sort) == ["creation","deletion","non_fast_forward","update"] and
         all(.rules[]; (keys | sort) == ["type"])'
    assert_shape "must allow only organization administrators to bypass, always" \
        '.bypass_actors == [{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"always"}]'

    if [ "${failed}" -ne 0 ]; then
        return 1
    fi
}

# Report a failed GitHub API read as a read failure. Without this, an
# authentication error yields empty output that parses as zero rulesets.
github_read_failed() {
    local what="$1"
    echo "error: could not read ${what} from GitHub; the ruleset was not checked" >&2
    echo "hint: this is usually an expired, revoked or under-scoped credential" >&2
    echo "hint: run gh through the org root's direnv (RELEASE_CHECKLIST.md)" >&2
    exit 1
}

resolve_live_ruleset() {
    require_command gh
    require_command jq

    local ruleset_pages ruleset_ids ruleset_count ruleset_id ruleset_json
    ruleset_pages="$(gh api --paginate --slurp \
        "repos/${EXPECTED_REPOSITORY}/rulesets?per_page=100")" ||
        github_read_failed "the ${EXPECTED_REPOSITORY} ruleset list"
    ruleset_ids="$(jq -b -r \
        --arg name "${EXPECTED_RULESET_NAME}" \
        'flatten | map(select(.name == $name)) | .[].id' \
        <<<"${ruleset_pages}")"
    ruleset_count="$(awk 'NF { count++ } END { print count + 0 }' <<<"${ruleset_ids}")"

    if [ "${ruleset_count}" -ne 1 ]; then
        echo "error: expected exactly one '${EXPECTED_RULESET_NAME}' ruleset; found ${ruleset_count}" >&2
        exit 1
    fi

    ruleset_id="$(awk 'NF { print; exit }' <<<"${ruleset_ids}")"
    ruleset_json="$(gh api "repos/${EXPECTED_REPOSITORY}/rulesets/${ruleset_id}")" ||
        github_read_failed "ruleset ${ruleset_id}"

    printf '%s\n' "${ruleset_json}"
}

main() {
    if [ "$#" -ne 0 ]; then
        echo "error: unknown argument: $1 (the guard has one mode: the full policy)" >&2
        exit 1
    fi
    require_command jq

    local ruleset_json
    ruleset_json="$(resolve_live_ruleset)"
    validate_ruleset_json "${ruleset_json}"
    echo "[ok] tag ruleset: ${EXPECTED_RULESET_NAME} matches the full publication policy"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
