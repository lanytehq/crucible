---
title: PR Body vs Squash-Commit Shape Policy
status: draft
version: 0.1.0
---

# PR Body vs Squash-Commit Shape Policy

This policy governs the content split between PR body and squash-merged commit message across all Lanyte-ecosystem repositories.

It answers one question:

**What content belongs in the PR body vs. the squash-commit message?** Default: **two different audiences, two different content shapes — don't write one and paste it as both.**

## Default Disposition

**The PR body is a discovery snapshot for reviewers in this moment. The squash-commit message is a durable "what changed and why" for someone running `git log` or `git blame` years from now.**

The two artifacts coexist and serve distinct purposes. Operational details that age out (timestamps, post IDs, byte counts, live identifiers) belong in the PR body — they help reviewers and stay containable as the PR thread ages. They do NOT belong in the squash-commit message, which lives forever in every clone of the repo.

## When This Policy Applies

Every PR opened in any Lanyte-ecosystem repository where the merge strategy is squash-merge (the standard across lanytehq, 3leaps, fulmenhq Rust release repos and most documentation repos).

Applies whether the PR author is human or agent.

Does NOT apply to: PRs merged via merge-commit or rebase-merge (the commit messages on the feature branch travel through unchanged; per-commit discipline applies instead). The squash-merge concern is specifically about the squash-merge box at merge time.

## Practice

### PR body content (discovery snapshot)

Include:

- **Dogfood narrative** — "during the bootstrap I caught X", "while doing it I noticed Y"
- **Verification ledger** — post IDs, byte counts, command output, `whoami` responses, screenshots
- **Specific dates and version pins** — when something was discovered, what version was current at the time
- **Sidebar findings** — "the 2026-04-30 secrev gap appears resolved", "noticed an unrelated thing worth flagging"
- **First-person voice** describing the discovery flow
- **Test plan checkboxes** — what was verified, with detail on commands run
- **Attribution footer** per [commit-attribution-policy.md](./commit-attribution-policy.md) (Drafted-By + Role + PR-of-Record)

### Squash-commit message content (durable record)

Include:

- **Posture changes + brief rationale** for non-obvious choices
- **File-by-file what-changed** — one line each, high-signal
- **Cross-references** to other commits, briefs, or specs that establish the contract being changed
- **Attribution trailers** per [commit-attribution-policy.md](./commit-attribution-policy.md) (Co-Authored-By + Role + Committer-of-Record)

Exclude:

- **No dates** tied to a moment (use version numbers or "this commit" instead)
- **No post IDs, byte counts, row counts** tied to a moment in time
- **No first-person dogfood voice** ("I noticed", "during dogfood", "while doing it I caught")
- **No verification ledger** (already in PR body; merging duplicates it forever)
- **No sidebar findings** unrelated to the change (separate channel/issue post)
- **No live identifiers** that the registry/code now contains (`user_id X`, `post_id Y`)

### Litmus tests before pasting commit message

Before pasting a commit message into the squash-merge box, run these tests. Drop any sentence that:

1. Starts with "I noticed" / "during dogfood" / "while doing it" / "surfaced"
2. Names a specific timestamp, post ID, byte count, or row count tied to a moment in time
3. Reports verification or test results (PR-body home)
4. Mentions an unrelated finding (separate channel post or issue)
5. Repeats live identifiers (user IDs, channel IDs) that the registry/code now contains

If the agent or human authored the commit message before the PR body, expect to rewrite both before merge — the easy default is to paste, but the easy default produces over-detailed commit messages that age into noise.

### Why durable-vs-ephemeral matters

A squash-merge message lives forever in every clone of the repo. Operational details that age out become noise after a quarter. They also create a mild attacker-recon surface — repeating internal details across every artifact instead of containing them in PR-body discussion that can be revisited intentionally.

The PR body and commit message both stay, but they answer different questions:

- **PR body**: "what was discovered when this was reviewed?"
- **Commit message**: "what does this commit do?"

## Cross-References

- **`commit-attribution-policy.md`** — defines the trailer structure for both PR body footer and squash-commit message. The two-audience content split (this policy) is orthogonal to the attribution structure (other policy).
- **`public-docs-redaction.md`** — adjacent concern on public-visible content. Squash-commit messages on public repos are public artifacts; this policy's "no live identifiers" rule reinforces the public-docs-redaction stance for the commit-history surface.

## History

- **0.1.0 (2026-05-16)** — initial draft. Consolidates the prior session-memory entry on PR-body-vs-squash-commit content discipline into a platform-public policy. Convention established 2026-05-08 after squash-merges on two prior PRs surfaced the over-detail pattern; PR 1 cross-repo SSOT framing from dispatch 2026-05-14 prompted the move to policy form.
