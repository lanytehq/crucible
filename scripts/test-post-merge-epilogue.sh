#!/usr/bin/env bash
# Controls for scripts/post-merge-epilogue.sh.
# Includes: fail-secure refusals, dry-run non-mutation, disposable-remote
# apply success, and H1 partial-destruction negative (dirty main-checkout).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
SCRIPT="$ROOT/scripts/post-merge-epilogue.sh"
[[ -f "$SCRIPT" ]] || { echo "[!!] missing $SCRIPT" >&2; exit 1; }
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

# ---------------------------------------------------------------------------
# Suite A — lightweight controls against this checkout (no --apply)
# ---------------------------------------------------------------------------

# Default branch from local metadata if present; else 'main' for message only.
DEFAULT="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || true)"
DEFAULT="${DEFAULT:-main}"

assert_fails "default-branch as --branch" \
  "$SCRIPT" --worktree "$ROOT" --branch "$DEFAULT"

assert_fails "relative --worktree" \
  "$SCRIPT" --worktree "relative/path" --branch "feature/x"

assert_fails "unowned / unknown worktree" \
  "$SCRIPT" --worktree "/tmp/definitely-not-a-worktree-of-this-repo-$$" --branch "feature/x"

assert_fails "--apply without --confirm" \
  "$SCRIPT" --worktree "$ROOT" --branch "feature/x" --apply

assert_fails "unknown remote" \
  "$SCRIPT" --worktree "$ROOT" --branch "feature/x" --remote "no-such-remote-$$"

if [[ -d "$ROOT/.git" ]]; then
  assert_fails "primary checkout removal" \
    "$SCRIPT" --worktree "$ROOT" --branch "feature/does-not-matter"
fi

# Linked worktree on this repo for dirty/unmerged + dry-run non-mutation.
TMP_WT="$(mktemp -d "${TMPDIR:-/tmp}/pme-wt.XXXXXX")"
TEST_BRANCH="pme-test-epilogue-$$"
DISPOSABLE=""
cleanup() {
  if [[ -n "${TMP_WT:-}" ]]; then
    git worktree remove --force "$TMP_WT" 2>/dev/null || true
  fi
  git branch -D "$TEST_BRANCH" 2>/dev/null || true
  if [[ -n "${DISPOSABLE:-}" && -d "$DISPOSABLE" ]]; then
    # Drop any worktrees registered inside disposable primary
    if [[ -d "$DISPOSABLE/primary" ]]; then
      git -C "$DISPOSABLE/primary" worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{print $2}' \
        | while read -r p; do
            [[ "$p" == "$DISPOSABLE/primary" ]] && continue
            git -C "$DISPOSABLE/primary" worktree remove --force "$p" 2>/dev/null || true
          done
    fi
    rm -rf "$DISPOSABLE"
  fi
  rm -rf "$TMP_WT" 2>/dev/null || true
  rm -f /tmp/pme-test-out.$$ /tmp/pme-test-err.$$ 2>/dev/null || true
}
trap cleanup EXIT

# Only add linked wt if origin/default remote-tracking exists (may require prior fetch by operator).
if git rev-parse --verify "refs/remotes/origin/${DEFAULT}" >/dev/null 2>&1; then
  git worktree add -b "$TEST_BRANCH" "$TMP_WT" "origin/${DEFAULT}" --quiet

  echo "pme-test-marker $$" >"$TMP_WT/.pme-test-marker"
  git -C "$TMP_WT" add .pme-test-marker
  git -C "$TMP_WT" -c user.email=test@example.com -c user.name=test \
    commit -m "test: unmerged marker for epilogue negative control" --quiet

  assert_fails "unmerged branch tip" \
    "$SCRIPT" --worktree "$TMP_WT" --branch "$TEST_BRANCH"

  git -C "$TMP_WT" reset --hard "origin/${DEFAULT}" --quiet

  # --- M1: dry-run must not mutate FETCH_HEAD / refs ---
  common_dir="$(git rev-parse --git-common-dir)"
  if [[ "$common_dir" != /* ]]; then
    common_dir="$(cd "$ROOT" && cd "$common_dir" && pwd -P)"
  else
    common_dir="$(cd "$common_dir" && pwd -P)"
  fi
  fetch_head="$common_dir/FETCH_HEAD"
  had_fetch_head=false
  [[ -e "$fetch_head" ]] && had_fetch_head=true
  # Remove FETCH_HEAD to prove dry-run does not recreate it
  rm -f "$fetch_head"
  refs_before="$(git show-ref | sort | (shasum -a 256 2>/dev/null || sha256sum) | awk '{print $1}')"
  wt_list_before="$(git worktree list --porcelain)"

  assert_ok "dry-run on clean merged linked worktree" \
    "$SCRIPT" --worktree "$TMP_WT" --branch "$TEST_BRANCH"

  if [[ -e "$fetch_head" ]]; then
    echo "[FAIL] dry-run created/updated FETCH_HEAD (must be non-mutating)" >&2
    fail=$((fail + 1))
  else
    echo "[ok] dry-run left FETCH_HEAD absent"
    pass=$((pass + 1))
  fi
  refs_after="$(git show-ref | sort | (shasum -a 256 2>/dev/null || sha256sum) | awk '{print $1}')"
  if [[ "$refs_before" != "$refs_after" ]]; then
    echo "[FAIL] dry-run mutated refs (show-ref digest changed)" >&2
    fail=$((fail + 1))
  else
    echo "[ok] dry-run left refs unchanged"
    pass=$((pass + 1))
  fi
  wt_list_after="$(git worktree list --porcelain)"
  if [[ "$wt_list_before" != "$wt_list_after" ]]; then
    echo "[FAIL] dry-run mutated worktree registry" >&2
    fail=$((fail + 1))
  else
    echo "[ok] dry-run left worktree registry unchanged"
    pass=$((pass + 1))
  fi
  # restore FETCH_HEAD expectation: optional re-fetch not required
  if $had_fetch_head; then
    git fetch origin "$DEFAULT" --quiet 2>/dev/null || true
  fi

  echo dirty >"$TMP_WT/.pme-dirty"
  assert_fails "dirty worktree" \
    "$SCRIPT" --worktree "$TMP_WT" --branch "$TEST_BRANCH"
  rm -f "$TMP_WT/.pme-dirty"

  [[ -d "$TMP_WT" ]] || { echo "[FAIL] dry-run removed worktree" >&2; fail=$((fail + 1)); exit 1; }
  echo "[ok] dry-run left worktree path intact"
  pass=$((pass + 1))
else
  echo "[!!] skip linked-worktree suite: missing refs/remotes/origin/${DEFAULT}" >&2
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Suite B — disposable bare remote: apply success + H1 dirty-main negative
# ---------------------------------------------------------------------------
DISPOSABLE="$(mktemp -d "${TMPDIR:-/tmp}/pme-disposable.XXXXXX")"
git init --bare "$DISPOSABLE/remote.git" --quiet
git clone "$DISPOSABLE/remote.git" "$DISPOSABLE/primary" --quiet
git -C "$DISPOSABLE/primary" -c user.email=test@example.com -c user.name=test \
  checkout -b main 2>/dev/null || git -C "$DISPOSABLE/primary" checkout -B main
# empty clone may need initial commit
echo base >"$DISPOSABLE/primary/file.txt"
git -C "$DISPOSABLE/primary" add file.txt
git -C "$DISPOSABLE/primary" -c user.email=test@example.com -c user.name=test \
  commit -m "init" --quiet
git -C "$DISPOSABLE/primary" push -u origin main --quiet
git -C "$DISPOSABLE/primary" remote set-head origin main

# Feature branch fully merged into main (remote + local)
git -C "$DISPOSABLE/primary" checkout -b feature/pme --quiet
echo feat >"$DISPOSABLE/primary/feat.txt"
git -C "$DISPOSABLE/primary" add feat.txt
git -C "$DISPOSABLE/primary" -c user.email=test@example.com -c user.name=test \
  commit -m "feat" --quiet
git -C "$DISPOSABLE/primary" push -u origin feature/pme --quiet
git -C "$DISPOSABLE/primary" checkout main --quiet
git -C "$DISPOSABLE/primary" merge --ff-only feature/pme --quiet
git -C "$DISPOSABLE/primary" push origin main --quiet

# Linked worktree still on feature/pme tip (== main tip, fully merged)
git -C "$DISPOSABLE/primary" worktree add "$DISPOSABLE/wt" feature/pme --quiet

# --- H1 negative: dirty primary on diverging branch blocks before mutation ---
git -C "$DISPOSABLE/primary" checkout -b scratch --quiet
# Make file.txt differ on scratch vs main so a dirty edit blocks checkout to main
echo scratch-content >"$DISPOSABLE/primary/file.txt"
git -C "$DISPOSABLE/primary" add file.txt
git -C "$DISPOSABLE/primary" -c user.email=test@example.com -c user.name=test \
  commit -m "scratch diverges" --quiet
echo dirty-overwrite >"$DISPOSABLE/primary/file.txt"  # dirty; would be overwritten by checkout main

# Snapshot remote feature + worktree existence
remote_had_feature=false
if git --git-dir="$DISPOSABLE/remote.git" show-ref --verify --quiet refs/heads/feature/pme; then
  remote_had_feature=true
fi
[[ -d "$DISPOSABLE/wt" ]] || { echo "[FAIL] setup: worktree missing" >&2; exit 1; }

if (
  cd "$DISPOSABLE/primary"
  "$SCRIPT" --worktree "$DISPOSABLE/wt" --branch feature/pme \
    --main-checkout "$DISPOSABLE/primary" --apply --confirm
) >/tmp/pme-test-out.$$ 2>/tmp/pme-test-err.$$; then
  echo "[FAIL] expected failure: dirty main-checkout must refuse before mutation" >&2
  cat /tmp/pme-test-err.$$ >&2 || true
  fail=$((fail + 1))
else
  echo "[ok] refuses: dirty main-checkout before mutation"
  pass=$((pass + 1))
fi

# Prove no partial destruction
if ! git --git-dir="$DISPOSABLE/remote.git" show-ref --verify --quiet refs/heads/feature/pme; then
  echo "[FAIL] H1: remote feature branch was deleted despite failed preflight" >&2
  fail=$((fail + 1))
else
  echo "[ok] H1: remote feature branch intact after dirty-main refusal"
  pass=$((pass + 1))
fi
if [[ ! -d "$DISPOSABLE/wt" ]]; then
  echo "[FAIL] H1: task worktree was removed despite failed preflight" >&2
  fail=$((fail + 1))
else
  echo "[ok] H1: task worktree intact after dirty-main refusal"
  pass=$((pass + 1))
fi
# primary still on scratch
cur="$(git -C "$DISPOSABLE/primary" rev-parse --abbrev-ref HEAD)"
if [[ "$cur" != "scratch" ]]; then
  echo "[FAIL] H1: primary branch moved unexpectedly (now $cur)" >&2
  fail=$((fail + 1))
else
  echo "[ok] H1: primary still on scratch"
  pass=$((pass + 1))
fi

# Reset primary to clean main for success path
git -C "$DISPOSABLE/primary" checkout -- file.txt
git -C "$DISPOSABLE/primary" checkout main --quiet

# --- Apply success path ---
if (
  cd "$DISPOSABLE/primary"
  "$SCRIPT" --worktree "$DISPOSABLE/wt" --branch feature/pme \
    --main-checkout "$DISPOSABLE/primary" --apply --confirm
) >/tmp/pme-test-out.$$ 2>/tmp/pme-test-err.$$; then
  echo "[ok] accepts: full apply --confirm on disposable remote"
  pass=$((pass + 1))
else
  echo "[FAIL] expected success: full apply --confirm" >&2
  cat /tmp/pme-test-err.$$ >&2 || true
  fail=$((fail + 1))
fi

if [[ -d "$DISPOSABLE/wt" ]]; then
  echo "[FAIL] apply success: worktree still present" >&2
  fail=$((fail + 1))
else
  echo "[ok] apply success: worktree removed"
  pass=$((pass + 1))
fi
if git --git-dir="$DISPOSABLE/remote.git" show-ref --verify --quiet refs/heads/feature/pme; then
  echo "[FAIL] apply success: remote feature branch still present" >&2
  fail=$((fail + 1))
else
  echo "[ok] apply success: remote feature branch deleted"
  pass=$((pass + 1))
fi
cur="$(git -C "$DISPOSABLE/primary" rev-parse --abbrev-ref HEAD)"
if [[ "$cur" != "main" ]]; then
  echo "[FAIL] apply success: primary not on main (now $cur)" >&2
  fail=$((fail + 1))
else
  echo "[ok] apply success: primary on main"
  pass=$((pass + 1))
fi
if [[ -n "$(git -C "$DISPOSABLE/primary" status --porcelain)" ]]; then
  echo "[FAIL] apply success: primary not clean" >&2
  fail=$((fail + 1))
else
  echo "[ok] apply success: primary clean"
  pass=$((pass + 1))
fi

# M2: unresolved default metadata fails closed (disposable with HEAD unset)
git -C "$DISPOSABLE/primary" symbolic-ref -d refs/remotes/origin/HEAD 2>/dev/null || true
# recreate a feature worktree for dry-run unresolved test
git -C "$DISPOSABLE/primary" branch feature/pme2 main --quiet
git -C "$DISPOSABLE/primary" worktree add "$DISPOSABLE/wt2" feature/pme2 --quiet
assert_fails "unresolved default branch (dry-run fail-closed)" \
  bash -c "cd '$DISPOSABLE/primary' && '$SCRIPT' --worktree '$DISPOSABLE/wt2' --branch feature/pme2"

echo
echo "post-merge-epilogue controls: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
