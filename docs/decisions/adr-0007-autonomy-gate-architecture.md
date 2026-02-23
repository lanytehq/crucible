---
title: ADR-0007 Autonomy Gate Architecture
description: How high-risk autonomous actions are gated on human approval via the ADMIN channel
---

# ADR-0007: Autonomy Gate Architecture

Status: Accepted

## Context

Lanyte's orchestrator operates with varying degrees of autonomy. Certain actions (sending email, making mutating HTTP calls, spending money) must require explicit human approval before execution. The design challenge is: where does the gate live, and how does an approval travel from the human operator to the peer service that will perform the action?

## Decision

The autonomy gate is implemented as a request/approval/token flow across two IPC channels:

1. **Core signals a pending gate** — when the orchestrator determines an action requires human approval, it creates a gate record (gate_id, action, skill_id, summary) and blocks execution.
2. **Human operator sees the queue** — via `admin_gate_status_request` on channel 258 (ADMIN).
3. **Human approves or denies** — via `admin_gate_approve_request` or `admin_gate_deny_request` on channel 258.
4. **Core issues a gate_token** — on approval, core generates an opaque short-lived token and returns it to the admin peer via `admin_gate_approve_response.gate_token`.
5. **Operator passes token to the action** — the gate_token is included in the destructive action's request on its own channel (e.g. `mail_send_request.gate_token` on channel 256).
6. **Core validates the token** — before dispatching to mlvoy, core checks the token is valid and has not been consumed. Tokens are single-use.

### What requires a gate token

Any action that cannot be undone or that touches external systems with real-world consequences:

- `mail_send_request` — sends email to external recipients
- Future: HTTP POST/PUT/DELETE to external services beyond read-only
- Future: skill installation from unsigned packages

The schema enforces this at the IPC boundary: `mail_send_request` has `gate_token` as a required field.

### What does not require a gate token

Read-only operations: `mail_search_request`, `mail_read_request`, `http_get_request`, skill list/describe, all status queries.

## Options Considered

### Option A: Separate gate service (peer on its own channel)

A dedicated `lanyte-gate` process with its own IPC channel handles all approval flows.

- Pros: Clean separation of concerns; gate logic is isolated.
- Cons: Extra process, extra channel, extra IPC round-trip; gate must be up for any guarded action to proceed; adds complexity before v1 is proven.

### Option B: Gate inline in each channel handler (chosen approach, simplified)

Gate enforcement lives in the orchestrator. The ADMIN channel carries the approve/deny UI API. Core mints and validates tokens internally.

- Pros: No new process; gate state lives in the same process that enforces it; schema-enforced at the IPC level.
- Cons: Orchestrator owns more responsibility; gate state is not externally queryable without ADMIN channel.

## Consequences

- Positive: Gate state is internal to core — the TCB — which is the most trusted component.
- Positive: gate_token requirement is visible in the IPC schema; peer implementers cannot accidentally omit it.
- Positive: Single-use tokens prevent replay attacks.
- Negative: If the admin UI peer is down, gate approvals cannot be issued. Core should expose a CLI fallback for this case.
- Risk: Token lifetime management (expiry, revocation) must be implemented carefully. A pending gate with a long-lived token is a latent risk if the approval context changes before the token is used.
