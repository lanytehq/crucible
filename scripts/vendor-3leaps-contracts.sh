#!/usr/bin/env bash
# vendor-3leaps-contracts.sh - Refresh the vendored 3leaps contract files
#
# Copies the listed dimension definitions, the dimension meta-schema, the
# durable-record/v1 record schema, and the RFC 8785 canonicalizer (digest
# oracle) verbatim from a local 3leaps/crucible
# checkout and rewrites each vendor directory's MANIFEST.json
# with the source commit and per-file sha256. Review the diff before
# committing; a changed value set may need matching edits in families that
# inline it.
#
# Usage: scripts/vendor-3leaps-contracts.sh [path-to-3leaps-crucible]

set -euo pipefail

SRC="${1:-$HOME/dev/3leaps/crucible}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO/config/classifiers/vendor/3leaps"
DIMENSIONS=(sensitivity access-tier retention-lifecycle volatility)

if [ ! -d "$SRC/.git" ]; then
    echo "[!!] not a git checkout: $SRC" >&2
    exit 1
fi
if [ -n "$(git -C "$SRC" status --porcelain -- config/classifiers schemas/classifiers schemas/durable-record scripts/rfc8785-canonicalize.py)" ]; then
    echo "[!!] $SRC has uncommitted classifier changes; vendor from a clean tree" >&2
    exit 1
fi

mkdir -p "$DEST/dimensions" "$DEST/schemas"
for d in "${DIMENSIONS[@]}"; do
    cp "$SRC/config/classifiers/dimensions/$d.dimension.json" "$DEST/dimensions/"
done
cp "$SRC/schemas/classifiers/v0/dimension-definition.schema.json" "$DEST/schemas/"

python3 -I - "$(git -C "$SRC" rev-parse HEAD)" "$DEST" <<'EOF'
import hashlib
import json
import pathlib
import sys

commit, dest = sys.argv[1], pathlib.Path(sys.argv[2])
files = {}
for path in sorted(dest.rglob("*.json")):
    if path.name == "MANIFEST.json":
        continue
    upstream = (
        "config/classifiers/dimensions/"
        if path.parent.name == "dimensions"
        else "schemas/classifiers/v0/"
    ) + path.name
    files[str(path.relative_to(dest))] = {
        "upstream": upstream,
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

RECORD_DEST="$REPO/schemas/vendor/3leaps/durable-record/v1"
mkdir -p "$RECORD_DEST"
cp "$SRC/schemas/durable-record/v1/record.schema.json" "$RECORD_DEST/"
python3 -I - "$(git -C "$SRC" rev-parse HEAD)" "$RECORD_DEST" <<'EOF'
import hashlib
import json
import pathlib
import sys

commit, dest = sys.argv[1], pathlib.Path(sys.argv[2])
path = dest / "record.schema.json"
manifest = {
    "source": "https://github.com/3leaps/crucible",
    "commit": commit,
    "note": "Verbatim copy. Do not edit; refresh with scripts/vendor-3leaps-contracts.sh and review the diff.",
    "files": {
        "record.schema.json": {
            "upstream": "schemas/durable-record/v1/record.schema.json",
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
    },
}
(dest / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
EOF

JCS_DEST="$REPO/scripts/vendor/3leaps"
mkdir -p "$JCS_DEST"
cp "$SRC/scripts/rfc8785-canonicalize.py" "$JCS_DEST/"
python3 -I - "$(git -C "$SRC" rev-parse HEAD)" "$JCS_DEST" <<'EOF'
import hashlib
import json
import pathlib
import sys

commit, dest = sys.argv[1], pathlib.Path(sys.argv[2])
path = dest / "rfc8785-canonicalize.py"
manifest = {
    "source": "https://github.com/3leaps/crucible",
    "commit": commit,
    "note": "Verbatim copy. Do not edit; refresh with scripts/vendor-3leaps-contracts.sh and review the diff.",
    "files": {
        "rfc8785-canonicalize.py": {
            "upstream": "scripts/rfc8785-canonicalize.py",
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
    },
}
(dest / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
EOF

echo "[ok] vendored ${#DIMENSIONS[@]} dimensions, meta-schema, durable-record/v1 record, JCS canonicalizer from $SRC"
