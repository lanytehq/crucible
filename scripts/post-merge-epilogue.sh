#!/usr/bin/env bash
# Post-merge epilogue: fail-secure cleanup after a PR lands on the default
# branch. Dry-run by default; destructive steps require --apply AND --confirm
# with explicit absolute --worktree and --branch inputs.
#
# Steps (in order):
#   1. Validate inputs (default branch, ownership, clean tree, merged tip)
#   2. Delete remote branch if still present (auto-delete may already have)
#   3. Remove the task worktree via `git worktree remove` on the exact path
#   4. Optionally return a main checkout to the default branch and ff-only pull
#   5. Prune stale worktree metadata and remote-tracking refs
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
  --main-checkout <path>  Absolute path of the primary checkout to return to
                          the default branch and fast-forward (optional)
  --remote <name>         Remote name (default: origin)
  --apply                 Perform changes (default is dry-run)
  --confirm               Required with --apply (explicit operator confirmation)
  -h, --help              Show this help

Fail-secure refusals:
  - default branch as --branch
  - relative or non-absolute --worktree / --main-checkout
  - worktree not listed in `git worktree list --porcelain`
  - worktree is the primary (non-linked) checkout
  - worktree not belonging to this repository's common git dir
  - branch not checked out exactly in that worktree
  - branch checked out in more than one worktree (ambiguous ownership)
  - dirty worktree
  - branch tip not fully merged into remote default branch
  - --apply without --confirm
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
[[ "$WORKTREE" == /* ]] || die "--worktree must be an absolute path (got: $WORKTREE)"
if [[ -n "$MAIN_CHECKOUT" && "$MAIN_CHECKOUT" != /* ]]; then
  die "--main-checkout must be an absolute path (got: $MAIN_CHECKOUT)"
fi
if $APPLY && ! $CONFIRM; then
  die "--apply requires --confirm (refusing destructive run without explicit confirmation)"
fi

# Resolve repository root from the invoking cwd (Makefile cds to repo root).
REPO_ROOT="$(pwd -P)"
[[ -e "$REPO_ROOT/.git" ]] || die "not a git repository root: $REPO_ROOT (run from repo root or via make)"

COMMON_DIR="$(git rev-parse --git-common-dir)"
# git may return relative common-dir
if [[ "$COMMON_DIR" != /* ]]; then
  COMMON_DIR="$(cd "$REPO_ROOT" && cd "$COMMON_DIR" && pwd -P)"
else
  COMMON_DIR="$(cd "$COMMON_DIR" && pwd -P)"
fi

# Canonicalize worktree path if it exists; still allow dry-run validation
# against porcelain even if already removed (will fail list check).
if [[ -d "$WORKTREE" ]]; then
  WORKTREE="$(cd "$WORKTREE" && pwd -P)"
fi
if [[ -n "$MAIN_CHECKOUT" && -d "$MAIN_CHECKOUT" ]]; then
  MAIN_CHECKOUT="$(cd "$MAIN_CHECKOUT" && pwd -P)"
fi

# --- parse worktree list ---
# Porcelain records: worktree <path> / HEAD <sha> / branch refs/heads/<name> | detached
declare -a WT_PATHS=()
declare -a WT_BRANCHES=()
declare -a WT_HEADS=()
cur_path=""
cur_branch=""
cur_head=""
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ -z "$line" ]]; then
    if [[ -n "$cur_path" ]]; then
      WT_PATHS+=("$cur_path")
      WT_BRANCHES+=("${cur_branch:-}")
      WT_HEADS+=("${cur_head:-}")
    fi
    cur_path=""; cur_branch=""; cur_head=""
    continue
  fi
  case "$line" in
    worktree\ *) cur_path="${line#worktree }" ;;
    HEAD\ *) cur_head="${line#HEAD }" ;;
    branch\ refs/heads/*) cur_branch="${line#branch refs/heads/}" ;;
    detached) cur_branch="" ;;
  esac
done < <(git worktree list --porcelain; echo)

# Flush trailing record if porcelain lacked final blank line
if [[ -n "$cur_path" ]]; then
  WT_PATHS+=("$cur_path")
  WT_BRANCHES+=("${cur_branch:-}")
  WT_HEADS+=("${cur_head:-}")
fi

# Resolve default branch from remote HEAD (authoritative for this clone).
DEFAULT_BRANCH=""
if remote_head="$(git symbolic-ref -q "refs/remotes/${REMOTE}/HEAD" 2>/dev/null || true)"; then
  # refs/remotes/origin/main → main
  DEFAULT_BRANCH="${remote_head#refs/remotes/${REMOTE}/}"
fi
if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH="$(git remote show "$REMOTE" 2>/dev/null | awk '/HEAD branch/ {print $NF; exit}')"
fi
if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi
[[ -n "$DEFAULT_BRANCH" ]] || die "could not resolve default branch for remote '$REMOTE'"

[[ "$BRANCH" != "$DEFAULT_BRANCH" ]] || die "refusing to operate on the default branch ('$DEFAULT_BRANCH')"

# Find matching worktree by exact path
idx=-1
for i in "${!WT_PATHS[@]}"; do
  p="${WT_PATHS[$i]}"
  # normalize listed path
  if [[ -d "$p" ]]; then
    p="$(cd "$p" && pwd -P)"
  fi
  if [[ "$p" == "$WORKTREE" ]]; then
    idx=$i
    break
  fi
done
[[ $idx -ge 0 ]] || die "worktree not listed in this repository: $WORKTREE"

wt_branch="${WT_BRANCHES[$idx]}"
wt_head="${WT_HEADS[$idx]}"

# Primary worktree = the one whose path equals the worktree containing common-dir's parent
# Linked worktrees have gitdir under $COMMON_DIR/worktrees/<name>
# Primary checkout has .git as a directory equal to COMMON_DIR (or file pointing there without worktrees/ suffix)
is_linked=false
if [[ -f "$WORKTREE/.git" ]]; then
  # linked worktree: .git is a file "gitdir: ..."
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
  # primary checkout — refuse removal
  die "refusing to remove the primary checkout worktree: $WORKTREE"
else
  die "cannot determine worktree linkage for: $WORKTREE"
fi
$is_linked || die "internal: expected linked worktree"

# Ownership: branch must be checked out exactly in this worktree, and nowhere else
[[ -n "$wt_branch" ]] || die "worktree is detached HEAD; refuse (ambiguous ownership)"
[[ "$wt_branch" == "$BRANCH" ]] || die "worktree branch mismatch: expected '$BRANCH', found '$wt_branch'"

owners=0
for i in "${!WT_BRANCHES[@]}"; do
  if [[ "${WT_BRANCHES[$i]}" == "$BRANCH" ]]; then
    owners=$((owners + 1))
  fi
done
[[ $owners -eq 1 ]] || die "ambiguous ownership: branch '$BRANCH' is checked out in $owners worktrees (need exactly 1)"

# Clean tree
if [[ -d "$WORKTREE" ]]; then
  dirty="$(git -C "$WORKTREE" status --porcelain 2>/dev/null || true)"
  [[ -z "$dirty" ]] || die "worktree is dirty; commit/stash/discard before epilogue"
fi

# Ensure we have up-to-date remote default for merge check
info "fetching ${REMOTE}/${DEFAULT_BRANCH} for merge verification"
git fetch "$REMOTE" "$DEFAULT_BRANCH" --quiet

remote_default_ref="refs/remotes/${REMOTE}/${DEFAULT_BRANCH}"
git rev-parse --verify "$remote_default_ref" >/dev/null 2>&1 \
  || die "missing $remote_default_ref after fetch"

branch_tip=""
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  branch_tip="$(git rev-parse "refs/heads/${BRANCH}")"
else
  # fall back to worktree HEAD
  branch_tip="$wt_head"
fi
[[ -n "$branch_tip" ]] || die "could not resolve tip of branch '$BRANCH'"

# Fully merged: no commits on branch that are not on remote default
unmerged_count="$(git rev-list --count "${remote_default_ref}..${branch_tip}")"
[[ "$unmerged_count" == "0" ]] || die "branch '$BRANCH' is not fully merged into ${REMOTE}/${DEFAULT_BRANCH} ($unmerged_count commit(s) ahead); merge first"

# Optional main-checkout validation
if [[ -n "$MAIN_CHECKOUT" ]]; then
  main_idx=-1
  for i in "${!WT_PATHS[@]}"; do
    p="${WT_PATHS[$i]}"
    if [[ -d "$p" ]]; then p="$(cd "$p" && pwd -P)"; fi
    if [[ "$p" == "$MAIN_CHECKOUT" ]]; then main_idx=$i; break; fi
  done
  [[ $main_idx -ge 0 ]] || die "--main-checkout is not a worktree of this repository: $MAIN_CHECKOUT"
  [[ "$MAIN_CHECKOUT" != "$WORKTREE" ]] || die "--main-checkout must not equal --worktree"
fi

# Remote branch presence
remote_branch_exists=false
if git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
  remote_branch_exists=true
fi

echo
echo "=== post-merge epilogue plan ==="
echo "  repo root:       $REPO_ROOT"
echo "  remote:          $REMOTE"
echo "  default branch:  $DEFAULT_BRANCH"
echo "  feature branch:  $BRANCH  (tip ${branch_tip:0:12})"
echo "  worktree:        $WORKTREE"
echo "  remote branch:   $(if $remote_branch_exists; then echo present; else echo already absent; fi)"
echo "  main checkout:   ${MAIN_CHECKOUT:-"(skip)"}"
echo "  mode:            $(if $APPLY; then echo APPLY; else echo DRY-RUN; fi)"
echo

plan_step() { echo "  would: $*"; }
run_step() { echo "  doing: $*"; }

if ! $APPLY; then
  if $remote_branch_exists; then
    plan_step "git push ${REMOTE} --delete ${BRANCH}"
  else
    plan_step "skip remote delete (already absent — likely auto-delete on merge)"
  fi
  plan_step "git worktree remove ${WORKTREE}"
  if [[ -n "$MAIN_CHECKOUT" ]]; then
    plan_step "git -C ${MAIN_CHECKOUT} checkout ${DEFAULT_BRANCH}"
    plan_step "git -C ${MAIN_CHECKOUT} pull --ff-only ${REMOTE} ${DEFAULT_BRANCH}"
  fi
  plan_step "git worktree prune"
  plan_step "git fetch --prune ${REMOTE}"
  echo
  ok "dry-run complete; re-run with --apply --confirm to execute"
  exit 0
fi

# --- apply ---
if $remote_branch_exists; then
  run_step "git push ${REMOTE} --delete ${BRANCH}"
  git push "$REMOTE" --delete "$BRANCH"
  ok "deleted remote branch ${REMOTE}/${BRANCH}"
else
  ok "remote branch already absent"
fi

run_step "git worktree remove ${WORKTREE}"
# Must be invoked from a remaining worktree; use REPO_ROOT if it is not the target.
# If REPO_ROOT == WORKTREE we cannot remove from inside; use MAIN_CHECKOUT or common parent.
remove_cwd="$REPO_ROOT"
if [[ "$REPO_ROOT" == "$WORKTREE" ]]; then
  if [[ -n "$MAIN_CHECKOUT" && -d "$MAIN_CHECKOUT" ]]; then
    remove_cwd="$MAIN_CHECKOUT"
  else
    # fall back to any other listed worktree
    for i in "${!WT_PATHS[@]}"; do
      p="${WT_PATHS[$i]}"
      if [[ -d "$p" ]]; then p="$(cd "$p" && pwd -P)"; fi
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

if [[ -n "$MAIN_CHECKOUT" ]]; then
  run_step "checkout + ff-only pull on main checkout"
  git -C "$MAIN_CHECKOUT" checkout "$DEFAULT_BRANCH"
  git -C "$MAIN_CHECKOUT" pull --ff-only "$REMOTE" "$DEFAULT_BRANCH"
  ok "main checkout at ${MAIN_CHECKOUT} on ${DEFAULT_BRANCH}"
fi

run_step "git worktree prune"
git -C "$remove_cwd" worktree prune
run_step "git fetch --prune ${REMOTE}"
git -C "$remove_cwd" fetch --prune "$REMOTE"

echo
ok "post-merge epilogue complete"
echo "     tip: use 'gh run list' / 'gh run watch' for CI status (not 'gh pr checks')"
