#!/usr/bin/env bash
# release-fetch-tool.sh - Install a digest-pinned release tool
#
# Downloads one tool archive for one platform, requires its SHA-256 to equal
# the single matching line in config/release/<tool>-ci-sha256.txt
# (3leaps/crucible PDR-0008 §2.5, §2.6), extracts only the binary, and checks
# that it reports the pinned version. The committed digest is the trust root;
# the version check is not a substitute for it.
#
# Tools:
#   decernor  3leaps/decernor, archive decernor_X.Y.Z_<os_arch>.tar.gz; also
#             checked by resolve_release_decernor (release-env.sh)
#   goneat    fulmenhq/goneat, archive goneat_vX.Y.Z_<os_arch>.tar.gz; its
#             digests are checked against goneat's signed SHA256SUMS by
#             release-verify-goneat-pin.sh before they are committed
#
# Usage: release-fetch-tool.sh TOOL OS_ARCH DEST_DIR
#   OS_ARCH is e.g. linux_amd64 or darwin_arm64. DEST_DIR must be an existing,
#   empty directory. Prints the absolute path of the installed binary.

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 3 ]] || die "usage: release-fetch-tool.sh TOOL OS_ARCH DEST_DIR"
tool="$1"
platform="$2"
dest="$3"
case "$tool" in
decernor) repo="3leaps/decernor" vprefix="" ;;
goneat) repo="fulmenhq/goneat" vprefix="v" ;;
*) die "unknown tool '$tool'" ;;
esac
[[ "$platform" =~ ^[a-z0-9]+_[a-z0-9]+$ ]] || die "invalid platform '$platform'"
[[ -d "$dest" && ! -L "$dest" ]] || die "destination $dest must exist"
[[ -z "$(ls -A "$dest")" ]] || die "destination $dest must be empty"
dest="$(cd "$dest" && pwd -P)"

root="$(git rev-parse --show-toplevel)"
pins="$root/config/release/${tool}-ci-sha256.txt"
[[ -f "$pins" && ! -L "$pins" ]] || die "missing $pins"

matches="$(awk -v suffix="_${platform}.tar.gz" 'substr($2, length($2) - length(suffix) + 1) == suffix' "$pins")"
[[ -n "$matches" && "$matches" != *$'\n'* ]] || die "expected exactly one pinned $tool archive for $platform"
read -r digest archive <<<"$matches"
[[ "$digest" =~ ^[0-9a-f]{64}$ ]] || die "malformed digest for $archive"
[[ "$archive" =~ ^${tool}_${vprefix}((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))_${platform}\.tar\.gz$ ]] ||
    die "malformed archive name '$archive'"
version="${BASH_REMATCH[1]}"

curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location --retry 3 \
    "https://github.com/${repo}/releases/download/v${version}/${archive}" \
    --output "$dest/$archive"
if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$dest/$archive" | awk '{print $1}')"
else
    actual="$(shasum -a 256 "$dest/$archive" | awk '{print $1}')"
fi
[[ "$actual" == "$digest" ]] || die "$archive digest $actual does not match the pinned $digest"

tar -xzf "$dest/$archive" -C "$dest" "$tool"
rm -f "$dest/$archive"
[[ -f "$dest/$tool" && ! -L "$dest/$tool" ]] || die "archive did not yield a regular $tool binary"
chmod 755 "$dest/$tool"

case "$tool" in
decernor)
    # shellcheck source=scripts/release-env.sh
    source "$root/scripts/release-env.sh"
    LANYTE_CRUCIBLE_DECERNOR_BIN="$dest/decernor" resolve_release_decernor
    "$dest/decernor" version | grep -Fqx "decernor ${version}" || die "installed decernor does not report ${version}"
    ;;
goneat)
    "$dest/goneat" version 2>/dev/null | head -n1 | grep -Fqx "goneat v${version}" ||
        die "installed goneat does not report v${version}"
    ;;
esac
printf '%s\n' "$dest/$tool"
