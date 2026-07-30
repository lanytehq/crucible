#!/usr/bin/env bash
# Post-merge epilogue: fail-secure cleanup after a PR lands on the default
# branch. Dry-run by default; destructive steps require --apply AND --confirm
# with explicit absolute --worktree and --branch inputs.
#
# Ordering (apply path):
#   1. Validate all inputs and preflight every apply prerequisite
#      (including optional --main-checkout, locked target, default-branch
#      ownership) BEFORE any mutation
#   2. Optional preflight refresh (fetch) — apply only, never dry-run
#   3. If --main-checkout: checkout default + local ff-only reconciliation
#      against already-fetched remote-tracking ref (BEFORE delete/remove)
#   4. Delete remote branch if still present
#   5. Remove the task worktree via `git worktree remove` on the exact path
#   6. Prune stale worktree metadata and remote-tracking refs
#
# Dry-run is strictly non-mutating: no fetch, no push, no worktree remove,
# no checkout, no prune. It uses already-present remote-tracking refs only
# and fails closed with an explicit refresh instruction when freshness
# cannot be proven from local state.
#
# Never deletes the default branch. Never removes a worktree that is not an
# added linked worktree owned by this repository. Never uses globs or
# recursive filesystem deletes.
#
# Operator CI posture: prefer `gh run list` / `gh run watch` for check status
# (fine-grained PATs often lack checks:read, so `gh pr checks` is unreliable).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/post-merge-epilogue.sh --worktree <abs-path> --branch <name> [options]

Required:
  --worktree <path>   Absolute path of the linked worktree to remove
  --branch <name>     Feature branch that was merged (must be checked out there)

Options:
  --main-checkout <path>  Absolute path of the PRIMARY checkout to return to
                          the default branch and fast-forward (optional).
                          When set: must be the exact primary worktree, clean,
                          same common-dir, default branch free (or already on
                          it), and safely reconcilable to default. Checkout +
                          local ff-only run BEFORE any remote delete / remove.
  --remote <name>         Remote name (default: origin); must be configured
  --apply                 Perform changes (default is dry-run)
  --confirm               Required with --apply (explicit operator confirmation)
  -h, --help              Show this help

Fail-secure refusals:
  - default branch as --branch
  - relative or non-absolute --worktree / --main-checkout
  - unknown / unconfigured remote
  - unresolved default branch (no current-branch fallback)
  - worktree not listed in `git worktree list --porcelain`
  - worktree is the primary (non-linked) checkout
  - target worktree is locked
  - worktree not belonging to this repository's common git dir
  - branch not checked out exactly in that worktree
  - branch checked out in more than one worktree (ambiguous ownership)
  - dirty task worktree
  - branch tip not fully merged into remote-tracking default
  - --main-checkout not the primary checkout / dirty / not ff-safe
  - default branch owned by a different worktree (checkout would fail)
  - --apply without --confirm
  - dry-run when required remote-tracking refs are missing (refresh first)
EOF
}

die() { echo "[!!] $*" >&2; exit 1; }
info() { echo "[..] $*"; }
ok() { echo "[ok] $*"; }

APPLY=false
CONFIRM=false
WORKTREE=""
BRANCH=""
MAIN_CHECKOUT=""
REMOTE="origin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree) WORKTREE="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --main-checkout) MAIN_CHECKOUT="${2:-}"; shift 2 ;;
    --remote) REMOTE="${2:-}"; shift 2 ;;
    --apply) APPLY=true; shift ;;
    --confirm) CONFIRM=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[[ -n "$WORKTREE" ]] || die "--worktree is required"
[[ -n "$BRANCH" ]] || die "--branch is required"
[[ -n "$REMOTE" ]] || die "--remote must be non-empty"
[[ "$WORKTREE" == /* ]] || die "--worktree must be an absolute path (got: $WORKTREE)"
if [[ -n "$MAIN_CHECKOUT" && "$MAIN_CHECKOUT" != /* ]]; then
  die "--main-checkout must be an absolute path (got: $MAIN_CHECKOUT)"
fi
if $APPLY && ! $CONFIRM; then
  die "--apply requires --confirm (refusing destructive run without explicit confirmation)"
fi
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 \
  || die "invalid --branch value: $BRANCH"
case "$REMOTE" in
  ''|*'..'*|*/*|*\\*|*[[:space:]]*) die "invalid --remote value: $REMOTE" ;;
esac

REPO_ROOT="$(pwd -P)"
[[ -e "$REPO_ROOT/.git" ]] || die "not a git repository root: $REPO_ROOT (run from repo root or via make)"

git remote get-url "$REMOTE" >/dev/null 2>&1 \
  || die "remote '$REMOTE' is not configured in this repository"

COMMON_DIR="$(git rev-parse --git-common-dir)"
if [[ "$COMMON_DIR" != /* ]]; then
  COMMON_DIR="$(cd "$REPO_ROOT" && cd "$COMMON_DIR" && pwd -P)"
else
  COMMON_DIR="$(cd "$COMMON_DIR" && pwd -P)"
fi

if [[ -d "$WORKTREE" ]]; then
  WORKTREE="$(cd "$WORKTREE" && pwd -P)"
fi
if [[ -n "$MAIN_CHECKOUT" && -d "$MAIN_CHECKOUT" ]]; then
  MAIN_CHECKOUT="$(cd "$MAIN_CHECKOUT" && pwd -P)"
fi

# --- parse worktree list (incl. locked) ---
declare -a WT_PATHS=()
declare -a WT_BRANCHES=()
declare -a WT_HEADS=()
declare -a WT_LOCKED=()
cur_path=""
cur_branch=""
cur_head=""
cur_locked=false
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ -z "$line" ]]; then
    if [[ -n "$cur_path" ]]; then
      WT_PATHS+=("$cur_path")
      WT_BRANCHES+=("${cur_branch:-}")
      WT_HEADS+=("${cur_head:-}")
      if $cur_locked; then WT_LOCKED+=("true"); else WT_LOCKED+=("false"); fi
    fi
    cur_path=""; cur_branch=""; cur_head=""; cur_locked=false
    continue
  fi
  case "$line" in
    worktree\ *) cur_path="${line#worktree }" ;;
    HEAD\ *) cur_head="${line#HEAD }" ;;
    branch\ refs/heads/*) cur_branch="${line#branch refs/heads/}" ;;
    detached) cur_branch="" ;;
    locked|locked\ *) cur_locked=true ;;
  esac
done < <(git worktree list --porcelain; echo)

if [[ -n "$cur_path" ]]; then
  WT_PATHS+=("$cur_path")
  WT_BRANCHES+=("${cur_branch:-}")
  WT_HEADS+=("${cur_head:-}")
  if $cur_locked; then WT_LOCKED+=("true"); else WT_LOCKED+=("false"); fi
fi

normalize_wt_path() {
  local p="$1"
  if [[ -d "$p" ]]; then
    (cd "$p" && pwd -P)
  else
    printf '%s' "$p"
  fi
}

find_primary_checkout() {
  local i p
  for i in "${!WT_PATHS[@]}"; do
    p="$(normalize_wt_path "${WT_PATHS[$i]}")"
    if [[ -d "$p/.git" ]]; then
      local gd
      gd="$(cd "$p/.git" && pwd -P)"
      if [[ "$gd" == "$COMMON_DIR" ]]; then
        printf '%s' "$p"
        return 0
      fi
    fi
  done
  return 1
}

resolve_default_branch() {
  local remote_head prefix
  remote_head="$(git symbolic-ref -q "refs/remotes/${REMOTE}/HEAD" 2>/dev/null || true)"
  if [[ -n "$remote_head" ]]; then
    prefix="refs/remotes/${REMOTE}/"
    DEFAULT_BRANCH="${remote_head#"$prefix"}"
    [[ -n "$DEFAULT_BRANCH" && "$DEFAULT_BRANCH" != "$remote_head" ]] \
      || die "could not parse default branch from $remote_head"
    return 0
  fi
  return 1
}

DEFAULT_BRANCH=""
if ! resolve_default_branch; then
  if $APPLY; then
    info "remote-tracking HEAD missing; preflight fetch of remote HEAD for '$REMOTE'"
    git remote set-head "$REMOTE" --auto >/dev/null 2>&1 \
      || git fetch "$REMOTE" --quiet
    resolve_default_branch \
      || die "could not resolve default branch for remote '$REMOTE' from remote-tracking metadata (no current-branch fallback); ensure 'git remote set-head $REMOTE --auto' or fetch has populated refs/remotes/$REMOTE/HEAD"
  else
    die "could not resolve default branch for remote '$REMOTE' from local remote-tracking metadata (dry-run is non-mutating). Refresh first: git remote set-head $REMOTE --auto && git fetch $REMOTE"
  fi
fi

[[ "$BRANCH" != "$DEFAULT_BRANCH" ]] || die "refusing to operate on the default branch ('$DEFAULT_BRANCH')"

idx=-1
for i in "${!WT_PATHS[@]}"; do
  p="$(normalize_wt_path "${WT_PATHS[$i]}")"
  if [[ "$p" == "$WORKTREE" ]]; then
    idx=$i
    break
  fi
done
[[ $idx -ge 0 ]] || die "worktree not listed in this repository: $WORKTREE"

wt_branch="${WT_BRANCHES[$idx]}"
wt_head="${WT_HEADS[$idx]}"
wt_locked="${WT_LOCKED[$idx]}"

# Locked target cannot be removed — refuse before any mutation.
[[ "$wt_locked" != "true" ]] \
  || die "target worktree is locked; unlock it first (git worktree unlock) before epilogue — refusing before any mutation"

is_linked=false
if [[ -f "$WORKTREE/.git" ]]; then
  gitdir_line="$(tr -d '\r' <"$WORKTREE/.git")"
  gitdir_path="${gitdir_line#gitdir: }"
  if [[ "$gitdir_path" != /* ]]; then
    gitdir_path="$(cd "$WORKTREE" && cd "$(dirname "$gitdir_path")" && pwd -P)/$(basename "$gitdir_path")"
  else
    gitdir_path="$(cd "$(dirname "$gitdir_path")" && pwd -P)/$(basename "$gitdir_path")"
  fi
  case "$gitdir_path" in
    "$COMMON_DIR"/worktrees/*) is_linked=true ;;
    *) die "worktree gitdir is not under this repo's common worktrees dir: $gitdir_path" ;;
  esac
elif [[ -d "$WORKTREE/.git" ]]; then
  die "refusing to remove the primary checkout worktree: $WORKTREE"
else
  die "cannot determine worktree linkage for: $WORKTREE"
fi
$is_linked || die "internal: expected linked worktree"

[[ -n "$wt_branch" ]] || die "worktree is detached HEAD; refuse (ambiguous ownership)"
[[ "$wt_branch" == "$BRANCH" ]] || die "worktree branch mismatch: expected '$BRANCH', found '$wt_branch'"

owners=0
for i in "${!WT_BRANCHES[@]}"; do
  if [[ "${WT_BRANCHES[$i]}" == "$BRANCH" ]]; then
    owners=$((owners + 1))
  fi
done
[[ $owners -eq 1 ]] || die "ambiguous ownership: branch '$BRANCH' is checked out in $owners worktrees (need exactly 1)"

if [[ -d "$WORKTREE" ]]; then
  dirty="$(git -C "$WORKTREE" status --porcelain 2>/dev/null || true)"
  [[ -z "$dirty" ]] || die "worktree is dirty; commit/stash/discard before epilogue"
fi

remote_default_ref="refs/remotes/${REMOTE}/${DEFAULT_BRANCH}"

if $APPLY; then
  info "preflight fetch ${REMOTE} ${DEFAULT_BRANCH} (apply path only)"
  git fetch "$REMOTE" "$DEFAULT_BRANCH" --quiet
fi

git rev-parse --verify "$remote_default_ref" >/dev/null 2>&1 \
  || die "missing $remote_default_ref. Refresh first: git fetch $REMOTE $DEFAULT_BRANCH"

branch_tip=""
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  branch_tip="$(git rev-parse "refs/heads/${BRANCH}")"
else
  branch_tip="$wt_head"
fi
[[ -n "$branch_tip" ]] || die "could not resolve tip of branch '$BRANCH'"

unmerged_count="$(git rev-list --count "${remote_default_ref}..${branch_tip}")"
[[ "$unmerged_count" == "0" ]] || die "branch '$BRANCH' is not fully merged into ${REMOTE}/${DEFAULT_BRANCH} ($unmerged_count commit(s) ahead); merge first"

# --- main-checkout preflight (BEFORE any mutation) ---
PRIMARY_PATH=""
if PRIMARY_PATH="$(find_primary_checkout)"; then
  :
else
  PRIMARY_PATH=""
fi

if [[ -n "$MAIN_CHECKOUT" ]]; then
  main_idx=-1
  for i in "${!WT_PATHS[@]}"; do
    p="$(normalize_wt_path "${WT_PATHS[$i]}")"
    if [[ "$p" == "$MAIN_CHECKOUT" ]]; then main_idx=$i; break; fi
  done
  [[ $main_idx -ge 0 ]] || die "--main-checkout is not a worktree of this repository: $MAIN_CHECKOUT"
  [[ "$MAIN_CHECKOUT" != "$WORKTREE" ]] || die "--main-checkout must not equal --worktree"
  [[ -n "$PRIMARY_PATH" ]] || die "could not identify the primary checkout for this repository"
  [[ "$MAIN_CHECKOUT" == "$PRIMARY_PATH" ]] \
    || die "--main-checkout must be the exact primary checkout ($PRIMARY_PATH), not a linked worktree (got: $MAIN_CHECKOUT)"
  [[ -d "$MAIN_CHECKOUT/.git" ]] \
    || die "--main-checkout is not a primary checkout directory: $MAIN_CHECKOUT"

  main_dirty="$(git -C "$MAIN_CHECKOUT" status --porcelain 2>/dev/null || true)"
  [[ -z "$main_dirty" ]] \
    || die "--main-checkout is dirty; refuse before any mutation (clean it or omit --main-checkout)"

  main_common="$(git -C "$MAIN_CHECKOUT" rev-parse --git-common-dir)"
  if [[ "$main_common" != /* ]]; then
    main_common="$(cd "$MAIN_CHECKOUT" && cd "$main_common" && pwd -P)"
  else
    main_common="$(cd "$main_common" && pwd -P)"
  fi
  [[ "$main_common" == "$COMMON_DIR" ]] \
    || die "--main-checkout common-dir mismatch (got $main_common, expected $COMMON_DIR)"

  if git -C "$MAIN_CHECKOUT" show-ref --verify --quiet "refs/heads/${DEFAULT_BRANCH}"; then
    local_default_tip="$(git -C "$MAIN_CHECKOUT" rev-parse "refs/heads/${DEFAULT_BRANCH}")"
    if ! git merge-base --is-ancestor "$local_default_tip" "$remote_default_ref"; then
      die "local ${DEFAULT_BRANCH} has diverged from ${REMOTE}/${DEFAULT_BRANCH}; refuse ff-only update before any mutation"
    fi
  fi

  # Default branch must not be owned by a different worktree (checkout would fail).
  main_cur="$(git -C "$MAIN_CHECKOUT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$main_cur" != "$DEFAULT_BRANCH" ]]; then
    for i in "${!WT_BRANCHES[@]}"; do
      p="$(normalize_wt_path "${WT_PATHS[$i]}")"
      if [[ "${WT_BRANCHES[$i]}" == "$DEFAULT_BRANCH" && "$p" != "$MAIN_CHECKOUT" ]]; then
        die "default branch '${DEFAULT_BRANCH}' is already checked out in another worktree ($p); refuse before any mutation (move/remove that worktree or omit --main-checkout)"
      fi
    done
  fi
fi

remote_branch_exists=false
if $APPLY; then
  if git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
    remote_branch_exists=true
  fi
else
  if git show-ref --verify --quiet "refs/remotes/${REMOTE}/${BRANCH}"; then
    remote_branch_exists=true
  fi
fi

echo
echo "=== post-merge epilogue plan ==="
echo "  repo root:       $REPO_ROOT"
echo "  remote:          $REMOTE"
echo "  default branch:  $DEFAULT_BRANCH"
echo "  feature branch:  $BRANCH  (tip ${branch_tip:0:12})"
echo "  worktree:        $WORKTREE"
echo "  locked:          $wt_locked"
echo "  remote branch:   $(if $remote_branch_exists; then echo present; else echo already absent; fi)$(if ! $APPLY; then echo " (local tracking knowledge)"; fi)"
echo "  main checkout:   ${MAIN_CHECKOUT:-"(skip)"}"
echo "  mode:            $(if $APPLY; then echo APPLY; else echo DRY-RUN; fi)"
echo

plan_step() { echo "  would: $*"; }
run_step() { echo "  doing: $*"; }

if ! $APPLY; then
  if [[ -n "$MAIN_CHECKOUT" ]]; then
    plan_step "git -C ${MAIN_CHECKOUT} checkout ${DEFAULT_BRANCH}"
    plan_step "git -C ${MAIN_CHECKOUT} merge --ff-only ${remote_default_ref}  (local; already-fetched)"
  fi
  if $remote_branch_exists; then
    plan_step "git push ${REMOTE} --delete ${BRANCH}"
  else
    plan_step "skip remote delete (already absent or not present in local tracking)"
  fi
  plan_step "git worktree remove ${WORKTREE}"
  plan_step "git worktree prune"
  plan_step "git fetch --prune ${REMOTE}"
  echo
  ok "dry-run complete (no fetch, no mutations); re-run with --apply --confirm to execute"
  exit 0
fi

# --- apply: all preflight passed ---
# Reversible / non-destructive-to-feature first: primary checkout + local ff.
if [[ -n "$MAIN_CHECKOUT" ]]; then
  run_step "checkout default + local ff-only on main checkout (before delete/remove)"
  git -C "$MAIN_CHECKOUT" checkout "$DEFAULT_BRANCH"
  # Reconcile against already-fetched remote-tracking ref (no second network pull required).
  git -C "$MAIN_CHECKOUT" merge --ff-only "$remote_default_ref"
  ok "main checkout at ${MAIN_CHECKOUT} on ${DEFAULT_BRANCH} (ff-only vs ${remote_default_ref})"
fi

# Irreversible steps only after main transition succeeds (or was skipped).
if $remote_branch_exists; then
  run_step "git push ${REMOTE} --delete ${BRANCH}"
  git push "$REMOTE" --delete "$BRANCH"
  ok "deleted remote branch ${REMOTE}/${BRANCH}"
else
  ok "remote branch already absent"
fi

run_step "git worktree remove ${WORKTREE}"
remove_cwd="$REPO_ROOT"
if [[ "$REPO_ROOT" == "$WORKTREE" ]]; then
  if [[ -n "$MAIN_CHECKOUT" && -d "$MAIN_CHECKOUT" ]]; then
    remove_cwd="$MAIN_CHECKOUT"
  else
    for i in "${!WT_PATHS[@]}"; do
      p="$(normalize_wt_path "${WT_PATHS[$i]}")"
      if [[ "$p" != "$WORKTREE" && -d "$p" ]]; then
        remove_cwd="$p"
        break
      fi
    done
  fi
  [[ "$remove_cwd" != "$WORKTREE" ]] || die "cannot remove worktree from inside itself without --main-checkout"
fi
git -C "$remove_cwd" worktree remove "$WORKTREE"
ok "removed worktree $WORKTREE"

run_step "git worktree prune"
git -C "$remove_cwd" worktree prune
run_step "git fetch --prune ${REMOTE}"
git -C "$remove_cwd" fetch --prune "$REMOTE"

echo
ok "post-merge epilogue complete"
echo "     tip: use 'gh run list' / 'gh run watch' for CI status (not 'gh pr checks')"
