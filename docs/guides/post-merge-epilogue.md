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

# Apply (preflight all prerequisites; main checkout/ff before delete/remove)
make post-merge-epilogue \
  WORKTREE=... BRANCH=... MAIN_CHECKOUT=... \
  APPLY=1 CONFIRM=1
```

Or: `scripts/post-merge-epilogue.sh --worktree … --branch … [--apply --confirm]`.

## Invariants

- Dry-run uses local remote-tracking refs only; no fetch/push/remove/checkout/prune.
- Default branch is resolved only from remote-tracking HEAD metadata (fail closed).
- Locked target worktrees are refused before any mutation.
- When `--main-checkout` is set it must be the **exact primary** checkout, clean,
  ff-only safe, and the default branch must not be owned by another worktree.
  Checkout + local ff-only run **before** remote delete / worktree remove.
- Removes only via `git worktree remove <exact-path>` — no globs or recursive
  filesystem deletes.
- Controls: `make test-epilogue` (part of `make check`) — disposable bare-remote
  suite covers dirty main, default owned elsewhere, locked target, full apply.

## CI status

Prefer `gh run list` / `gh run watch`. Fine-grained PATs often lack
`checks:read`, so `gh pr checks` is unreliable.
