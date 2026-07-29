#!/usr/bin/env bash
# Controls for scripts/post-merge-epilogue.sh.
# Suite A: lightweight refusals against the real checkout (no FETCH_HEAD mutation).
# Suite B: fully disposable bare-remote world for dry-run non-mutation, H1
# negatives (dirty main, default owned elsewhere, locked target), and apply success.
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

assert_intact_remote_and_wt() {
  local label="$1" remote_git="$2" branch="$3" wt="$4"
  if ! git --git-dir="$remote_git" show-ref --verify --quiet "refs/heads/${branch}"; then
    echo "[FAIL] $label: remote branch ${branch} was deleted" >&2
    fail=$((fail + 1))
    return 1
  fi
  if [[ ! -d "$wt" ]]; then
    echo "[FAIL] $label: task worktree was removed" >&2
    fail=$((fail + 1))
    return 1
  fi
  echo "[ok] $label: remote branch + worktree intact"
  pass=$((pass + 1))
  return 0
}

# ---------------------------------------------------------------------------
# Suite A — lightweight controls against this checkout (no --apply, no shared mutation)
# ---------------------------------------------------------------------------
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

# Unmerged tip against this repo's origin (creates a temporary linked wt; cleaned up).
TMP_WT=""
TEST_BRANCH="pme-test-epilogue-$$"
DISPOSABLE=""
cleanup() {
  if [[ -n "${TMP_WT:-}" ]]; then
    git worktree unlock "$TMP_WT" 2>/dev/null || true
    git worktree remove --force "$TMP_WT" 2>/dev/null || true
  fi
  git branch -D "$TEST_BRANCH" 2>/dev/null || true
  if [[ -n "${DISPOSABLE:-}" && -d "$DISPOSABLE" ]]; then
    if [[ -d "$DISPOSABLE/primary" ]]; then
      # unlock then remove any linked worktrees
      git -C "$DISPOSABLE/primary" worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{print $2}' \
        | while read -r p; do
            [[ "$p" == "$DISPOSABLE/primary" ]] && continue
            git -C "$DISPOSABLE/primary" worktree unlock "$p" 2>/dev/null || true
            git -C "$DISPOSABLE/primary" worktree remove --force "$p" 2>/dev/null || true
          done
    fi
    rm -rf "$DISPOSABLE"
  fi
  rm -rf "${TMP_WT:-}" 2>/dev/null || true
  rm -f /tmp/pme-test-out.$$ /tmp/pme-test-err.$$ 2>/dev/null || true
}
trap cleanup EXIT

if git rev-parse --verify "refs/remotes/origin/${DEFAULT}" >/dev/null 2>&1; then
  TMP_WT="$(mktemp -d "${TMPDIR:-/tmp}/pme-wt.XXXXXX")"
  git worktree add -b "$TEST_BRANCH" "$TMP_WT" "origin/${DEFAULT}" --quiet
  echo "pme-test-marker $$" >"$TMP_WT/.pme-test-marker"
  git -C "$TMP_WT" add .pme-test-marker
  git -C "$TMP_WT" -c user.email=test@example.com -c user.name=test \
    commit -m "test: unmerged marker for epilogue negative control" --quiet
  assert_fails "unmerged branch tip" \
    "$SCRIPT" --worktree "$TMP_WT" --branch "$TEST_BRANCH"
  echo dirty >"$TMP_WT/.pme-dirty"
  # After reset for dirty test we need merged tip; use hard reset then dirty
  git -C "$TMP_WT" reset --hard "origin/${DEFAULT}" --quiet
  echo dirty >"$TMP_WT/.pme-dirty"
  assert_fails "dirty worktree" \
    "$SCRIPT" --worktree "$TMP_WT" --branch "$TEST_BRANCH"
  rm -f "$TMP_WT/.pme-dirty"
  # Remove temp wt so shared repo is clean again (no FETCH_HEAD games)
  git worktree remove --force "$TMP_WT" 2>/dev/null || true
  TMP_WT=""
  git branch -D "$TEST_BRANCH" 2>/dev/null || true
  TEST_BRANCH=""
else
  echo "[!!] skip unmerged/dirty suite: missing refs/remotes/origin/${DEFAULT}" >&2
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Suite B — fully disposable bare remote (M1 + all H1 paths + apply success)
# ---------------------------------------------------------------------------
DISPOSABLE="$(mktemp -d "${TMPDIR:-/tmp}/pme-disposable.XXXXXX")"
git init --bare "$DISPOSABLE/remote.git" --quiet
git clone "$DISPOSABLE/remote.git" "$DISPOSABLE/primary" --quiet
git -C "$DISPOSABLE/primary" checkout -B main --quiet 2>/dev/null || true
echo base >"$DISPOSABLE/primary/file.txt"
git -C "$DISPOSABLE/primary" add file.txt
git -C "$DISPOSABLE/primary" -c user.email=test@example.com -c user.name=test \
  commit -m "init" --quiet
git -C "$DISPOSABLE/primary" push -u origin main --quiet
git -C "$DISPOSABLE/primary" remote set-head origin main

setup_merged_feature() {
  # primary on main, feature/pme fully merged, linked wt on feature/pme
  git -C "$DISPOSABLE/primary" checkout main --quiet
  # drop leftover feature worktrees if any
  if [[ -d "$DISPOSABLE/wt" ]]; then
    git -C "$DISPOSABLE/primary" worktree unlock "$DISPOSABLE/wt" 2>/dev/null || true
    git -C "$DISPOSABLE/primary" worktree remove --force "$DISPOSABLE/wt" 2>/dev/null || true
  fi
  if [[ -d "$DISPOSABLE/wt-main" ]]; then
    git -C "$DISPOSABLE/primary" worktree unlock "$DISPOSABLE/wt-main" 2>/dev/null || true
    git -C "$DISPOSABLE/primary" worktree remove --force "$DISPOSABLE/wt-main" 2>/dev/null || true
  fi
  git -C "$DISPOSABLE/primary" branch -D feature/pme 2>/dev/null || true
  git -C "$DISPOSABLE/primary" push origin --delete feature/pme 2>/dev/null || true

  git -C "$DISPOSABLE/primary" checkout -b feature/pme --quiet
  echo "feat-$$-$RANDOM" >"$DISPOSABLE/primary/feat.txt"
  git -C "$DISPOSABLE/primary" add feat.txt
  git -C "$DISPOSABLE/primary" -c user.email=test@example.com -c user.name=test \
    commit -m "feat" --quiet
  git -C "$DISPOSABLE/primary" push -u origin feature/pme --quiet
  git -C "$DISPOSABLE/primary" checkout main --quiet
  git -C "$DISPOSABLE/primary" merge --ff-only feature/pme --quiet
  git -C "$DISPOSABLE/primary" push origin main --quiet
  git -C "$DISPOSABLE/primary" worktree add "$DISPOSABLE/wt" feature/pme --quiet
}

# --- M1: dry-run non-mutation entirely inside disposable ---
setup_merged_feature
common_dir="$(git -C "$DISPOSABLE/primary" rev-parse --git-common-dir)"
if [[ "$common_dir" != /* ]]; then
  common_dir="$(cd "$DISPOSABLE/primary" && cd "$common_dir" && pwd -P)"
else
  common_dir="$(cd "$common_dir" && pwd -P)"
fi
fetch_head="$common_dir/FETCH_HEAD"
rm -f "$fetch_head"
refs_before="$(git -C "$DISPOSABLE/primary" show-ref | sort | (shasum -a 256 2>/dev/null || sha256sum) | awk '{print $1}')"
wt_list_before="$(git -C "$DISPOSABLE/primary" worktree list --porcelain)"

assert_ok "dry-run on clean merged linked worktree (disposable)" \
  bash -c "cd '$DISPOSABLE/primary' && '$SCRIPT' --worktree '$DISPOSABLE/wt' --branch feature/pme"

if [[ -e "$fetch_head" ]]; then
  echo "[FAIL] dry-run created/updated FETCH_HEAD in disposable" >&2
  fail=$((fail + 1))
else
  echo "[ok] dry-run left FETCH_HEAD absent (disposable)"
  pass=$((pass + 1))
fi
refs_after="$(git -C "$DISPOSABLE/primary" show-ref | sort | (shasum -a 256 2>/dev/null || sha256sum) | awk '{print $1}')"
if [[ "$refs_before" != "$refs_after" ]]; then
  echo "[FAIL] dry-run mutated refs in disposable" >&2
  fail=$((fail + 1))
else
  echo "[ok] dry-run left refs unchanged (disposable)"
  pass=$((pass + 1))
fi
wt_list_after="$(git -C "$DISPOSABLE/primary" worktree list --porcelain)"
if [[ "$wt_list_before" != "$wt_list_after" ]]; then
  echo "[FAIL] dry-run mutated worktree registry in disposable" >&2
  fail=$((fail + 1))
else
  echo "[ok] dry-run left worktree registry unchanged (disposable)"
  pass=$((pass + 1))
fi
[[ -d "$DISPOSABLE/wt" ]] || { echo "[FAIL] dry-run removed worktree" >&2; fail=$((fail + 1)); }
echo "[ok] dry-run left worktree path intact (disposable)"
pass=$((pass + 1))

# --- H1: dirty main-checkout ---
git -C "$DISPOSABLE/primary" checkout -b scratch --quiet
echo scratch-content >"$DISPOSABLE/primary/file.txt"
git -C "$DISPOSABLE/primary" add file.txt
git -C "$DISPOSABLE/primary" -c user.email=test@example.com -c user.name=test \
  commit -m "scratch diverges" --quiet
echo dirty-overwrite >"$DISPOSABLE/primary/file.txt"

if (
  cd "$DISPOSABLE/primary"
  "$SCRIPT" --worktree "$DISPOSABLE/wt" --branch feature/pme \
    --main-checkout "$DISPOSABLE/primary" --apply --confirm
) >/tmp/pme-test-out.$$ 2>/tmp/pme-test-err.$$; then
  echo "[FAIL] expected failure: dirty main-checkout" >&2
  fail=$((fail + 1))
else
  echo "[ok] refuses: dirty main-checkout before mutation"
  pass=$((pass + 1))
fi
assert_intact_remote_and_wt "H1 dirty-main" "$DISPOSABLE/remote.git" feature/pme "$DISPOSABLE/wt"
cur="$(git -C "$DISPOSABLE/primary" rev-parse --abbrev-ref HEAD)"
if [[ "$cur" == "scratch" ]]; then
  echo "[ok] H1: primary still on scratch"; pass=$((pass + 1))
else
  echo "[FAIL] H1: primary moved ($cur)" >&2; fail=$((fail + 1))
fi

# --- H1: default branch owned by another linked worktree ---
git -C "$DISPOSABLE/primary" checkout -- file.txt
# primary on scratch, clean; move main into a separate linked worktree
# need main free on primary first — primary is on scratch, main is free
git -C "$DISPOSABLE/primary" worktree add "$DISPOSABLE/wt-main" main --quiet
# primary still scratch, clean
git -C "$DISPOSABLE/primary" status --porcelain | grep -q . && die_setup=1 || die_setup=0
if [[ ${die_setup:-0} -eq 1 ]]; then
  echo "[FAIL] setup: primary not clean for ownership test" >&2
  fail=$((fail + 1))
fi

if (
  cd "$DISPOSABLE/primary"
  "$SCRIPT" --worktree "$DISPOSABLE/wt" --branch feature/pme \
    --main-checkout "$DISPOSABLE/primary" --apply --confirm
) >/tmp/pme-test-out.$$ 2>/tmp/pme-test-err.$$; then
  echo "[FAIL] expected failure: default branch owned by other worktree" >&2
  cat /tmp/pme-test-err.$$ >&2 || true
  fail=$((fail + 1))
else
  echo "[ok] refuses: default branch owned by other worktree"
  pass=$((pass + 1))
fi
assert_intact_remote_and_wt "H1 default-owned-elsewhere" "$DISPOSABLE/remote.git" feature/pme "$DISPOSABLE/wt"
cur="$(git -C "$DISPOSABLE/primary" rev-parse --abbrev-ref HEAD)"
if [[ "$cur" == "scratch" ]]; then
  echo "[ok] H1: primary still on scratch after ownership refusal"; pass=$((pass + 1))
else
  echo "[FAIL] H1 ownership: primary moved ($cur)" >&2; fail=$((fail + 1))
fi

# cleanup main-owner wt for next tests
git -C "$DISPOSABLE/primary" worktree remove --force "$DISPOSABLE/wt-main"
git -C "$DISPOSABLE/primary" checkout main --quiet

# --- H1: locked target worktree ---
git -C "$DISPOSABLE/primary" worktree lock "$DISPOSABLE/wt"
if (
  cd "$DISPOSABLE/primary"
  "$SCRIPT" --worktree "$DISPOSABLE/wt" --branch feature/pme \
    --main-checkout "$DISPOSABLE/primary" --apply --confirm
) >/tmp/pme-test-out.$$ 2>/tmp/pme-test-err.$$; then
  echo "[FAIL] expected failure: locked target worktree" >&2
  cat /tmp/pme-test-err.$$ >&2 || true
  fail=$((fail + 1))
else
  echo "[ok] refuses: locked target worktree"
  pass=$((pass + 1))
fi
assert_intact_remote_and_wt "H1 locked-target" "$DISPOSABLE/remote.git" feature/pme "$DISPOSABLE/wt"
git -C "$DISPOSABLE/primary" worktree unlock "$DISPOSABLE/wt"

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
if [[ "$cur" == "main" ]]; then
  echo "[ok] apply success: primary on main"; pass=$((pass + 1))
else
  echo "[FAIL] apply success: primary not on main ($cur)" >&2; fail=$((fail + 1))
fi
if [[ -n "$(git -C "$DISPOSABLE/primary" status --porcelain)" ]]; then
  echo "[FAIL] apply success: primary not clean" >&2
  fail=$((fail + 1))
else
  echo "[ok] apply success: primary clean"
  pass=$((pass + 1))
fi

# M2: unresolved default metadata fails closed
setup_merged_feature
git -C "$DISPOSABLE/primary" symbolic-ref -d refs/remotes/origin/HEAD 2>/dev/null || true
assert_fails "unresolved default branch (dry-run fail-closed)" \
  bash -c "cd '$DISPOSABLE/primary' && '$SCRIPT' --worktree '$DISPOSABLE/wt' --branch feature/pme"

echo
echo "post-merge-epilogue controls: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
