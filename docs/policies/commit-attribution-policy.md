---
title: Commit Attribution Policy
status: draft
version: 0.1.0
---

# Commit Attribution Policy

This policy governs commit author + trailer attribution and PR body attribution for all repositories in the Lanyte ecosystem (lanytehq, 3leaps, fulmenhq, enacthq, namelens, and any future galaxy-organization repos).

It answers three questions:

1. **Who is the git author?** The human supervisor — never the agent.
2. **What email goes in the `Co-Authored-By` trailer?** A galaxy-internal noreply address matching the repo's GitHub organization — never `noreply@anthropic.com` or other model-provider defaults.
3. **What trailer structure carries agent identity?** Three lines per commit; three lines per PR body footer.

## Default Disposition

**Supervised agent commits land under the human supervisor's git identity.** Agent identity is carried in `Co-Authored-By` + `Role` + `Committer-of-Record` trailers — never as the git `author`.

**Email in the `Co-Authored-By` trailer must match the repo's GitHub organization** using the `noreply@<org>.dev` format (or `noreply@<org>.net` if matching the org's domain convention — check existing commits).

## When This Policy Applies

Every commit created in any Lanyte-ecosystem repository by an agent acting under human supervision. This is the operating mode for cxotech / dispatch / devlead / devrev / secrev / prodmktg and all team-scoped roles (alfa, bravo, charlie, etc.).

Applies to: HEREDOC commit messages via Bash, commits authored via `gh` CLI, and any commit-creation path that does not go through a human-typed `git commit` session.

Does NOT apply to: direct human commits where the human is the actual author (no agent involvement).

## Practice

### Per-organization email table

| GitHub org | `Co-Authored-By` email |
|---|---|
| `lanytehq/*` | `noreply@lanytehq.dev` |
| `3leaps/*` | `noreply@3leaps.dev` (or `noreply@3leaps.net` if matching repo's existing convention) |
| `fulmenhq/*` | `noreply@fulmenhq.dev` |
| `enacthq/*` | `noreply@enacthq.dev` |
| `namelens/*` | `noreply@namelens.dev` |

Backstop when unsure: run `git remote -v` first to confirm the org, or inspect prior commits via `git log` for the established trailer style in this repo.

### Commit message trailer structure

Every agent-generated commit appends these three lines as trailers:

```
Role: <your-role-slug>
Committer-of-Record: @<supervisor-handle>

Co-Authored-By: <Model Name> (<context tag>) <noreply@<org>.dev>
```

Example for a cxotech commit on a lanytehq repo, supervised by `@3leapsdave`, authored by Claude Opus 4.7 (1M context window):

```
Role: cxotech
Committer-of-Record: @3leapsdave

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@lanytehq.dev>
```

### PR body footer structure

Every agent-opened PR appends this three-line footer at the bottom of the PR body:

```
---
Drafted-By: <Model Name> (<Agentic Tool>)
Role: <your-role-slug>
PR-of-Record: @<supervisor-handle>
```

Example:

```
---
Drafted-By: Claude Opus 4.7 (1M context, Claude Code)
Role: cxotech
PR-of-Record: @3leapsdave
```

### Git identity discipline

Agents **do not** set local `user.email` or `user.name` via `git config`. The supervised commit lands under the human supervisor's git identity. Agent identity lives in the trailer structure above, not as the git `author`.

Concretely: an agent operating under `@3leapsdave` supervision creates commits authored by `Dave Thompson <dave.thompson@3leaps.net>` (or the supervisor's standard git identity), with the agent attributed in the `Co-Authored-By` trailer.

### Why anti-spoofing matters

Unscrupulous GitHub users have associated `noreply@anthropic.com` (and other model-provider default addresses) with their own accounts. The result: commits appear in those users' GitHub contribution graphs even though they had no involvement in the work. Using galaxy-internal `noreply@<org>.dev` addresses prevents that spoofing path entirely.

This is not optional. `noreply@anthropic.com` is the wrong email for this codebase galaxy — even when an agent's harness defaults to it.

## Cross-References

- **Per-repo AGENTS.md files** cite this policy under their attribution section.
- **`pr-body-vs-squash-commit-shape-policy.md`** — companion policy on the two-audience split between PR body (reviewers now) and squash-commit message (git log readers years out). Attribution trailers travel with both; content within does not.
- **`release-signing-manual-baseline-policy.md`** — release commits follow the same attribution convention; signing keys are a separate identity question.

## History

- **0.1.0 (2026-05-16)** — initial draft. Consolidates the prior session-memory entries on anti-spoofing email format and supervised-commit git-identity discipline into a single policy file. Triggered by the PR 1 cross-repo SSOT framing from dispatch 2026-05-14.
