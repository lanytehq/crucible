---
title: Core Developer Warm-Up Guide
description: Read this at the start of every development session on the Lanyte platform. Applies to devlead, devrev, and secrev roles.
---

# Core Developer Warm-Up Guide

**Read this first — every session.** It takes 2 minutes and prevents costly mistakes.

This guide is for agents and humans doing core development on the Lanyte platform
(`lanytehq` org). It is the single "go here first" document regardless of which repo
or workstream you are working in.

---

## 1. Platform in One Paragraph

Lanyte is a **secure, self-hosted autonomous AI agent platform**. The architecture is:
- **`lanyte` (Rust core)** is the Trusted Computing Base (TCB) — the only fully trusted component. It runs on an immutable SquashFS root. All IPC is framed and schema-validated at the boundary.
- **Peer services** (`mlvoy`, `fulminar`, admin) connect via `ipcprims` Unix sockets. Each peer is on a numbered channel with a JSON Schema 2020-12 contract.
- **WASM skills** run inside the executor sandbox inside core. They are isolated, capability-granted, fresh-instance per execution.
- **You** are a supervised AI agent. Dave Thompson (@3leapsdave) is the human maintainer and has final authority.

---

## 2. Key Paths (on this machine)

```
~/dev/lanytehq/
  lanyte-crucible/          ← SSOT: schemas, ADRs, roles (you are here or close)
  lanyte/                   ← Rust workspace (TCB) — CRT-001 creates this
  lanyte-productbook-internal/ ← Sprint boards, gate status
  lanyte-*/                 ← other platform repos

~/dev/3leaps/ipcprims/      ← IPC library v0.1.3 (MSRV 1.85.0)
~/dev/fulmenhq/mlvoy/       ← email bridge peer (channel 256)
~/dev/fulmenhq/fulminar/    ← HTTP proxy peer (channel 257)
```

If you don't see `lanyte/`, it hasn't been created yet — that's CRT-001.
Check `AGENTS.local.md` in your working repo for any machine-specific path overrides.

---

## 3. IPC Channel Quick Reference

| Channel | Schema file | Peer |
|---------|-------------|------|
| 0 | `control.schema.json` | all peers — handshake |
| 1 | `command.schema.json` | all peers — generic commands |
| 3 | `telemetry.schema.json` | all peers — metrics, audit |
| 4 | `error.schema.json` | all peers — out-of-band errors |
| 256 | `channel_256.schema.json` | mlvoy — email |
| 257 | `channel_257.schema.json` | fulminar — HTTP proxy |
| 258 | `channel_258.schema.json` | lanyte-admin |
| 259 | `channel_259.schema.json` | skill executor I/O |

Schema files live in: `~/dev/lanytehq/lanyte-crucible/schemas/ipc/`

---

## 4. Current Sprint State

Check before touching any task:

```
~/dev/lanytehq/lanyte-productbook-internal/content/projmgmt/projmgmt/index.md
  → Gate status (which gates are cleared)

~/dev/lanytehq/lanyte-productbook-internal/content/projmgmt/core-runtime/index.md
  → CRT task board (active for Gate 3)

~/dev/lanytehq/lanyte-productbook-internal/content/projmgmt/standards/index.md
  → STD task board (STD-001/002/003 done; STD-004/005/006 ready)
```

**Current gate status (as of 2026-02-22):**
- G1 ✅ ipcprims v0.1.3 available
- G2 ✅ IPC schemas — all 8 written and merged to lanyte-crucible main
- G3 🟡 Ready — lanyte Rust workspace + gateway (CRT-001 through CRT-006)
- G4 🔴 Blocked on G3 — executor runs echo skill
- G5 🔴 Blocked on G4 — stack alive

---

## 5. Non-Negotiable Rules

These are never bent. If in doubt, escalate to @3leapsdave.

**Schemas before code.**
Do not implement a new IPC message type without its schema in
`lanyte-crucible/schemas/ipc/` first. This is not a suggestion.

**Gateway is a router. Not a business logic host.**
`lanyte-gateway` wraps ipcprims. It validates, routes, and hands off.
No decisions, no state, no side effects in the gateway.

**PR scheme.**
No direct pushes to main in any `lanytehq` repo.
Create a branch, push, open a PR. Use rebase-merge for multi-commit branches.

**TCB boundary.**
Only `lanyte` (core) is trusted. Peers are not trusted.
Peer input is always validated at the IPC boundary before acting on it.

**Attribution.**
Every agent-generated commit must include:
```
Co-Authored-By: <Model Name> <noreply@lanytehq.dev>
Role: <your-role-slug>
Committer-of-Record: @3leapsdave
```
Example: `Co-Authored-By: Claude Sonnet 4.6 <noreply@lanytehq.dev>`

Every agent-opened PR must include this footer in the body:
```
---
Drafted-By: <Model Name> (<Agentic Tool>)
Role: <your-role-slug>
PR-of-Record: @3leapsdave
```
Example: `Drafted-By: Claude Sonnet 4.6 (Claude Code)`

**MSRV 1.85.0.**
All lanyte crates target stable Rust 1.85.0. No nightly features.
`unsafe` requires secrev review before merge.

---

## 6. Dev Environment Check

Run this before starting if you haven't worked in this repo recently:

```bash
# Rust toolchain
rustc --version              # expect 1.85.0 or later

# ipcprims CLI (schema validation) — public crate, install once
ipcprims --version           # expect 0.1.2 (latest released tag)
# If missing:
cargo install ipcprims                            # from crates.io if published
# Or from git tag (always works):
cargo install --git https://github.com/3leaps/ipcprims --tag v0.1.2 ipcprims
# Or from local source if cloned:
cargo install --path ~/dev/3leaps/ipcprims

# Validate IPC schemas (takes ~2s, catches JSON errors before commit)
ipcprims echo /tmp/lanyte-test.sock \
  --validate ~/dev/lanytehq/lanyte-crucible/schemas/ipc/
# Expect: "INFO listening on unix domain socket" with no errors, then Ctrl-C

# In lanyte/ workspace (once CRT-001 is done):
make check   # cargo fmt --check + cargo clippy -D warnings + cargo test + cargo deny
```

**ipcprims as a library dependency** (for `lanyte-gateway` and other crates — already in the workspace Cargo.toml spec):
```toml
# Pinned to latest release tag. Update deliberately — wire format frozen for 0.x.
ipcprims = { version = "0.1.2", features = ["schema", "peer"] }

# Local source override during active ipcprims development (workspace Cargo.toml):
# [patch.crates-io]
# ipcprims = { path = "../../3leaps/ipcprims" }
# — or for git dependency if not yet on crates.io:
# ipcprims = { git = "https://github.com/3leaps/ipcprims", tag = "v0.1.2", features = ["schema", "peer"] }
```

**Version discipline**: local `VERSION` may read `0.1.3` (in-progress dev) but the last *tagged release* is `v0.1.2`. Pin to the tag, not the VERSION file.

---

## 7. Role-Specific Starting Points

### devlead
You are building. Start with the task board for your workstream (see §4).
Read the task spec before writing any code. Read the relevant ADRs.
The build order for CRT is: `lanyte-common` → `lanyte-telemetry` → `lanyte-gateway` → `lanyte-state` → `lanyte-llm` → `lanyte-executor` → `lanyte-orchestrator` → `main.rs`.

### devrev
You are reviewing. Read the PR diff, then the task it implements, then the relevant ADRs.
Check: does the implementation match the schema? Does the gateway stay dumb? Are there new dependencies that bypass `deny.toml`? Are tests present and meaningful?

### secrev
You are auditing. Your mandatory checklist:
- Any `unsafe` block → justify line by line
- IPC boundary enforcement → is schema validation actually called before any use of payload data?
- TCB boundary → does peer input ever reach core state without validation?
- Credential handling → no secrets in code, no secrets in logs, API key from config only
- New capabilities or capability tier changes → policy decision, escalate to @3leapsdave
- Gate token validation → single-use enforced? Expiry enforced?

---

## 8. Escalation

If you hit any of these, stop and notify @3leapsdave before proceeding:
- Adding a new IPC channel (number assignment is a policy decision)
- Adding a new capability to the taxonomy (20-cap limit in v1)
- Any change to the WASM ABI (break existing skills)
- Any change to the Skill ABI v1 spec in `docs/specs/`
- Force push, branch deletion, or any destructive git operation
- Credentials anywhere in the codebase
