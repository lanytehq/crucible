#!/usr/bin/env bash
# release-derive-anchors.sh - Derive the release fingerprint anchors (3leaps/crucible PDR-0008 §2.2)
#
# Derives keys/expected-fingerprints.txt and keys/expected-fingerprints.ndjson
# from the committed public exports with the designated checker, twice, and
# requires both derivations to agree. Hex is never typed by hand.
#
# Modes:
#   --check  (default) re-derive and require the committed anchors to match
#   --write  write the anchors; refuses if either file already exists, so an
#            anchor change is always a delete-then-derive in a reviewed commit
#
# The checker is LANYTE_CRUCIBLE_DECERNOR_BIN (see release-env.sh).

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

mode="${1:---check}"
[[ $# -le 1 && ("$mode" == --check || "$mode" == --write) ]] ||
    die "usage: release-derive-anchors.sh [--check|--write]"

cd "$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/release-env.sh
source scripts/release-env.sh
refuse_legacy_release_env
resolve_release_decernor

gpg_pin=docs/security/release-signing-keys.asc
minisign_pin=docs/security/crucible-minisign.pub
for pin in "$gpg_pin" "$minisign_pin"; do
    [[ -f "$pin" && ! -L "$pin" && -s "$pin" ]] || die "public export $pin must be a non-empty regular file"
done

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

derive() {
    local dest="$1"
    mkdir "$dest"
    "$RELEASE_DECERNOR_BIN" fingerprint "$gpg_pin" --class public --kind gpg \
        --format ndjson --path-mode none --gpg-role primary >"$dest/gpg.ndjson"
    "$RELEASE_DECERNOR_BIN" fingerprint "$minisign_pin" --class public --kind minisign \
        --format ndjson --path-mode none >"$dest/minisign.ndjson"
    python3 - "$dest" <<'PY'
import json
import pathlib
import sys

base = pathlib.Path(sys.argv[1])


def records(name):
    return [json.loads(line) for line in (base / name).read_text().splitlines() if line]


gpg = records("gpg.ndjson")
minisign = [
    r
    for r in records("minisign.ndjson")
    if r.get("fingerprint_scheme") == "minisign-public-blob-sha256-v1"
]
if (
    len(gpg) != 1
    or gpg[0].get("fingerprint_scheme") != "openpgp-fingerprint-v1"
    or gpg[0].get("key_role") != "primary"
    or len(minisign) != 1
):
    sys.exit("error: expected exactly one GPG primary and one minisign public-blob fingerprint")
pair = (gpg[0], minisign[0])
(base / "expected-fingerprints.ndjson").write_text(
    "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in pair)
)
(base / "expected-fingerprints.txt").write_text(
    f"gpg {pair[0]['fingerprint']}\nminisign {pair[1]['fingerprint']}\n"
)
PY
}

derive "$scratch/first"
derive "$scratch/second"
for name in expected-fingerprints.txt expected-fingerprints.ndjson; do
    cmp -s "$scratch/first/$name" "$scratch/second/$name" || die "two derivations of $name disagree"
done

if [[ "$mode" == --write ]]; then
    for name in expected-fingerprints.txt expected-fingerprints.ndjson; do
        [[ ! -e "keys/$name" && ! -L "keys/$name" ]] || die "keys/$name exists; delete it in the same reviewed change to re-derive"
    done
    mkdir -p keys
    for name in expected-fingerprints.txt expected-fingerprints.ndjson; do
        cp "$scratch/first/$name" "keys/$name"
    done
    echo "[ok] derived keys/expected-fingerprints.{txt,ndjson}; review and commit them"
    exit 0
fi

for name in expected-fingerprints.txt expected-fingerprints.ndjson; do
    [[ -f "keys/$name" && ! -L "keys/$name" ]] || die "keys/$name must be a regular file"
    cmp -s "$scratch/first/$name" "keys/$name" || die "keys/$name differs from the checker's derivation"
done
echo "[ok] committed anchors match the checker's derivation"
