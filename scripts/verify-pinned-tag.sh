#!/usr/bin/env bash
# verify-pinned-tag.sh - Verify a signed release tag against the committed pin
#
# Trust data is read as inert git objects from the tagged commit, never from the
# working tree or the environment (3leaps/crucible PDR-0004 §2, PDR-0008 §2.1):
# - keys/expected-fingerprints.txt and .ndjson: the gpg and minisign anchors
# - docs/security/release-signing-keys.asc: one primary matching the gpg anchor,
#   exactly one signing subkey
# - docs/security/crucible-minisign.pub: public key blob matching the minisign anchor
# - config/release/tagger-identity.txt: required tagger name and email
#
# The anchors are verified by the designated checker, decernor, bound through
# LANYTE_CRUCIBLE_DECERNOR_BIN (release-verify-anchors.sh). The tag must
# carry exactly one good, unexpired, unrevoked signature made by the pinned
# signing subkey.
#
# Usage: verify-pinned-tag.sh TAG   (required; never derived)

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || die "usage: verify-pinned-tag.sh TAG (the release tag is never derived)"
cd "$(git rev-parse --show-toplevel)"
tag="$1"
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "canonical release tag required: $tag"
object="$(git rev-parse -q --verify "refs/tags/$tag")" || die "tag $tag absent"
[[ "$(git cat-file -t "$object")" == tag ]] || die "annotated tag required"
[[ "$(git cat-file tag "$object" | sed -n 's/^tag //p' | head -1)" == "$tag" ]] || die "tag name mismatch"
target="$(git rev-parse "${object}^{commit}")"

work="$(mktemp -d)"
trap 'gpgconf --homedir "$work/home" --kill all >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
chmod 700 "$work"

mkdir -m 700 "$work/pins"
./scripts/release-verify-anchors.sh "$target" "$work/pins"
[[ "$(git ls-tree "$target" -- config/release/tagger-identity.txt | awk '{print $1}')" == 100644 ]] ||
    die "committed regular file config/release/tagger-identity.txt required in the tagged commit"
git cat-file blob "$target:config/release/tagger-identity.txt" >"$work/tagger"
[[ -s "$work/tagger" ]] || die "committed config/release/tagger-identity.txt is empty"

tagger="$(git cat-file tag "$object" | sed -n 's/^tagger \(.*\) [0-9][0-9]* [+-][0-9][0-9][0-9][0-9]$/\1/p' | head -1)"
[[ "$tagger" == "$(cat "$work/tagger")" ]] || die "tagger '$tagger' does not match committed tagger identity"

mkdir -m 700 "$work/home"
export GNUPGHOME="$work/home"
gpg --batch --quiet --import "$work/pins/pin.asc" 2>/dev/null || die "pin import failed"
listing="$(gpg --batch --with-colons --with-subkey-fingerprint --list-keys)"
[[ "$(awk -F: '$1=="sec"' <<<"$listing")" == "" ]] || die "pin contains secret material"
[[ "$(awk -F: '$1=="pub" {n++} END {print n+0}' <<<"$listing")" == 1 ]] || die "pin must hold exactly one primary key"
primary="$(awk '$1=="gpg" {print $2}' "$work/pins/anchors.txt")"
signing="$(awk -F: '$1=="sub" {s=1; cap=$12; next} s && $1=="fpr" {if (cap ~ /s/) print $10; s=0}' <<<"$listing")"
[[ "$signing" =~ ^[0-9A-F]{40}$ ]] || die "pin must hold exactly one signing subkey"

git -c gpg.program=gpg verify-tag --raw "$object" >"$work/status" 2>&1 || {
    awk '$1=="[GNUPG:]" {print "signature status:", $2}' "$work/status" >&2
    die "tag signature invalid under pin"
}
awk -v primary="$primary" -v signing="$signing" '
  $1=="[GNUPG:]" && $2=="VALIDSIG" {valid++; subkey=$3; signer_primary=$NF}
  $1=="[GNUPG:]" && $2=="GOODSIG" {good++}
  $1=="[GNUPG:]" && $2 ~ /^(EXPKEYSIG|EXPSIG|REVKEYSIG|KEYREVOKED|BADSIG|ERRSIG)$/ {bad++}
  END { if (bad || good != 1 || valid != 1 || signer_primary != primary || subkey != signing) exit 1 }
' "$work/status" || die "signature is not a single good signature by the pinned signing subkey"

echo "[ok] $tag ($object) signed by pinned subkey $signing; anchors and tagger match"
