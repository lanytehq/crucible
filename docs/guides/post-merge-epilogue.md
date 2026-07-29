# Post-merge epilogue

Fail-secure cleanup after a pull request has merged into the default branch.
Same shape as the sibling tooling repos: dry-run by default; destructive steps
require explicit confirmation and absolute path inputs.

## Surface

```bash
# Dry-run (default)
make post-merge-epilogue \
  WORKTREE=/absolute/path/to/task-worktree \
  BRANCH=feature/my-change

# Apply
make post-merge-epilogue \
  WORKTREE=... BRANCH=... MAIN_CHECKOUT=... \
  APPLY=1 CONFIRM=1
```

Or: `scripts/post-merge-epilogue.sh --worktree … --branch … [--apply --confirm]`.

## Invariants

- Refuses the default branch, relative paths, unknown worktrees, the primary
  checkout, dirty trees, unmerged tips, and ambiguous multi-worktree ownership.
- Removes only via `git worktree remove <exact-path>` — no globs or recursive
  filesystem deletes.
- Negative controls: `make test-epilogue` (part of `make check`).

## CI status

Prefer `gh run list` / `gh run watch`. Fine-grained PATs often lack
`checks:read`, so `gh pr checks` is unreliable.
