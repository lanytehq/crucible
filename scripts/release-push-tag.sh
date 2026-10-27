#!/usr/bin/env bash
# release-push-tag.sh - Verify and push the signed version tag
#
# Transport (ADR-0020): every remote call goes to the fixed URL below, never a
# configured remote. The explicit URL is only explicit if nothing between the
# script and the wire rewrites it, so each git call runs with global and
# system config ignored, injected config (GIT_CONFIG_PARAMETERS/COUNT)
# scrubbed, and no askpass; repository config that rewrites URLs or sets
# credentials is refused. The only credential is GH_TOKEN, supplied through
# `gh auth git-credential` with gh's stored logins hidden. A missing token
# stops the push; there is no second try.
#
# Order of checks, all before any push:
# - LANYTE_CRUCIBLE_RELEASE_TAG and the checker (release-env.sh)
# - GH_TOKEN present; transport isolated and the URL unchanged by git config
# - The live ruleset is the full policy (release-guard-tag-ruleset.sh) and a
#   fresh read reports current_user_can_bypass == "always" for this credential
# - Local annotated tag exists and verifies against the committed pin
# - Tagged commit is on the remote main; remote tag does not already exist
# Then pushes only the tag ref, requires the remote tag object to equal the
# local one, and reads GitHub's verified flag (a read failure after the push
# is reported as such).
#
# --delete (make release-delete-remote-tag) is the rollback: the same
# credential, transport, and bypass checks, then deletes only the remote tag
# ref and requires it to be gone. Deletion is in the ruleset too, so it never
# goes through origin.
#
# Usage: direnv exec <org root> make release-push-tag
#   with LANYTE_CRUCIBLE_RELEASE_TAG and LANYTE_CRUCIBLE_DECERNOR_BIN set.

set -euo pipefail

readonly RELEASE_REMOTE_URL="https://github.com/lanytehq/crucible.git"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release-env.sh
source "$script_dir/release-env.sh"
# Ruleset reading and the full-policy check; its main is replaced below.
# shellcheck source=scripts/release-guard-tag-ruleset.sh
source "$script_dir/release-guard-tag-ruleset.sh"

die() {
    echo "error: $*" >&2
    exit 1
}

# git with only repository config: global and system files ignored, injected
# configuration and askpass programs removed, no terminal prompt.
isolated_git() {
    env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_ASKPASS -u SSH_ASKPASS \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
        git "$@"
}

# isolated_git with gh as the only credential helper.
release_git() {
    isolated_git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"
}

# Refuse repository config that could reroute or authenticate the push, and
# require git to resolve URL to itself. http.* is refused whole: extraheader
# (also URL-scoped, http.<url>.extraheader) can carry a second credential, and
# cookie, client-certificate, proxy, and TLS keys change who or what is on the
# wire. None has a role in a release push.
require_isolated_transport() {
    local url="$1" keys resolved
    keys="$(isolated_git config --get-regexp '^(url|credential|http)\.' 2>/dev/null || true)"
    [[ -z "$keys" ]] ||
        die "repository git config rewrites URLs, sets credentials, or sets http options ($(awk '{print $1}' <<<"$keys" | tr '\n' ' ')); remove it before pushing"
    resolved="$(isolated_git ls-remote --get-url "$url")"
    [[ "$resolved" == "$url" ]] || die "git rewrites $url to $resolved; refusing to push"
}

# gh may use only GH_TOKEN: no other token variable and no stored login.
require_push_credential() {
    [[ -n "${GH_TOKEN:-}" ]] ||
        die "GH_TOKEN is required (run through the org root's direnv); no other credential is tried"
    unset GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_HOST
    GH_CONFIG_DIR="$(mktemp -d)"
    export GH_CONFIG_DIR
}

# The credential about to push must be one the ruleset lets bypass, always.
# Read fresh; the recorded evidence in ADR-0020 is provenance only.
require_bypass_now() {
    local ruleset_json bypass
    ruleset_json="$(resolve_live_ruleset)"
    validate_ruleset_json "$ruleset_json" || die "tag ruleset does not match the full publication policy"
    bypass="$(jq -r '.current_user_can_bypass // "absent"' <<<"$ruleset_json")" ||
        die "could not read current_user_can_bypass from the ruleset response"
    [[ "$bypass" == "always" ]] ||
        die "this credential's current_user_can_bypass is '$bypass', not 'always'; refusing to push"
}

# Succeeds when COMMIT is on URL's main.
require_on_remote_main() {
    local url="$1" commit="$2" main
    release_git fetch --quiet --no-tags "$url" refs/heads/main ||
        die "could not fetch main from $url; nothing was pushed"
    main="$(git rev-parse FETCH_HEAD)"
    git merge-base --is-ancestor "$commit" "$main" ||
        die "tagged commit $commit is not on main at $url"
}

# Succeeds when TAG is absent at URL; a failed read is not absence.
require_remote_tag_absent() {
    local url="$1" tag="$2" rc=0
    release_git ls-remote --exit-code --tags "$url" "refs/tags/${tag}" >/dev/null || rc=$?
    case "$rc" in
    2) ;;
    0) die "remote tag ${tag} already exists at $url" ;;
    *) die "could not read tags from $url (git exit $rc); nothing was pushed" ;;
    esac
}

# Deletes TAG at URL; it must exist, and must be gone afterwards.
delete_remote_tag() {
    local url="$1" tag="$2" rc=0
    release_git ls-remote --exit-code --tags "$url" "refs/tags/${tag}" >/dev/null || rc=$?
    case "$rc" in
    0) ;;
    2) die "remote tag ${tag} does not exist at $url; nothing to delete" ;;
    *) die "could not read tags from $url (git exit $rc); nothing was deleted" ;;
    esac
    echo "Deleting remote tag: ${tag} at ${url}"
    release_git push "$url" ":refs/tags/${tag}"
    require_remote_tag_absent "$url" "$tag"
    echo "[ok] Remote tag ${tag} deleted; the local tag is unchanged"
}

main() {
    local mode=push
    case "${1:-}" in
    "") ;;
    --delete) mode=delete ;;
    *) die "unknown argument: $1" ;;
    esac
    cd "$(git rev-parse --show-toplevel)"
    refuse_legacy_release_env
    local tag
    tag="$(require_release_tag)"
    if [[ "$mode" == push ]]; then
        resolve_release_decernor
    fi

    require_push_credential
    trap 'rm -rf "$GH_CONFIG_DIR"' EXIT
    require_isolated_transport "$RELEASE_REMOTE_URL"
    require_bypass_now

    if [[ "$mode" == delete ]]; then
        delete_remote_tag "$RELEASE_REMOTE_URL" "$tag"
        return
    fi

    git rev-parse -q --verify "refs/tags/${tag}^{tag}" >/dev/null ||
        die "${tag} is not a local annotated tag (run 'make release-tag' first)"
    ./scripts/release-verify-tag.sh

    local tag_commit local_object remote_object
    tag_commit="$(git rev-parse "refs/tags/${tag}^{commit}")"
    require_on_remote_main "$RELEASE_REMOTE_URL" "$tag_commit"
    require_remote_tag_absent "$RELEASE_REMOTE_URL" "$tag"

    echo "Pushing tag: ${tag} to ${RELEASE_REMOTE_URL}"
    release_git push "$RELEASE_REMOTE_URL" "refs/tags/${tag}:refs/tags/${tag}"

    local_object="$(git rev-parse "refs/tags/${tag}")"
    remote_object="$(release_git ls-remote "$RELEASE_REMOTE_URL" "refs/tags/${tag}" | awk '{print $1}')"
    [[ "$remote_object" == "$local_object" ]] ||
        die "remote tag object (${remote_object:-missing}) differs from local (${local_object})"
    echo "[ok] Pushed ${tag} (${local_object}); the remote tag object matches"

    local verified
    if ! verified="$(gh api "repos/lanytehq/crucible/git/tags/${local_object}" --jq .verification.verified)"; then
        echo "error: ${tag} is pushed, but GitHub's verified flag could not be read" >&2
        echo "hint: do not push or delete the tag again; re-check with:" >&2
        echo "hint:   gh api repos/lanytehq/crucible/git/tags/${local_object} --jq .verification" >&2
        exit 1
    fi
    [[ "$verified" == "true" ]] ||
        die "${tag} is pushed, but GitHub does not report it verified (verification.verified=${verified})"
    echo "[ok] GitHub reports ${tag} verified; the release workflow verifies it against the pin"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
