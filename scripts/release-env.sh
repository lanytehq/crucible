#!/usr/bin/env bash
# release-env.sh - Explicit release inputs (3leaps/crucible PDR-0008 §2.3, §2.4)
#
# Source this file; it defines functions only.
#
# - refuse_legacy_release_env: fail if a retired, unprefixed, or other
#   repository's release variable is set, so an inherited name never silently
#   wins or is silently ignored.
# - require_release_tag: print LANYTE_CRUCIBLE_RELEASE_TAG, which must be a
#   canonical vMAJOR.MINOR.PATCH tag. There is no default from VERSION, git
#   describe, or the branch.

RELEASE_RETIRED_VARIABLES=(
    RELEASE_TAG
    CRUCIBLE_RELEASE_TAG
    CRUCIBLE_GPG_HOMEDIR
    CRUCIBLE_PGP_KEY_ID
    CRUCIBLE_TAGGER_NAME
    CRUCIBLE_TAGGER_EMAIL
    CRUCIBLE_ALLOW_NON_MAIN
    CRUCIBLE_REQUIRE_TAG
    CRUCIBLE_DECERNOR_BIN
    DECERNOR_BIN
    LANYTE_CRUCIBLE_REQUIRE_TAG
    THREELEAPS_CRUCIBLE_RELEASE_TAG
    THREELEAPS_CRUCIBLE_GPG_HOMEDIR
    THREELEAPS_CRUCIBLE_PGP_KEY_ID
    THREELEAPS_CRUCIBLE_DECERNOR_BIN
)

refuse_legacy_release_env() {
    local name found=()
    for name in "${RELEASE_RETIRED_VARIABLES[@]}"; do
        if [[ -n "${!name+set}" ]]; then
            found+=("$name")
        fi
    done
    if ((${#found[@]})); then
        echo "error: retired, unprefixed, or other-repository release variable set: ${found[*]}" >&2
        echo "hint: unset it; release inputs use the LANYTE_CRUCIBLE_ prefix (RELEASE_CHECKLIST.md)" >&2
        return 1
    fi
}

require_release_tag() {
    local tag="${LANYTE_CRUCIBLE_RELEASE_TAG:-}"
    if [[ -z "$tag" ]]; then
        echo "error: LANYTE_CRUCIBLE_RELEASE_TAG is required (e.g. v1.2.3); the tag is never derived" >&2
        return 1
    fi
    if ! [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        echo "error: invalid release tag '$tag' (expected vMAJOR.MINOR.PATCH)" >&2
        return 1
    fi
    printf '%s\n' "$tag"
}
