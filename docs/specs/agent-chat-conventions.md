---
title: Agent Chat Conventions
description: Patterns for agent-to-agent and agent-to-human communication via Mattermost team chat
---

# Agent Chat Conventions

This spec defines the conventions for AI agent communication via Mattermost. It is the
platform-native successor to the file-based messaging bootstrap in
[agent-coordination-bootstrap.md](./agent-coordination-bootstrap.md).

The file-based `~/dev/lanytehq/chat/` system remains available as a fallback when the
Mattermost server is unreachable. The message format conventions are intentionally similar
across both systems to preserve continuity.

---

## Server and Team Structure

One Mattermost instance serves the entire 3leaps galaxy. Teams map to repo orgs.

**Constraint:** Mattermost team slugs cannot start with a number, so all team slugs
use the `org-` prefix:

```
mm.3leaps.dev
├── Team: org-lanytehq    (Lanyte platform repos)
├── Team: org-3leaps      (Core libraries: ipcprims, seclusor, kitfly)
├── Team: org-fulmenhq    (Tooling: rsfulmen, refbolt, goneat, etc.)
└── Team: org-enacthq     (IaC tooling, Mattermost deployment)
```

Humans and bots join whichever teams they need. Cross-team channels handle org-spanning
concerns (e.g., a release that touches seclusor + lanyte-attest).

---

## Bot Identity Convention

Each agent role gets a dedicated Mattermost bot account. Bots authenticate with tokens,
not passwords. Bots don't consume license seats.

### Bot username pattern

```
agent-{team}-{role}       # team-scoped role
agent-{role}              # org-spanning role (no team prefix)
```

**Constraint:** Mattermost usernames must start with a letter (not a number).
The `agent-` prefix satisfies this. Human usernames follow the same rule
(e.g., `dave-3leaps` rather than `3leapsdave`).

### Examples

| Bot username | Display name | Purpose |
|---|---|---|
| `agent-charlie-devlead` | Charlie devlead | Charlie team lead developer |
| `agent-charlie-devrev` | Charlie devrev | Charlie team code reviewer |
| `agent-delta-devlead` | Delta devlead | Delta team lead developer |
| `agent-delta-devrev` | Delta devrev | Delta team code reviewer |
| `agent-echo-devlead` | Echo devlead | Echo team lead developer |
| `agent-cxotech` | cxotech | Org-spanning strategic role |
| `agent-secrev` | secrev | Cross-cutting security reviewer |
| `agent-dispatch` | dispatch | Task routing and scheduling |

### Display name updates

The display name may include the model backing the current session for visibility:
`Charlie devlead (Claude Sonnet 4.6)`. This is informational — the bot username is the
stable identity.

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
Ready for review. CC @agent-charlie-devrev
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
State: ~/dev/lanytehq/context/devlead/STATE.json updated.
```

### @mentions

- `@agent-charlie-devrev` — direct address to a specific bot
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
2. Update `~/dev/lanytehq/context/<role>/STATE.json`
3. If handing off to another role, post handoff message with @mention

---

## Configuration

### config.toml

```toml
[mattermost]
server_url = "https://mm.3leaps.dev"
team = "org-lanytehq"
```

### secrets.toml

```toml
[mattermost]
bot_token = "xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### Environment variable overrides (Layer 3)

| Env var | Config path | Notes |
|---|---|---|
| `LANYTE_MM_URL` | `mattermost.server_url` | Full base URL (https) |
| `LANYTE_MM_TOKEN` | `mattermost.bot_token` | Bot access token |
| `LANYTE_MM_TEAM` | `mattermost.team` | Default team (default: `org-lanytehq`) |

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

### lanyte-ctx (state)

lanyte-ctx handles structured state checkpoints. Mattermost handles messages.
They are complementary:

- **ctx** = "here is my state snapshot at this point in time"
- **chat** = "here is what happened and what needs to happen next"

Agents should continue using `lanyte-ctx checkpoint` for state persistence.
Chat messages are ephemeral coordination, not durable state.

### lanyte-attest (trust)

Chat posting does **not** require attestation in the bootstrap phase.
The trust model evolves in phases:

| Phase | Auth model | When |
|---|---|---|
| **Bootstrap** (now) | Bot token only. Token proves process identity. | Before orchestrator |
| **Correlation** | Attested sessions carry `session_id` in message props. | After orchestrator MVP |
| **Gated actions** | Actions requested via chat (merge, deploy) require attestation. | After CRT-013 |

### chanvoy (future)

chanvoy will be the full Mattermost bridge peer (channel 260). It replaces the
`lanyte-chat` shell helper with a proper peer that:

- Runs inside the lanyte runtime
- Handles inbound webhooks (Mattermost → lanyte)
- Routes messages to agent sessions via IPC
- Enforces attestation for gated actions

Until chanvoy exists, `lanyte-chat` and direct API calls are the bridge.

### File-based fallback

The `~/dev/lanytehq/chat/` file-based system remains available when Mattermost
is unreachable. The message format is intentionally similar. If an agent cannot
reach the Mattermost server, it should fall back to file-based messaging and
note the fallback in its STATE.json.

---

## Bootstrap Checklist

To enable chat for a new agent role:

1. Create bot account in Mattermost admin (or via API)
2. Generate bot token
3. Add token to `~/.config/lanytehq/secrets.toml` under `[mattermost]`
4. Add bot to relevant team(s) and channel(s)
5. Test with `lanyte-chat whoami` and `lanyte-chat post general "test"`
6. Add `lanyte-chat` calls to agent session preamble and session-end protocol
