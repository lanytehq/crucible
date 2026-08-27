---
title: Agent Chat Conventions
description: Patterns for agent-to-agent and agent-to-human communication via Mattermost team chat
---

# Agent Chat Conventions

This spec defines the conventions for AI agent communication via Mattermost. It is the
platform-native successor to the file-based messaging bootstrap in
[agent-coordination-bootstrap.md](./agent-coordination-bootstrap.md).

An operator-local file fallback remains available when the chat server is
unreachable. Message format conventions are intentionally similar across both
systems.

---

## Server and team structure

A self-hosted Mattermost instance may serve multiple GitHub orgs. Team slugs
map to orgs. Mattermost team slugs cannot start with a number, so a prefix such
as `org-` is used. Exact hostnames and team lists are operator configuration,
not this contract.

---

## Bot Identity Convention

Each agent role gets a dedicated Mattermost bot account. Bots authenticate with tokens,
not passwords. Bots don't consume license seats.

### Bot username pattern

```
agent-{team}-{role}       # team-scoped role
agent-{role}-{org}        # org-scoped role
agent-{role}              # ecosystem-wide role (currently only dispatch)
```

**Constraint:** Mattermost usernames must start with a letter (not a number).
The `agent-` prefix satisfies this. Human usernames follow the same rule
(e.g., `dave-3leaps` rather than `3leapsdave`).

### Examples (patterns only)

| Bot username pattern  | Kind        |
| --------------------- | ----------- |
| `agent-<team>-<role>` | Team-scoped |
| `agent-<role>-<org>`  | Org-scoped  |
| `agent-<role>`        | Estate-wide |

### Display name updates

The display name may include the model backing the current session. That is
informational — the bot username is the stable identity.

---

## Chanvoy Profile Naming

A **chanvoy profile** is a local configuration binding on a dev machine that pairs a
Mattermost bot token, bot username, team, and daemon socket under a short name.
Multiple profiles coexist on one machine; CLI invocations target one at a time via
the `--profile <name>` flag, or via default resolution (described below) when the
flag is absent. The profile name is therefore load-bearing for both human ergonomics
and deterministic default resolution.

### Convention

A chanvoy profile name MUST match the identity-script stem: `<role>-<scope>`.

| Identity script             | Chanvoy profile          |
| --------------------------- | ------------------------ |
| `cxotech-lanytehq.sh`       | `cxotech-lanytehq`       |
| `cxotech-enacthq.sh`        | `cxotech-enacthq`        |
| `bravo-devlead-lanytehq.sh` | `bravo-devlead-lanytehq` |
| `dispatch-lanytehq.sh`      | `dispatch-lanytehq`      |

Scope suffix is required even for team-scoped roles where the scope is unambiguous
today (e.g., `bravo-devlead-lanytehq`). The uniformity buys a simpler default-resolution
rule and removes special cases for "does this role span orgs?" The identity script's
filename is the source of truth for both `<role>` and `<scope>` segments.

### Implication for CLI default resolution

Because profile names follow `<role>-<scope>`, every chanvoy CLI verb that targets a
profile or daemon can resolve its target from sourced environment without an explicit
`--profile` flag. The canonical rule:

1. If `LANYTE_AGENT_ROLE` and `LANYTE_AGENT_SCOPE` are both set in the environment,
   resolve to `${LANYTE_AGENT_ROLE}-${LANYTE_AGENT_SCOPE}` and act on that profile.
   Resolution is by **exact profile name**, not by filtering profiles whose role and
   scope happen to match — when sibling profiles exist (e.g., bootstrap or test
   variants), exact-name match must win and the filter step must never bail on
   ambiguity before the exact match gets a turn.
2. Else if exactly one chanvoy daemon is running on this machine, act on that
   profile (single-tenant fallback).
3. Else refuse with a clear error, print live profiles, and require an explicit
   `--profile`.

**Persistent local-state pointers MUST NOT participate in rule #1.** A last-used or
"active profile" marker file on disk is cross-session state on a shared machine — it
silently carries one operator's choice into another operator's default resolution and
has been observed to produce silent identity-attribution drift (an operator's command
posting under a different bot's identity). Rule #1 derives exclusively from the
current process environment. Any persistent marker file may serve as a convenience
for single-tenant setups but MUST be consulted strictly lower than rules #1 and #2,
and MUST NOT override an env-derived resolution.

This rule applies to every CLI verb that takes a single profile or daemon as its
target. Verbs that manage the profile _collection_ (enumerate it, or create new
entries) bypass the resolver entirely, since they don't have a target to resolve.

**Resolver applies:** `daemon {start, stop, status}`, `profile active`, `post`,
`read`, `check`, `whoami`, `attention`, and any future verbs that address a single
profile or daemon.

**Resolver bypassed:** `profile {list, create, create-from-env}` and `auto-setup`.
The collection-management verbs (`profile {list, create, create-from-env}`) operate
on the profile collection (enumerate, append) rather than targeting a single
profile. The `auto-setup` bootstrap verb creates-or-refreshes the canonical
`${LANYTE_AGENT_ROLE}-${LANYTE_AGENT_SCOPE}` profile from sourced env — it must
work even when that profile doesn't yet exist (the bootstrap chicken-and-egg).
Forcing the resolver on any of these would brick fresh bootstrap on an empty
config (cannot enumerate zero profiles, cannot create the first profile, cannot
materialize the canonical profile from a fresh machine).

Within the "resolver applies" set there is no verb-specific default; absence of
`--profile` always triggers the resolution rule above. Within the "resolver bypassed"
set, hardcoded scope defaults still MUST be removed — for example, `org-lanytehq`
as the default for `--team-name` on `profile create` carries a single-org bias and
produces wrong-target behavior in multi-org use. Where a flag's value can be derived
from `$LANYTE_AGENT_ROLE` or `$LANYTE_AGENT_SCOPE`, derive it; otherwise require it
explicitly.

### Migration

Historical profiles created under bare names predate this convention and must be
renamed to their true `<role>-<scope>` form regardless of which scope they resolve to.
Dispatch owns the sweep: bare `<role>` → `<role>-lanytehq` for lanytehq-scoped
profiles, bare `<role>` → `<role>-enacthq` for enacthq-scoped profiles, with parallel
partners created where an identity script for the other scope exists. Test and scratch
profiles (`*-bootstrap`, `*-custom-team`, `temp-*`) are separately eligible for
cleanup during the sweep.

The rename is destructive for running daemons — each affected daemon must stop
cleanly before its profile is renamed, or per-profile cursor state can desync.
Coordinate the sweep in a maintenance window with all active operators aware.

---

## Channel Structure

### Per-team channels

```
#general                  ← team-wide announcements
#pr-reviews               ← PR notifications and review requests
#ci-status                ← CI pass/fail notifications
#releases                 ← release coordination
```

### Per-team role channels

```
#lanyte-cxotech           ← messages addressed to cxotech
#lanyte-devlead           ← messages addressed to team devleads
```

### Per-team parallel team channels

```
#charlie-team             ← Charlie team coordination
#delta-team               ← Delta team coordination
#echo-team                ← Echo team coordination
```

### Channel naming rules

- Lowercase alphanumeric + hyphens only
- Team channels prefixed with team name: `#charlie-team`
- Role channels prefixed with org slug: `#lanyte-cxotech`
- Task-specific channels use stream prefix: `#agi-013`, `#crt-012`
  (create as needed, archive when task completes)

---

## Message Conventions

### Structured messages

Agents should use consistent formatting for machine-parseable context:

```markdown
**Session started** | role: devlead | team: charlie | task: AGI-013
Reading channel backlog...
```

```markdown
**PR opened** | repo: lanytehq/lanyte | PR #17
AGI-013: add Claude live validation tests
Ready for review. CC @agent-<team>-devrev
```

```markdown
**Handoff** | from: devlead | to: devrev
PR #17 is ready. Key review focus: `claude_live.rs` tool round-trip test.
Conformance harness passes. Live tests pass with key set.
```

```markdown
**Session ended** | role: devlead | team: charlie | task: AGI-013
Completed: claude_live.rs with 4 test cases. PR #17 open.
Next: devrev review, then merge.
State: role STATE.json updated.
```

### @mentions

- `@agent-<team>-devrev` — direct address to a specific bot
- `@dave-3leaps` — direct address to human supervisor
- `@channel` — notify all channel members (use sparingly)

### Message props (future)

Mattermost supports custom message properties (`props` field). When the orchestrator
exists, messages will carry structured metadata:

```json
{
  "props": {
    "lanyte_session_id": "uuid",
    "lanyte_role": "devlead",
    "lanyte_team": "charlie",
    "lanyte_task": "AGI-013"
  }
}
```

This is informational until the orchestrator can act on it. Do not depend on props for
routing or authorization in the bootstrap phase.

---

## Agent Session Protocol

### Session start

1. Read bot token from config (see Configuration below)
2. Verify identity: `lanyte-chat whoami`
3. Read channel backlog: `lanyte-chat read <team-channel> --since 120`
4. Post session start message to team channel

### During session

- Post status updates at natural milestones (PR opened, tests passing, blocked)
- When waiting for another role (CI, review, build), poll the channel periodically
  for responses (~2 minute intervals)
- Address specific roles with @mentions when requesting action

### Session end

1. Post session summary to team channel (what was done, what's next)
2. Update role `STATE.json` (operator-local; not this repository)
3. If handing off to another role, post handoff message with @mention

---

## Configuration

### config.toml

```toml
[mattermost]
server_url = "https://chat.example.invalid"
team = "org-example"
```

### secrets.toml

Store the bot token in a secrets file or secret store. Never commit it.
Do not put tokens in `config.toml`.

### Environment variable overrides

The chat CLI binds server URL, bot token, and default team from operator
environment or a local profile. Variable names are a local profile concern,
not this contract.

### Security

- Bot tokens are bearer credentials — treat like API keys
- Store in `secrets.toml` or `secrets.age`, never in `config.toml`
- TLS required — all API calls over HTTPS
- Bot tokens scope access to the bot's identity — cannot impersonate users or access
  admin APIs
- Tokens are not attestation — they prove "this is an authorized process," not
  "this agent is attested for role X." See phase notes below.

---

## Relationship to Other Systems

### stashvoy (state)

stashvoy handles structured state checkpoints. Mattermost handles messages.
They are complementary:

- **ctx** = "here is my state snapshot at this point in time"
- **chat** = "here is what happened and what needs to happen next"

Agents should continue using `stashvoy checkpoint` for state persistence.
Chat messages are ephemeral coordination, not durable state.

### lanyte-attest (trust)

Chat posting does **not** require attestation in the bootstrap phase.
The trust model evolves in phases:

| Phase               | Auth model                                                      | When                   |
| ------------------- | --------------------------------------------------------------- | ---------------------- |
| **Bootstrap** (now) | Bot token only. Token proves process identity.                  | Before orchestrator    |
| **Correlation**     | Attested sessions carry `session_id` in message props.          | After orchestrator MVP |
| **Gated actions**   | Actions requested via chat (merge, deploy) require attestation. | After session attest   |

### chanvoy (future)

chanvoy will be the full Mattermost bridge peer (channel 260). It replaces the
`lanyte-chat` shell helper with a proper peer that:

- Runs inside the lanyte runtime
- Handles inbound webhooks (Mattermost → lanyte)
- Routes messages to agent sessions via IPC
- Enforces attestation for gated actions

The chat CLI (`chanvoy`) is the current bridge.

### File-based fallback

An operator-local file inbox remains available when Mattermost is unreachable.
The message format is intentionally similar. Note the fallback in role state.

---

## Bootstrap Checklist

To enable chat for a new agent role:

1. Create a bot account in Mattermost admin (or via API)
2. Generate a bot token; store it in the operator secret store / CLI profile (never commit it)
3. Add the bot to relevant team(s) and channel(s)
4. Test with the chat CLI `whoami` and a throwaway `post`
5. Use the chat CLI in session start/end, not a retired helper name
