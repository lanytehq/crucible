# AI Agent Guide — lanyte-crucible

**Start here first**: `docs/guides/dev-warmup.md` — the platform-wide warm-up for all core development agents.

**Then read `REPOSITORY_SAFETY_PROTOCOLS.md`.** If a request conflicts with it, stop and escalate to @3leapsdave.

---

## What This Repo Is

`lanyte-crucible` is the **single source of truth (SSOT)** for all Lanyte platform contracts. Nothing is implemented before its contract exists here. All other repos are downstream consumers.

Contents:

- `schemas/ipc/` — JSON Schema 2020-12 files for all IPC channels (loaded by ipcprims at runtime)
- `schemas/agentic/` — Role prompt schema and capability taxonomy schema
- `docs/decisions/` — ADRs (Architecture Decision Records), SDRs, DDRs
- `docs/specs/` — Canonical specifications (Skill ABI, peer contract, capability taxonomy)
- `config/agentic/roles/` — Agent role definitions for the Lanyte platform
- `docs/policies/` — Security and operational policies

---

## Lanyte Platform Context

Lanyte is a **secure, self-hosted autonomous AI agent platform**. Key architecture:

- **Core** (`lanyte`, Rust, TCB) — the only fully trusted component. Everything else is a peer.
- **Peers** connect to core via ipcprims IPC sockets. Each peer gets a schema-validated channel.
- **Skills** are WASM modules that run inside the executor sandbox inside core.
- **ipcprims** (`3leaps/ipcprims`, v0.1.3) — the IPC framing library. SchemaRegistry loads files from `schemas/ipc/` at startup.

**IPC channel assignments:**

| Channel | File                      | Peer                           |
| ------- | ------------------------- | ------------------------------ |
| 0       | `control.schema.json`     | all peers (handshake)          |
| 1       | `command.schema.json`     | all peers (generic commands)   |
| 3       | `telemetry.schema.json`   | all peers (metrics, audit)     |
| 4       | `error.schema.json`       | all peers (out-of-band errors) |
| 256     | `channel_256.schema.json` | mlvoy (email bridge)           |
| 257     | `channel_257.schema.json` | fulminar (HTTP proxy)          |
| 258     | `channel_258.schema.json` | lanyte-admin (admin UI)        |
| 259     | `channel_259.schema.json` | skill executor I/O             |

**Schema naming**: user channels MUST be `channel_NNN.schema.json`. Do not use logical names — ipcprims will silently ignore them. See ADR-0006.

**Human supervisor**: Dave Thompson (@3leapsdave), owner of 3leaps, fulmenhq, and lanytehq orgs.

---

## Local Machine Context

If you are a core maintainer on a dev machine, check for `AGENTS.local.md` in this directory (gitignored). It contains local paths and private repo references.

Typical sibling repos on a dev machine:

```
~/dev/lanytehq/lanyte-crucible/   ← you are here (or a repo-seed)
~/dev/lanytehq/lanyte/             ← Rust workspace (main core)
~/dev/3leaps/ipcprims/             ← IPC library (v0.1.3)
~/dev/fulmenhq/mlvoy/              ← email bridge peer
~/dev/fulmenhq/fulminar/           ← HTTP proxy peer
```

---

## Rules for This Repo

### Schema changes

- Schema changes are **breaking by default** — all peers that use the channel must be updated simultaneously.
- Add new message types via `oneOf` — never remove or rename existing ones without an ADR and a migration plan.
- Run schema validation before committing: `~/dev/3leaps/ipcprims/target/debug/ipcprims echo /tmp/test.sock --validate schemas/ipc/`
- All schema objects must have `"additionalProperties": false` (ipcprims strict mode enforces this; be explicit anyway).

### ADR process

- New ADR: copy `docs/decisions/adr-template.md`, number sequentially, add to `docs/decisions/index.md`.
- Status lifecycle: `Proposed` → `Accepted` → (`Deprecated` | `Superseded by ADR-XXXX`).
- When in doubt, write a `Proposed` ADR and escalate to @3leapsdave.

### Role files

- Role files validate against `schemas/agentic/v0/role-prompt.schema.json`.
- New Lanyte-specific roles go here. Generic roles are sourced from `3leaps/crucible`.
- Do not modify roles without discussion — they govern how all AI agents behave on this platform.

### What requires escalation

- Any schema change that affects a channel already in use by a deployed peer.
- Adding a new IPC channel (requires a channel number assignment decision).
- Adding a capability to the taxonomy (20-cap limit in v1; each addition is a policy decision).
- Status change from Proposed to Accepted on any ADR.

---

## Quick Reference

```bash
# Validate all IPC schemas
~/dev/3leaps/ipcprims/target/debug/ipcprims echo /tmp/lanyte-test.sock \
  --validate schemas/ipc/

# Check schema JSON is valid
for f in schemas/ipc/*.schema.json; do python3 -m json.tool "$f" > /dev/null && echo "OK $f" || echo "FAIL $f"; done
```
