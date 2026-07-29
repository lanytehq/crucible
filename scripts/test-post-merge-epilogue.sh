#!/usr/bin/env bash
# Negative (and dry-run positive) controls for scripts/post-merge-epilogue.sh.
# Non-destructive: never passes --apply. Creates a temporary linked worktree
# under the system temp dir and removes it itself on exit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
SCRIPT="$ROOT/scripts/post-merge-epilogue.sh"
[[ -x "$SCRIPT" || -f "$SCRIPT" ]] || { echo "[!!] missing $SCRIPT" >&2; exit 1; }
chmod +x "$SCRIPT"

pass=0
fail=0
assert_fails() {
  local label="$1"; shift
  if "$@" >/tmp/pme-test-out.$$ 2>/tmp/pme-test-err.$$; then
    echo "[FAIL] expected failure: $label" >&2
    cat /tmp/pme-test-err.$$ >&2 || true
    fail=$((fail + 1))
  else
    echo "[ok] refuses: $label"
    pass=$((pass + 1))
  fi
}
assert_ok() {
  local label="$1"; shift
  if "$@" >/tmp/pme-test-out.$$ 2>/tmp/pme-test-err.$$; then
    echo "[ok] accepts: $label"
    pass=$((pass + 1))
  else
    echo "[FAIL] expected success: $label" >&2
    cat /tmp/pme-test-err.$$ >&2 || true
    fail=$((fail + 1))
  fi
}

# Ensure origin/main exists for merge checks
git fetch origin main --quiet 2>/dev/null || git fetch origin --quiet

DEFAULT="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || true)"
DEFAULT="${DEFAULT:-main}"

# 1) default-branch refusal
assert_fails "default-branch as --branch" \
  "$SCRIPT" --worktree "$ROOT" --branch "$DEFAULT"

# 2) relative worktree path refusal
assert_fails "relative --worktree" \
  "$SCRIPT" --worktree "relative/path" --branch "feature/x"

# 3) unknown worktree refusal
assert_fails "unowned / unknown worktree" \
  "$SCRIPT" --worktree "/tmp/definitely-not-a-worktree-of-this-repo-$$" --branch "feature/x"

# 4) --apply without --confirm
assert_fails "--apply without --confirm" \
  "$SCRIPT" --worktree "$ROOT" --branch "feature/x" --apply

# 5) primary checkout refusal (even if we invent a branch name)
# Primary is ROOT when this is the main worktree; if ROOT is linked, skip.
if [[ -d "$ROOT/.git" ]]; then
  assert_fails "primary checkout removal" \
    "$SCRIPT" --worktree "$ROOT" --branch "feature/does-not-matter"
fi

# 6) Temporary linked worktree for dry-run positive + dirty/unmerged refusals
TMP_WT="$(mktemp -d "${TMPDIR:-/tmp}/pme-wt.XXXXXX")"
TEST_BRANCH="pme-test-epilogue-$$"
cleanup() {
  # Best-effort teardown without using the script under test for apply
  git worktree remove --force "$TMP_WT" 2>/dev/null || true
  git branch -D "$TEST_BRANCH" 2>/dev/null || true
  rm -rf "$TMP_WT" 2>/dev/null || true
  rm -f /tmp/pme-test-out.$$ /tmp/pme-test-err.$$ 2>/dev/null || true
}
trap cleanup EXIT

git worktree add -b "$TEST_BRANCH" "$TMP_WT" "origin/${DEFAULT}" --quiet

# Unmerged: create a local-only commit on the test branch
echo "pme-test-marker $$" >"$TMP_WT/.pme-test-marker"
git -C "$TMP_WT" add .pme-test-marker
git -C "$TMP_WT" -c user.email=test@example.com -c user.name=test \
  commit -m "test: unmerged marker for epilogue negative control" --quiet

assert_fails "unmerged branch tip" \
  "$SCRIPT" --worktree "$TMP_WT" --branch "$TEST_BRANCH"

# Make it "merged" by resetting back to origin/default (clean + merged)
git -C "$TMP_WT" reset --hard "origin/${DEFAULT}" --quiet
# Ensure clean
assert_ok "dry-run on clean merged linked worktree" \
  "$SCRIPT" --worktree "$TMP_WT" --branch "$TEST_BRANCH"

# Dirty refusal
echo dirty >"$TMP_WT/.pme-dirty"
assert_fails "dirty worktree" \
  "$SCRIPT" --worktree "$TMP_WT" --branch "$TEST_BRANCH"
rm -f "$TMP_WT/.pme-dirty"

# Dry-run must not remove the worktree
[[ -d "$TMP_WT" ]] || { echo "[FAIL] dry-run removed worktree" >&2; fail=$((fail + 1)); }
echo "[ok] dry-run left worktree intact"
pass=$((pass + 1))

echo
echo "post-merge-epilogue controls: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
