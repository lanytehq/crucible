#!/usr/bin/env bash
# Control: release-tag deletes a tag that does not verify against the
# committed pin. This is the one control that drives the real `git tag -s`
# path, so it needs a terminal (python pty) and a real checker; it is not part
# of make check. A throwaway key named like the release signer signs a tag in a
# disposable clone; release-tag must refuse it and leave no tag.
#
# Usage: LANYTE_CRUCIBLE_DECERNOR_BIN=/abs/decernor test-release-tag-pinned.sh
set -euo pipefail

: "${LANYTE_CRUCIBLE_DECERNOR_BIN:?absolute path to decernor required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'gpgconf --homedir "$WORK/kr" --kill all >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

mkdir -m 700 "$WORK/kr"
name="$(sed 's/ <.*//' "$ROOT/config/release/tagger-identity.txt")"
email="$(sed 's/.*<\(.*\)>/\1/' "$ROOT/config/release/tagger-identity.txt")"
GNUPGHOME="$WORK/kr" gpg --batch --quiet --passphrase '' \
  --quick-gen-key "$name <$email>" ed25519 sign 1d >/dev/null 2>&1

# A disposable clone of the committed tip, on main, at an unreleased version.
git clone -q "$ROOT" "$WORK/repo"
cd "$WORK/repo"
git checkout -q -B main
printf '9.9.9\n' >VERSION
git -c user.name=t -c user.email=t@example.invalid commit -qam "control: unreleased version"

set +e
env -u GNUPGHOME LANYTE_CRUCIBLE_RELEASE_TAG=v9.9.9 \
  LANYTE_CRUCIBLE_GPG_HOMEDIR="$WORK/kr" \
  LANYTE_CRUCIBLE_TAGGER_NAME="$name" LANYTE_CRUCIBLE_TAGGER_EMAIL="$email" \
  python3 -I -c 'import pty, sys; sys.exit(pty.spawn(["./scripts/release-tag.sh"]) >> 8)' \
  >"$WORK/out" 2>&1
rc=$?
set -e
tr -d '\r' <"$WORK/out" >"$WORK/log"

if ((rc == 0)); then
  echo "[FAIL] release-tag accepted a tag signed outside the committed pin" >&2
  exit 1
fi
# Positive evidence that the run reached the pinned check, not an earlier stop.
if ! grep -qF "does not verify against the committed pin; the local tag was deleted" "$WORK/log"; then
  echo "[FAIL] release-tag refused before the pinned check:" >&2
  sed 's/^/       /' "$WORK/log" >&2
  exit 1
fi
if [[ -n "$(git tag -l v9.9.9)" ]]; then
  echo "[FAIL] release-tag left the unverified tag in place" >&2
  exit 1
fi
echo "[ok] release-tag deleted a tag that does not verify against the committed pin"
