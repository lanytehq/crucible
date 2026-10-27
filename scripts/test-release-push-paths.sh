#!/usr/bin/env bash
# Control: release surfaces teach one push path. Outside release-push-tag.sh,
# no release script, make file, or release document may push or delete a ref
# with plain git (git push, push origin, --delete), because that path skips
# the transport isolation, the bypass check, and the remote-object check.
#
# Usage: test-release-push-paths.sh [ROOT]   (ROOT defaults to this checkout)
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd -P)}"
cd "$ROOT"

surfaces=(
  scripts/release-*.sh
  scripts/verify-pinned-tag.sh
  scripts/ci-install-goneat.sh
  make/release.mk
  Makefile
  RELEASE_CHECKLIST.md
  docs/security/README.md
  docs/decisions/adr-0020-release-identity-adoption.md
)
# Any git invocation whose words include push, so options and their values
# (git -c key=value push, git -C dir push) are matched; release_git is not.
pattern='(^|[^_[:alnum:]])git([[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)|push[[:space:]]+origin|push[[:space:]].*--delete'

hits=""
for f in "${surfaces[@]}"; do
  [[ -f "$f" ]] || { echo "[FAIL] release surface missing: $f" >&2; exit 1; }
  [[ "$f" == scripts/release-push-tag.sh ]] && continue
  if found="$(grep -nE -- "$pattern" "$f")"; then
    hits+="$(sed "s|^|$f:|" <<<"$found")"$'\n'
  fi
done

if [[ -n "$hits" ]]; then
  echo "[FAIL] release surfaces push outside make release-push-tag:" >&2
  printf '%s' "$hits" | sed 's/^/       /' >&2
  exit 1
fi
echo "[ok] release surfaces push only through release-push-tag"
