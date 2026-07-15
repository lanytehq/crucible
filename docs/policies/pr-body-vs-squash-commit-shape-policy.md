---
title: PR Body vs Squash-Commit Shape Policy
status: draft
version: 0.2.0
---

# PR Body vs Squash-Commit Shape Policy

This policy governs the content split between PR body and squash-merged commit message across all Lanyte-ecosystem repositories.

It answers one question:

**What content belongs in the PR body vs. the squash-commit message?** Default: **two different audiences, two different content shapes — don't write one and paste it as both.**

## Default Disposition

**The PR body is a short reviewer orientation for this moment. The squash-commit message is a durable "what changed and why" for someone running `git log` or `git blame` years from now. Neither is a traceability store — the detailed operational record lives out of band.**

The two artifacts coexist and serve distinct purposes, and both are
near-immutable public surfaces on public-bound repositories: PR text is hard
to fully alter after the fact, and squash commits live forever in every
clone. Content that ages out, leaks operational detail, or references
internal-only resources belongs in neither — it belongs in the out-of-band
planning corpus ([ADR-0017](../decisions/adr-0017-oob-planning-root.md)),
which records the verification ledger, discovery narrative, and
delivery-to-planning mapping on the internal side of the boundary.

## When This Policy Applies

Every PR opened in any Lanyte-ecosystem repository where the merge strategy is squash-merge (the standard across lanytehq, 3leaps, fulmenhq Rust release repos and most documentation repos).

Applies whether the PR author is human or agent.

Does NOT apply to: PRs merged via merge-commit or rebase-merge (the commit messages on the feature branch travel through unchanged; per-commit discipline applies instead). The squash-merge concern is specifically about the squash-merge box at merge time.

## Practice

### PR body content (reviewer orientation — keep it short)

Include:

- **What and why**, in a few sentences of self-contained plain language
- **Verification summary** — what classes of checks ran and their outcome
  (one or two lines; not the ledger itself)
- **Reviewer pointers** where genuinely load-bearing — "the risk is
  concentrated in X", "Y is the contested choice"
- **Attribution footer** per [commit-attribution-policy.md](./commit-attribution-policy.md) (Drafted-By + Role + PR-of-Record; bare role names are publicly resolvable via the role catalog and are fine)

Exclude (these live in the out-of-band planning corpus, not the PR):

- **Internal planning identifiers** in any form, per the
  [Audience-Appropriate References Policy](./audience-appropriate-references-policy.md)
- **Verification ledgers** — post IDs, byte counts, command transcripts,
  screenshots, `whoami` responses
- **Discovery/dogfood narrative** — "during the bootstrap I caught X";
  the story of the work is internal record, not public review surface
- **Sidebar findings** unrelated to the change (internal record or a
  separate issue, audience-safely worded)
- **Moment-bound operational detail** — timestamps, live identifiers,
  environment specifics

### Squash-commit message content (durable record)

Include:

- **Posture changes + brief rationale** for non-obvious choices
- **File-by-file what-changed** — one line each, high-signal
- **Cross-references the audience can resolve** — public issue/PR numbers,
  commit hashes, public specs. No internal planning identifiers.
- **Attribution trailers** per [commit-attribution-policy.md](./commit-attribution-policy.md) (Co-Authored-By + Role + Committer-of-Record)

Exclude:

- **No dates** tied to a moment (use version numbers or "this commit" instead)
- **No post IDs, byte counts, row counts** tied to a moment in time
- **No first-person dogfood voice** ("I noticed", "during dogfood", "while doing it I caught")
- **No verification ledger** (out-of-band record; merging duplicates it forever)
- **No sidebar findings** unrelated to the change (separate channel/issue post)
- **No live identifiers** that the registry/code now contains (`user_id X`, `post_id Y`)

### Litmus tests before pasting commit message

Before pasting a commit message into the squash-merge box, run these tests. Drop any sentence that:

1. Starts with "I noticed" / "during dogfood" / "while doing it" / "surfaced"
2. Names a specific timestamp, post ID, byte count, or row count tied to a moment in time
3. Reports verification or test results beyond a one-line summary (out-of-band home)
4. Mentions an unrelated finding (separate channel post or issue)
5. Repeats live identifiers (user IDs, channel IDs) that the registry/code now contains
6. Contains an internal planning identifier (any surface, any form)

If the agent or human authored the commit message before the PR body, expect to rewrite both before merge — the easy default is to paste, but the easy default produces over-detailed commit messages that age into noise.

### Why durable-vs-ephemeral matters

A squash-merge message lives forever in every clone of the repo, and PR text
is near-immutable once posted — on a public-bound repository both are
permanent public surfaces. Operational details that age out become noise
after a quarter and create a mild attacker-recon surface. Containing them in
the out-of-band record keeps the public artifacts clean and the full detail
retrievable by the people entitled to it.

- **PR body**: "what should a reviewer look at right now?"
- **Commit message**: "what does this commit do?"
- **Out-of-band record**: "what exactly happened, verified how, tracked where?"

## Cross-References

- **`commit-attribution-policy.md`** — defines the trailer structure for both PR body footer and squash-commit message. The two-audience content split (this policy) is orthogonal to the attribution structure (other policy).
- **`audience-appropriate-references-policy.md`** — the resolvability rule this policy's exclusions implement on the PR/commit surfaces.
- **`adr-0017-oob-planning-root.md`** — where the excluded detail lives.
- **`public-docs-redaction.md`** — adjacent concern on public-visible content. Squash-commit messages on public repos are public artifacts; this policy's "no live identifiers" rule reinforces the public-docs-redaction stance for the commit-history surface.

## History

- **0.2.0 (2026-07-15)** — aligned with the audience-appropriate-references
  policy 0.2.0 on two-lens review: PR body redefined from "discovery
  snapshot" (verification ledgers, dogfood narrative, post IDs) to short
  reviewer orientation; ledger/narrative relocated to the out-of-band
  planning corpus; internal-planning-identifier exclusion made explicit on
  both surfaces; litmus test 6 added.
- **0.1.0 (2026-05-16)** — initial draft. Consolidates the prior session-memory entry on PR-body-vs-squash-commit content discipline into a platform-public policy. Convention established 2026-05-08 after squash-merges on two prior PRs surfaced the over-detail pattern; PR 1 cross-repo SSOT framing from dispatch 2026-05-14 prompted the move to policy form.
