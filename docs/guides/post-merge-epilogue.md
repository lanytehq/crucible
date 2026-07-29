# Post-merge epilogue

Fail-secure cleanup after a pull request has merged into the default branch.
Same shape as the sibling tooling repos: dry-run by default; destructive steps
require explicit confirmation and absolute path inputs.

## Surface

```bash
# Dry-run (default) — strictly non-mutating (no fetch)
make post-merge-epilogue \
  WORKTREE=/absolute/path/to/task-worktree \
  BRANCH=feature/my-change

# Apply (preflight all prerequisites before any push/remove)
make post-merge-epilogue \
  WORKTREE=... BRANCH=... MAIN_CHECKOUT=... \
  APPLY=1 CONFIRM=1
```

Or: `scripts/post-merge-epilogue.sh --worktree … --branch … [--apply --confirm]`.

## Invariants

- Dry-run uses local remote-tracking refs only; no fetch/push/remove/checkout/prune.
- Default branch is resolved only from remote-tracking HEAD metadata (fail closed).
- When `--main-checkout` is set it must be the **exact primary** checkout, clean,
  and ff-only safe — validated **before** any mutation.
- Refuses the default branch, relative paths, unknown worktrees, the primary
  checkout as a removal target, dirty trees, unmerged tips, and ambiguous ownership.
- Removes only via `git worktree remove <exact-path>` — no globs or recursive
  filesystem deletes.
- Negative + disposable apply controls: `make test-epilogue` (part of `make check`).

## CI status

Prefer `gh run list` / `gh run watch`. Fine-grained PATs often lack
`checks:read`, so `gh pr checks` is unreliable.
