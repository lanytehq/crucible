#!/usr/bin/env bash
# release-restore-tag-ref.sh - Restore the remote annotated tag in a CI checkout
#
# actions/checkout of a tag ref leaves a peeled local ref, so the tag object
# that carries the signature is not present. This fetches the annotated tag
# from the fixed public repository URL (never a configured remote) and
# requires it to be an annotated tag of LANYTE_CRUCIBLE_RELEASE_TAG pointing
# at HEAD. It changes only the runner-local ref; verify-pinned-tag.sh checks
# the signature.
#
# Usage: LANYTE_CRUCIBLE_RELEASE_TAG=vX.Y.Z release-restore-tag-ref.sh

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

url="https://github.com/lanytehq/crucible.git"
tag="${LANYTE_CRUCIBLE_RELEASE_TAG:-}"
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "canonical release tag required"

remote_object="$(git ls-remote --exit-code "$url" "refs/tags/$tag" | awk '{print $1}')" ||
    die "remote release tag $tag is absent"
[[ "$remote_object" =~ ^[0-9a-f]{40}$ ]] || die "remote tag object is invalid"
git fetch --quiet --no-tags "$url" "+refs/tags/$tag:refs/tags/$tag"
[[ "$(git rev-parse "refs/tags/$tag")" == "$remote_object" &&
    "$(git cat-file -t "refs/tags/$tag")" == tag &&
    "$(git rev-parse "refs/tags/$tag^{commit}")" == "$(git rev-parse HEAD)" ]] ||
    die "runner-local tag is not the remote annotated tag at HEAD"
echo "[ok] annotated tag $tag ($remote_object) restored at HEAD"
