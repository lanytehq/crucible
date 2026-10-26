#!/usr/bin/env bash
# release-verify-goneat-pin.sh - Check the goneat digest pins against goneat's
# signed checksums
#
# CI installs goneat by the digests in config/release/goneat-ci-sha256.txt
# (release-fetch-tool.sh). This script is how those digests are admitted: it
# downloads SHA256SUMS and SHA256SUMS.minisig for the pinned version, verifies
# the signature with the committed third-party pin
# docs/security/fulmenhq-goneat-minisign.pub (never a key from the release
# itself), and requires every pinned line to appear verbatim in the signed
# file. Run it before committing a change to the goneat pins.
#
# In CI the trust root is the committed archive digest; GitHub's Ubuntu
# runners carry no minisign. This signature check is defence in depth where
# minisign exists. Do not drop the digest path to rely on it.
#
# Requires minisign on PATH. Usage: release-verify-goneat-pin.sh

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

root="$(git rev-parse --show-toplevel)"
pins="$root/config/release/goneat-ci-sha256.txt"
key="$root/docs/security/fulmenhq-goneat-minisign.pub"
[[ -f "$pins" && ! -L "$pins" ]] || die "missing $pins"
[[ -f "$key" && ! -L "$key" ]] || die "missing $key"
command -v minisign >/dev/null 2>&1 || die "minisign is required on PATH"

versions="$(awk '{print $2}' "$pins" | sed -n 's/^goneat_\(v[0-9][0-9.]*\)_[a-z0-9]*_[a-z0-9]*\.tar\.gz$/\1/p' | sort -u)"
[[ -n "$versions" && "$versions" != *$'\n'* ]] || die "goneat pins must name exactly one version"
[[ "$(wc -l <"$pins")" -eq "$(grep -Fc "_${versions}_" "$pins")" ]] || die "malformed goneat pin line"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for f in SHA256SUMS SHA256SUMS.minisig; do
    curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location --retry 3 \
        "https://github.com/fulmenhq/goneat/releases/download/${versions}/${f}" --output "$work/$f"
done
minisign -Vq -p "$key" -m "$work/SHA256SUMS" -x "$work/SHA256SUMS.minisig" ||
    die "goneat ${versions} SHA256SUMS is not signed by the committed goneat key"

while IFS= read -r line; do
    grep -Fqx -- "$line" "$work/SHA256SUMS" || die "pin not in goneat's signed SHA256SUMS: $line"
done <"$pins"
echo "[ok] goneat ${versions} pins match its SHA256SUMS signed by the committed key"
