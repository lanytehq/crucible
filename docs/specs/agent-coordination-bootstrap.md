---
title: Agent Coordination Bootstrap
description: Minimal no-infrastructure patterns for multi-agent coordination on the Lanyte platform during early development
---

# Agent Coordination Bootstrap

This spec defines the minimal coordination infrastructure for supervised and autonomous AI agents working on the Lanyte platform. It requires **no servers, no databases, no network services** — only the local filesystem.

This is the bootstrap pattern. When Lanyte's own agent infrastructure (memory store per ADR-0009, Mattermost proxy for messaging) is operational, these patterns transition to platform-native equivalents. The conventions remain stable across the transition.

---

## Three Functions

Agent coordination requires exactly three cross-repo functions:

| Function      | Purpose                             | Location                                | Scope                    |
| ------------- | ----------------------------------- | --------------------------------------- | ------------------------ |
| **Messaging** | Inter-role communication            | `~/dev/lanytehq/chat/`                  | Append-only, per-channel |
| **Context**   | Per-role persistent state           | `~/dev/lanytehq/context/<role>/`        | Read-write, per-role     |
| **Roles**     | Identity and capability definitions | `config/agentic/roles/` | Git-versioned, canonical |

All three are local-machine-only (not committed to any repo) except Roles, which are the canonical source of truth in crucible.

---

## 1. Messaging (`chat/`)

File-based append-only messaging. One markdown file per channel.

### Channel structure

```
~/dev/lanytehq/chat/
├── README.md          ← conventions
├── general.md         ← cross-task discussion
├── crt-001.md         ← task-specific coordination
├── reviews.md         ← PR review requests and handoffs
└── <topic>.md         ← as needed
```

### Message format

```markdown
---
**[role:<slug>]** <ISO-8601 timestamp>

Message body. Markdown supported. Reference files by absolute path.
Tag other roles with @role:<slug> when requesting action.

---
```

Human supervisor messages use `**[@3leapsdave]**`.

### Rules

- **Append only** — never edit or delete previous messages
- **One message per `---` block** — delimited by horizontal rules
- **Include role slug and timestamp** — enables filtering and auditing
- **Reference files by absolute path** — no ambiguity across repos
- **Create channels as needed** — one file per task or topic is fine
- **No secrets** — ever, not even redacted

### Transition to Mattermost

When the Mattermost proxy is operational:

- Channel files map 1:1 to Mattermost channels
- Message format stays the same (markdown body with role attribution)
- Agents use MCP tools (`send_message`, `read_messages`) instead of file I/O
- File-based chat remains available as fallback

---

## 2. Context (`context/`)

Persistent per-role working state that survives across sessions.

### Directory structure

```
~/dev/lanytehq/context/
├── README.md
├── cxotech/
│   ├── STATE.md                   ← current state (overwritten each session)
│   ├── handoff-2026-02-23.md      ← session handoff notes (dated)
│   ├── brief-<slug>.md            ← briefs for other roles
│   └── <topic>.md                 ← persistent notes
├── devlead/
│   ├── STATE.md
│   └── ...
├── devrev/
├── secrev/
├── dispatch/
└── deliverylead/
```

### STATE.md convention

Every role directory has a `STATE.md` that is the quick-read entry point. Format:

```markdown
# <role> — Current State

**Updated**: YYYY-MM-DD

## Active work

- ...

## Recently completed

- ...

## Open decisions

- ...

## Blockers

- ...
```

### Session lifecycle

1. **Start**: Read your role's `STATE.md`. Read recent `handoff-*.md` files.
2. **During**: Update working artifacts as needed.
3. **End**: Overwrite `STATE.md` with current state. Write `handoff-YYYY-MM-DD.md` if the next session needs context.

### What goes here vs. elsewhere

| Content                              | Location                                        |
| ------------------------------------ | ----------------------------------------------- |
| Working notes, drafts, decision logs | `context/<role>/`                               |
| Inter-role messages                  | `chat/`                                         |
| Code, schemas, specs                 | The appropriate repo                            |
| Task status, sprint boards           | `lanyte-productbook-internal/content/projmgmt/` |
| Agent tool memory (Claude Code)      | `~/.claude/projects/.../memory/`                |

### Transition to Lanyte memory

When lanyte-state (SQLite + INSERT-only, per ADR-0009) is operational:

- `STATE.md` maps to agent memory records
- Handoff notes map to memory with `superseded_by` chains
- Context directory remains as development convenience and bootstrap fallback

---

## 3. Roles (canonical catalog)

Role definitions live in `config/agentic/roles/`. This is the single source of truth for what roles exist, what they do, and when to use them.

### Quick reference

| Slug           | Category   | Timeline       | Primary use                     |
| -------------- | ---------- | -------------- | ------------------------------- |
| `devlead`      | agentic    | Hours-Days     | Implementation                  |
| `devrev`       | review     | Hours-Days     | Code review                     |
| `secrev`       | review     | Days-Week      | Security audit                  |
| `qa`           | review     | Hours-Week     | Testing                         |
| `cxotech`      | governance | Strategic      | Architecture, product direction |
| `dispatch`     | governance | Minutes-Days   | Session routing                 |
| `deliverylead` | governance | Sprint-Quarter | Project coordination            |
| `cicd`         | automation | Days-Week      | Pipelines                       |
| `releng`       | automation | Quarter        | Releases                        |
| `infoarch`     | agentic    | Days-Sprint    | Documentation                   |
| `skillauthor`  | agentic    | Days-Sprint    | WASM skill authoring            |
| `prodmktg`     | agentic    | Quarter        | Branding, messaging             |

Full catalog with escalation paths and decision matrices:
`~/dev/lanytehq/crucible/config/agentic/roles/README.md`

### Agent invocation preamble

When starting a new agent session, use this standard preamble:

```
You are <role> on the Lanyte platform.
Read ~/dev/lanytehq/crucible/docs/guides/dev-warmup.md before starting.
Read ~/dev/lanytehq/context/<role>/STATE.md for current state.
Working repo: ~/dev/lanytehq/<repo>/.
Task: <description>
```

### Attribution

**Commit trailers:**

```
Co-Authored-By: <Model Name> <noreply@lanytehq.dev>
Role: <role-slug>
Committer-of-Record: @3leapsdave
```

**PR body footer:**

```
---
Drafted-By: <Model Name> (<Agentic Tool>)
Role: <role-slug>
PR-of-Record: @3leapsdave
```

Substitute your model name, agentic tool, and role slug. The email domain `noreply@lanytehq.dev` is fixed — do not use other domains.

---

## Surface relationships

```
┌──────────────────────────────────────────────────┐
│ Agent Session                                    │
│                                                  │
│  reads ─► context/<role>/STATE.md (where am I?)  │
│  reads ─► chat/<channel>.md    (what's pending?) │
│  reads ─► roles/<role>.yaml    (who am I?)       │
│                                                  │
│  writes ► context/<role>/STATE.md (update state)  │
│  writes ► chat/<channel>.md    (message others)  │
│  writes ► repos/*              (actual work)     │
│                                                  │
│  reads ─► projmgmt/           (task board)       │
│  reads ─► dev-warmup.md       (platform context) │
└──────────────────────────────────────────────────┘
```

---

## Bootstrap vs. Platform

| Function       | Bootstrap (now)                          | Platform (future)                         |
| -------------- | ---------------------------------------- | ----------------------------------------- |
| Messaging      | `chat/*.md` files                        | Mattermost channels via MCP proxy         |
| Context        | `context/<role>/STATE.md`                | lanyte-state memory store (ADR-0009)      |
| Roles          | `crucible/config/agentic/roles/`         | Same (git-versioned, canonical)           |
| Task boards    | `productbook-internal/content/projmgmt/` | Same or GitHub Issues                     |
| Agent identity | Role slug in preamble                    | Platform-issued identity with credentials |
| Notifications  | Poll files                               | Mattermost push / webhook                 |

The conventions (message format, STATE.md structure, role slugs, attribution) stay the same. Only the transport changes.
