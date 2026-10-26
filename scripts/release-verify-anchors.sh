#!/usr/bin/env bash
# release-verify-anchors.sh - Verify committed release pins against their anchors
#
# Reads the public pins and fingerprint anchors from COMMIT as inert git
# objects, never from the working tree or the environment (3leaps/crucible PDR-0008 §2.1), and
# verifies them with the designated checker (§2.2):
# - keys/expected-fingerprints.txt and keys/expected-fingerprints.ndjson
# - docs/security/release-signing-keys.asc
# - docs/security/crucible-minisign.pub
#
# The checker is LANYTE_CRUCIBLE_DECERNOR_BIN (see release-env.sh).
#
# Usage: release-verify-anchors.sh COMMIT OUTPUT_DIR
#   OUTPUT_DIR must be an existing, empty directory; the verified blobs are left
#   there for the caller (anchors.txt, anchors.ndjson, pin.asc, minisign.pub).

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 2 ]] || die "usage: release-verify-anchors.sh COMMIT OUTPUT_DIR"
commit_ref="$1"
out="$2"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release-env.sh
source "$script_dir/release-env.sh"
refuse_legacy_release_env
resolve_release_decernor

[[ -d "$out" && ! -L "$out" ]] || die "output directory $out must exist"
[[ -z "$(ls -A "$out")" ]] || die "output directory $out must be empty"
commit="$(git rev-parse -q --verify "${commit_ref}^{commit}")" || die "commit $commit_ref absent"

committed() {
    local path="$1" dest="$2" mode
    mode="$(git ls-tree "$commit" -- "$path" | awk '{print $1}')"
    [[ "$mode" == 100644 ]] || die "committed regular file $path required in $commit"
    git cat-file blob "$commit:$path" >"$dest"
    [[ -s "$dest" ]] || die "committed $path is empty"
}
committed keys/expected-fingerprints.txt "$out/anchors.txt"
committed keys/expected-fingerprints.ndjson "$out/anchors.ndjson"
committed docs/security/release-signing-keys.asc "$out/pin.asc"
committed docs/security/crucible-minisign.pub "$out/minisign.pub"

if ! "$RELEASE_DECERNOR_BIN" fingerprint verify \
    --anchors "$out/anchors.txt" \
    --anchors-ndjson "$out/anchors.ndjson" \
    --gpg "$out/pin.asc" \
    --minisign "$out/minisign.pub" >"$out/verify.ndjson" 2>"$out/verify.err"; then
    cat "$out/verify.err" >&2
    die "committed pins differ from their anchors in $commit"
fi
rm -f "$out/verify.ndjson" "$out/verify.err"

echo "[ok] committed pins match their anchors in $commit"
