---
title: Agent-Friendly CLI Permission Patterns
description: Platform-wide convention for designing CLI surfaces in Lanyte tooling so that agent harnesses (Claude Code, opencode, Codex, Zolkraf) can grant granular permissions with single prefix rules rather than total-release approvals.
status: draft
owner: cxotech
created: 2026-04-18
---

# Agent-Friendly CLI Permission Patterns

## Problem

Modern agent harnesses (Claude Code, opencode, Codex) control tool use
through per-command permission rules. These rules are typically
**prefix-based string matches** against the command the agent is about
to run. A harness can be taught "allow `stashvoy resume *`" cheaply —
one line in a settings file — but cannot easily express "allow this
command as long as its arguments are shaped thus-and-so."

This means the design of our CLIs determines how cheaply agents can
operate under fine-grained permission control. Two patterns that we
accidentally favor today make this harder than it should be:

1. **Compound shell expressions.** An agent that runs
   a loop that `cd`s into several clones and runs `gh pr list` presents the harness with a single opaque shell string.
   The harness cannot permit "run `gh pr list` in three known repos"
   granularly; the agent either gets **total shell release** (risky) or
   a prompt (slow). Field use flagged a concrete case of this.

2. **File-intermediate writes.** Our checkpoint flow today is
   "heredoc-emit a JSON file, then run `stashvoy checkpoint --file`."
   The heredoc step requires permission to write `/tmp/*` (broad);
   the `stashvoy` step requires permission to run the subcommand; and
   there is no single prefix that captures the whole flow. An agent
   that could have written its checkpoint in one invocation has to
   break it into two, each with its own permission gate.

The result: either we ask humans to approve too many prompts (slows
parallelism — the problem Dave flagged when pausing lanytehq work to
move client projects), or we release too much permission surface
(weakens safety posture). Neither is acceptable as we scale to more
parallel teams and more tooling.

## Goal

Every write-capable command in Lanyte tooling exposes a flat,
option-only surface that a harness can allowlist with a single prefix
rule. Every read-capable command is clearly separable from writes and
is aggressively safe to allowlist broadly.

## Non-Goals

- Replacing the harness permission systems themselves. We design _for_
  them, we do not design _them_.
- Solving the compound-shell-expression problem at the harness level.
  That is an agent-discipline issue (don't write loops when you can
  write parallel tool calls). We address only what we can fix in our
  own CLIs.

## Conventions

### C1 — Read vs. write separation by subcommand prefix

Every tool's subcommand tree must let a reviewer tell, **at the prefix
level alone**, whether a command mutates state.

- Pure reads: `<tool> schema *`, `<tool> resume *`, `<tool> show *`,
  `<tool> list *`, `<tool> get *`, `<tool> docs *`.
- Writes: `<tool> checkpoint *`, `<tool> post *`, `<tool> send *`,
  `<tool> set *`, `<tool> delete *`.

A harness rule `Allow: <tool> schema *` must be safe to grant
unconditionally because no subcommand under `schema` will ever mutate
anything. New subcommands that would violate this get renamed.

**Applies to**: `stashvoy`, `chanvoy`, `lanyte-verify`, `ipcprims`
CLI, `lanyte-attest`, `seclusor`, any future tool.

### C2 — Flat option-only surface for writes

Write commands accept all inputs through named flags. No positional
arguments that mix with flags (other than a single optional file
target). No embedded shell expansion. No "run this in a for-loop over
these values."

**Rule of thumb**: if an agent cannot do the operation in a single
`<tool> <subcommand> --flag value --flag value …` invocation, the
command's surface is wrong. Fix the CLI, not the agent's behavior.

The stashvoy option-oriented checkpoint CLI is the template.

### C3 — No file intermediates for the common write path

The common case for writes must not require writing a scratch file
first. File-based entry (`--file`) is allowed as an escape hatch for
large or generated payloads, but it is not the default path.

The file-intermediate antipattern hurts because:

- writing `/tmp/*` needs its own permission grant
- the file is a second source of truth during the few seconds it exists
- compound "heredoc && run" expressions hit C1's shell-release problem

Tools that today require a file intermediate (stashvoy checkpoint
before that checkpoint shape) are explicitly in scope for migration.

### C4 — Structured output via flag, not pipe

Agents consuming tool output should not have to pipe through `jq`,
`awk`, or `grep` for structured data. Every read command that emits
information for programmatic use exposes `--format json` (or
`--json`).

Piping is fine for humans. It is a failure mode for agents: each
additional command in a pipeline is another permission surface and
another failure mode. A tool whose JSON output requires
`| jq '.field'` to be useful is forcing agents into shell composition.

### C5 — Flag shape by input shape

Different input shapes call for different flag patterns. Three cases,
three patterns:

**String arrays — repeatable flag per item.**

```
--completed "Item A" --completed "Item B"
```

not:

```
--completed "Item A,Item B"           # CSV; breaks on commas in values
--completed '["Item A", "Item B"]'    # JSON literal; fragile under shell
```

Repeatable flags are trivially safe under shell quoting, require no
escape logic inside values, and are the pattern agents are most
familiar with across tools.

**Singleton nested objects with fixed shape — explicit prefixed
flags per field.**

```
--active-task-id CTX-DX-001
--active-task-title "Schema introspection"
--active-task-status in-progress
--active-task-next-action "Review with entarch"
```

not:

```
--active-task 'id=CTX-DX-001,title=...,status=...,next-action=...'
```

Reason: when the object has a fixed, known shape (appears at most
once, field names are schema-defined), explicit prefixed flags give
you clap-level type validation, per-field `--help` discoverability,
and no shell-quoting gotchas on commas or equals inside free-text
values like titles or descriptions. The `k=v` pattern works but is
strictly worse here — it loses all three benefits without any
counterbalancing gain.

Applies to: any schema-defined singleton nested object. Examples in
our tooling: `active_task`, `authored_by`.

**Repeatable arrays of small objects — `k=v,k=v` per occurrence.**

```
--pending 'action=Post note,owner=cxotech,priority=P1'
--pending 'action=Merge PR,owner=3leapsdave,priority=P2'
```

not:

```
--pending '{"action":"Post note",...}'  # embedded JSON; fragile
--pending-1-action "Post note" \
--pending-1-owner cxotech \
--pending-1-priority P1 \
--pending-2-action "Merge PR" \
--pending-2-owner 3leapsdave \
--pending-2-priority P2                 # indexed flag groups; ugly and
                                        # unbounded in arity
```

Reason: indexed-flag groups get ugly fast and require arity-matching
logic across flag families; embedded JSON hits the same
outer-quoting-under-shell-expansion failure C2 forbids elsewhere;
`k=v` per occurrence is the compromise that stays shell-safe with
bounded parsing complexity.

Applies to: any schema-defined array-of-objects input. Examples in
our tooling: `pending_actions[]`.

**Rule of thumb**: if the object appears at most once and its fields
are load-bearing for validation and help text, use explicit prefixed
flags. If the object is one of many in an array, use `k=v`. If the
array is just strings, use repeatable flag. Never embed JSON in a
flag value.

### C6 — Exit codes that branch cleanly

Every command uses exit codes that let a caller branch without parsing
stderr:

- `0` — success, state as expected
- `1` — expected alternative (e.g., `check` found no new messages)
- `2` — validation or input error (user-fixable)
- `3`+ — system / transient errors

Callers should not need to grep stderr to tell "no results" from
"broken." Chanvoy `check` exit-code contract is the
reference.

### C7 — stdout purity

Programmatic output (JSON, structured data) goes to **stdout**;
diagnostics, confirmations, and human-facing logs go to **stderr**.
stashvoy established this; it is now the platform rule.

Violation test: `<tool> <subcommand> --format json > out.json` must
produce a clean parseable file, with zero stray text.

### C8 — Idempotent where possible

Writes should tolerate replay where the semantics permit it. A repeat
checkpoint with the same content should not corrupt state; a repeat
`chanvoy post` with the same dedupe key should not double-post. This
reduces the cost of the "did my last command actually succeed?" retry
loop agents sometimes enter under unreliable harnesses.

Where idempotency is impossible (hash-chained audit writes,
monotonic counters), document it clearly in `docs show <command>`.

## Anti-Patterns

These should not appear in Lanyte tooling. Code review should call
them out.

- Commands whose only happy path requires `&&`-chaining.
- Commands that require an intermediate file for input when a small
  set of flags would suffice.
- Commands that emit banner text to stdout before the structured
  payload.
- Commands whose "failure" state is distinguished from "no results"
  only by reading a message.
- Array or object inputs that must be JSON-stringified by the caller.
- Subcommand trees where the reader cannot tell mutation vs. read from
  the prefix alone.

## Harness Integration Examples

### Claude Code

Once all Lanyte CLIs follow these conventions, a Claude Code
`settings.json` `permissions.allow` entry like:

```json
{
  "permissions": {
    "allow": [
      "Bash(stashvoy schema *)",
      "Bash(stashvoy resume *)",
      "Bash(stashvoy docs *)",
      "Bash(stashvoy checkpoint *)",
      "Bash(chanvoy check *)",
      "Bash(chanvoy read *)",
      "Bash(chanvoy notifications *)"
    ]
  }
}
```

covers the entire routine-operation surface with a handful of prefix
rules — no total shell release. Agents operate without prompts for any
of the core warm-up / checkpoint / check-inbox flow.

### opencode, Codex, Zolkraf

Same prefix matches work. Zolkraf's permissions matrix (ZOL-004)
should adopt these conventions natively since it controls its own
allowlist model.

## Applicability and Rollout

In-scope tools (today):

- **stashvoy** — schema introspection and option-oriented checkpoint
  (option-oriented checkpoint) bring it into compliance.
- **chanvoy** — `check` / wait already follow these patterns (exit
  codes, JSON output, cursor flags). Audit at review.
- **lanyte-chat** — being retired in favor of chanvoy; no work.
- **lanyte-verify, lanyte-attest** — audit during next touch.
- **seclusor** — audit during next touch.
- **ipcprims CLI** — audit during next touch.

Rollout strategy:

1. Ratify this spec (entarch + cxotech review).
2. Apply during the next modification of each tool rather than a
   dedicated sweep. Low cost, no disruption.
3. Add a devrev checklist item: "any new subcommand respects C1-C8."
4. Capture violations as follow-up tasks, not blockers.

## Out of Scope

- Harness-native integrations (covered in
  `async-interrupt-strategy.md`).
- Permission-policy content itself (what to grant at what tier) —
  that is role onboarding / SOP territory.
- WASM skill permission model — governed by STD-004 / STD-005, not
  CLI conventions.

## Status

Draft — circulating for entarch review. Not yet ratified.
