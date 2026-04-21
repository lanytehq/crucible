---
title: Async Interrupt Strategy for Agent Harnesses
description: How Lanyte agents receive off-turn signals (messages, nudges, wake-ups) across Claude Code, opencode, Codex, and Zolkraf without Dave manually relaying Mattermost activity.
status: draft
owner: cxotech
created: 2026-04-18
---

# Async Interrupt Strategy for Agent Harnesses

## Problem

Agents in our current rotation (Claude Code, opencode, Codex, and soon Zolkraf)
are turn-bounded: they act when prompted, then wait for the next human
message. Anything that happens **between** turns — an entarch reply on
Mattermost, a chanvoy mention, a scheduled follow-up firing — is invisible
until either (a) the agent finishes its turn and the human relays, or (b) the
agent guesses to poll.

This manifests today as Dave saying "check Mattermost for a message from
entarch" — a manual bridge where the human is the interrupt controller.
Polling loops (`lanyte-chat read --since N`) work sometimes but burn tokens,
miss activity during long model calls, and still require the agent to
*decide* to poll.

As we scale parallel teams (Alfa/Bravo/Charlie/Delta) and lean harder on
agentic tooling for 3leaps client work, this bottleneck gates throughput.
Without an async signal path, every cross-role handoff is a Dave-mediated
round trip.

## Goal

Agents can notice relevant off-turn events — new messages in their
Mattermost channels, scheduled re-entries, supervisor nudges — through a
mechanism that is (1) cheap in tokens, (2) deterministic about what arrived
since the last check, and (3) consistent enough across harnesses that role
conventions can rely on it.

## Options

### Option A — Per-harness inbox polling (CLI-driven)

Each harness agent runs a lightweight chanvoy check between turns, using the
cursor primitives PER-008 delivers:

```
chanvoy check <channel> --after <last-seen-post-id>
chanvoy notifications --unread
```

These are immediate, exit-coded, and JSON-emitting. A role convention ("call
`chanvoy check` against your channels at the top of every turn, and again
before closing") lets any harness participate without integration work.

**Pros**

- Zero harness-specific work. Ships the day PER-008 lands.
- Uniform across Claude Code, opencode, Codex, Zolkraf. Agents already know
  how to run shell commands.
- Token cost is bounded: a cheap `check` returns a few dozen bytes.
- Cursor-based semantics (PER-008) handle overnight pauses, sleep/wake,
  and restart without loss.

**Cons**

- Still turn-bounded. A long model call blocks the check until the turn
  ends. A message that arrives mid-turn waits for the *next* turn.
- Agent must remember to call `check`. Convention, not enforcement.
- No true push — latency = turn length.

### Option B — Harness-native push integration

Each harness grows a first-class inbox surface. Concretely:

- **Claude Code**: a hook that fires on `Stop` or `PreToolUse` and injects
  new chanvoy messages into the next turn's context (or a slash command
  agents can invoke).
- **opencode**: plugin calling the same chanvoy daemon.
- **Codex**: similar plugin or pre-prompt injection.
- **Zolkraf**: native — the conversation process subscribes to chanvoy
  channel 260 over ipcprims, messages render inline as supervisor
  interventions.

**Pros**

- True async: message arrival triggers agent consideration without waiting
  for turn boundaries (for harnesses that support mid-turn injection).
- Signal quality is high — agent sees the message formatted as a supervisor
  event, not as shell output.
- Zolkraf's version is the product story: "your agent actually notices
  when you message it."

**Cons**

- Per-harness engineering per feature. Claude Code hooks, opencode
  plugins, Codex extensions each need separate work.
- We do not control Claude Code, opencode, or Codex. Their extension
  surfaces constrain what we can build and may change.
- Fragmented UX: same event lands differently in each tool.
- Long tail of edge cases (message while tool-call is executing, rate
  limits, backpressure).

### Option C — Hybrid: CLI-first, harness-native where it pays

Adopt Option A as the baseline contract for all harnesses. Add Option B
only where the harness is ours (Zolkraf) or where the integration is cheap
and high-value (Claude Code hooks, since we already run in Claude Code
heavily).

Concretely:

1. **Every harness**: PER-008 CLI polling per role convention. This is the
   floor.
2. **Claude Code**: add a Stop hook that runs `chanvoy check` across the
   role's subscribed channels and surfaces results in the next turn's
   context. Low investment, high leverage — we live in Claude Code.
3. **Zolkraf**: native ipcprims subscription. This is a *product feature*,
   not just plumbing — the visible advantage over generic coding agents.
4. **opencode, Codex, others**: stay on Option A until usage volume
   justifies the integration cost, or until they expose stable extension
   surfaces we trust.

## Recommendation: Option C

Option A alone leaves too much latency and too much burden on agent
discipline. Option B alone is a money pit — we cannot afford per-harness
engineering for four-plus tools we do not own.

Option C gives us:

- a uniform contract on day one (PER-008 + role convention)
- real async behavior where it matters most (Zolkraf: product story;
  Claude Code: highest volume)
- no wasted work on harnesses whose extension APIs may drift

## Foundation: PER-008 (already delivered)

PER-008 merged 2026-04-14 (chanvoy PR #6, reviewed green by entarch and
secrev). It shipped the primitives this strategy depends on:

- `chanvoy read <channel> --after <post-id>` and `--since-last-mine`
  cursor-based resume
- `chanvoy check <channel>` — observe-only, exit-coded
- `chanvoy notifications --unread` — observe-only mention surface
- durable per-channel / per-mention cursor state with `stale_cursor`
  graceful degradation

The Option A baseline is therefore *already available* to any harness.
Any agent with a sourced identity script and a running chanvoy daemon
can adopt cursor-based resume today by convention alone.

Consumers this strategy now builds on top of:

- **Option C / Claude Code hook**: consumes `chanvoy check --json` and
  `notifications --unread --json` to summarize between-turn activity.
- **Zolkraf native subscriber**: consumes channel 260 directly via
  ipcprims rather than the CLI, but the cursor semantics (post_id
  anchors, stale_cursor fallback) remain the conceptual contract.

The PER-008 follow-on note ("no in-tree daemon-restart / end-to-end
attention-state integration harness yet") is worth tracking against
future hook and Zolkraf integrations — both exercise that path
heavily. Consider a PER-00X follow-up once real consumers expose gaps.

## Implications for Zolkraf (ZOL-005 + future)

ZOL-005 (local scheduler) is one half of Zolkraf's async story — timed
re-entry. The other half is **event-driven re-entry** from chanvoy.
Suggested follow-on (not in ZOL-005's current scope, but adjacent):

- ZOL conversation process subscribes to its role's channel 260 stream
  via ipcprims
- incoming messages surface in the conversation UI as supervisor
  interventions with distinct styling (not as assistant output, not as
  user input — a third event class)
- the scheduler (ZOL-005) and the chanvoy subscriber share a common
  "wake reason" model: `timer`, `message`, `mention`, `supervisor`

Capture this as a DDR when ZOL-005 starts, so the scheduler's event
surface accommodates chanvoy from day one rather than retrofitting.

## Implications for Claude Code (cxotech follow-up)

A thin Stop hook using `chanvoy check --json` against the role's
subscribed channels, writing a compact summary to stderr so the next turn
sees it. Prototype belongs in `lanyte-tools-internal`. Not a sprint task
— a cxotech-run experiment once PER-008 is in. If it works, promote to a
role-onboarding step.

## Out of Scope

- SMS / WhatsApp / textvoy surfaces. Chat-only for now.
- Mid-tool-call injection. If an agent is 40 seconds into a model
  completion, the message waits until that call finishes. Acceptable.
- Cross-role attention routing ("if cxotech is offline, page entarch").
  Later.
- Mattermost presence / read receipts. Nice-to-have; chanvoy already has
  the primitives if we want them.

## Validation Notes

Observations from live use of the Option A baseline during cross-role
coordination work. Captured here because the strategy is easier to
ratify with evidence it works as spec'd.

**2026-04-21 — cxotech poll-for-dispatch-reply** (this session's
dogfood). cxotech posted a follow-up to `#lanyte-dispatch` during the
`lanyte-chat` retirement sweep and needed to know within 2–3 minutes
whether dispatch would reply. Implementation was a harness `Monitor`
wrapping `chanvoy check lanyte-dispatch --after <post-id> --json` at
20-second intervals, breaking on `has_new_messages: true`, with a
180-second timeout.

Observations:

- **Exit-code + JSON combo (C6 + C4) collapsed the poll loop to one
  line of shell**: `echo "$result" | grep -q '"has_new_messages":
  true' && break`. No message parsing, no `jq` pipeline, no English
  string matching.
- **Anchor semantics held as documented**: `anchor_source:
  "explicit_after"` with `has_new_messages: false` is the unambiguous
  "nothing new since X" signal. No ambiguity between "no activity"
  and "broken cursor."
- **20-second probe interval against live Mattermost** was
  imperceptibly cheap. Bounded-window coordination waits (2–3 min)
  are a viable Option A use case.
- **PER-009 was silently load-bearing**: the monitor worked only
  because `chanvoy auto-setup` had run earlier in the session and
  the daemon was alive. Pre-PER-009 (or any non-auto-setup warm-up)
  would have produced `Daemon(NotRunning)` on the first probe. This
  validates the spec's framing of PER-008 + PER-009 as the
  foundation pair Option A builds on — not two independent features.
- **Upper bound on useful poll windows**: the 3-minute cap felt
  right. Beyond that, Option C's harness-native push path becomes
  the better fit. The spec's "layer A baseline + C selective
  upgrade" recommendation matches real use.

**Meta-validation**: this session also surfaced the exact failure
mode Option A is supposed to eliminate — entarch's recurring
`Daemon(NotRunning)` friction while reviewing ADR-0015. Root cause
was not a chanvoy bug but stale `AGENTS.md` warm-up docs still
pointing at `lanyte-chat`. Documentation drift post-PER-009
prevented the Option A contract from being instantiated in the
first place. Captured as the `lanyte-chat` retirement sweep (DSP
card in progress). Lesson for future ratification: a CLI-baseline
async strategy is only as good as the warm-up sequence that
instantiates it.

## Decision Checkpoints

| Checkpoint | Trigger | Who decides |
|------------|---------|-------------|
| Adopt Option C as baseline | PER-008 review | cxotech + entarch |
| Claude Code hook prototype | PER-008 ships | cxotech |
| Zolkraf chanvoy subscriber | ZOL-005 design doc | entarch |
| Promote hook to convention | Hook proves out over a sprint | cxotech + dispatch |

## Status

Draft — circulating for entarch review. Live validation captured
2026-04-21 (see Validation Notes). Not yet ratified.
