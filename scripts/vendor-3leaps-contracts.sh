#!/usr/bin/env bash
# vendor-3leaps-contracts.sh - Refresh the vendored 3leaps contract files
#
# Copies the listed dimension definitions, the dimension meta-schema, the
# durable-record/v1 record schema, and the RFC 8785 canonicalizer (digest
# oracle) verbatim from a local 3leaps/crucible checkout, then rewrites each
# vendor directory's MANIFEST.json with the source commit and per-file
# sha256. Review the diff before committing; a changed value set may need
# matching edits in families that inline it.
#
# Usage: scripts/vendor-3leaps-contracts.sh [path-to-3leaps-crucible]

set -euo pipefail

SRC="${1:-$HOME/dev/3leaps/crucible}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DIMENSIONS=(sensitivity access-tier retention-lifecycle volatility)
SOURCES=(
    config/classifiers/dimensions
    schemas/classifiers/v0/dimension-definition.schema.json
    schemas/durable-record/v1/record.schema.json
    scripts/rfc8785-canonicalize.py
)

die() {
    echo "[!!] $*" >&2
    exit 1
}

# Each git call is checked on its own line: a failure inside a command
# substitution used as an argument would not stop the script.
git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1 || die "not a git checkout: $SRC"

if ! status="$(git -C "$SRC" status --porcelain -- "${SOURCES[@]}")"; then
    die "git status failed in $SRC"
fi
[ -z "$status" ] || die "$SRC has uncommitted changes to vendored sources; vendor from a clean tree"

if ! commit="$(git -C "$SRC" rev-parse --verify HEAD)"; then
    die "cannot resolve HEAD in $SRC"
fi
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "unexpected commit id: $commit"

DIM_DEST="$REPO/config/classifiers/vendor/3leaps"
RECORD_DEST="$REPO/schemas/vendor/3leaps/durable-record/v1"
JCS_DEST="$REPO/scripts/vendor/3leaps"

mkdir -p "$DIM_DEST/dimensions" "$DIM_DEST/schemas" "$RECORD_DEST" "$JCS_DEST"
for d in "${DIMENSIONS[@]}"; do
    cp "$SRC/config/classifiers/dimensions/$d.dimension.json" "$DIM_DEST/dimensions/"
done
cp "$SRC/schemas/classifiers/v0/dimension-definition.schema.json" "$DIM_DEST/schemas/"
cp "$SRC/schemas/durable-record/v1/record.schema.json" "$RECORD_DEST/"
cp "$SRC/scripts/rfc8785-canonicalize.py" "$JCS_DEST/"

python3 -I - "$commit" "$DIM_DEST" "$RECORD_DEST" "$JCS_DEST" <<'EOF'
import hashlib
import json
import pathlib
import sys

commit = sys.argv[1]
dim_dest, record_dest, jcs_dest = (pathlib.Path(p) for p in sys.argv[2:5])
upstreams = {
    dim_dest: lambda rel: (
        "config/classifiers/dimensions/" + rel.name
        if rel.parent.name == "dimensions"
        else "schemas/classifiers/v0/" + rel.name
    ),
    record_dest: lambda rel: "schemas/durable-record/v1/" + rel.name,
    jcs_dest: lambda rel: "scripts/" + rel.name,
}
for dest, upstream in upstreams.items():
    files = {}
    for path in sorted(p for p in dest.rglob("*") if p.is_file()):
        if path.name == "MANIFEST.json":
            continue
        rel = path.relative_to(dest)
        files[str(rel)] = {
            "upstream": upstream(rel),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
    manifest = {
        "source": "https://github.com/3leaps/crucible",
        "commit": commit,
        "note": "Verbatim copies. Do not edit; refresh with scripts/vendor-3leaps-contracts.sh and review the diff.",
        "files": files,
    }
    (dest / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
EOF

echo "[ok] vendored ${#DIMENSIONS[@]} dimensions, meta-schema, durable-record/v1 record, RFC 8785 canonicalizer at $commit"
