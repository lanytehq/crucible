---
title: "Agent Identity and Session Attestation — Design Overview"
description: Overview of identity, attribution, and session attestation for the Lanyte agent platform. For 3leaps galaxy arch team discussion.
status: draft
---

# Agent Identity and Session Attestation

**Audience**: 3leaps galaxy architecture team
**Status**: Draft — decisions in progress, feedback welcome
**Date**: 2026-02-28

---

## The Problem

Lanyte is a platform where multiple actors — humans, supervised AI models, and (future)
autonomous agents — perform work in role-based sessions. Every action produces artifacts:
state checkpoints, commits, chat messages, Mattermost posts. We need to answer three
questions about each artifact:

1. **Attribution**: Who produced this? (Best-effort, may be unreliable)
2. **Provenance**: Can we verify the attribution? (Assurance level)
3. **Authorization**: Was the actor permitted to do this? (Capability scope)

Today we have attribution (freeform strings) with zero provenance assurance. Models
routinely misidentify themselves (e.g., Kimi 2.5 reporting as Claude Sonnet). Without
provenance, a malicious actor could impersonate any role on any communication channel.

## Core Principle

From the Lanyte premise: **the scope and freedom of action for any entity is based on trust
earned and assessment of capability + intent.** Our job is to create an environment that
increases confidence in that assessment. Identity and attestation are the foundation.

## Three Actor Types

| Actor type           | Example                        | Identity persistence           | Trust anchor                      |
| -------------------- | ------------------------------ | ------------------------------ | --------------------------------- |
| **Human**            | Dave (@3leapsdave)             | Persistent — known person      | Physical access, credentials, MFA |
| **Supervised agent** | Claude Opus 4.6 in Claude Code | Ephemeral — session-scoped     | The human supervisor              |
| **Autonomous agent** | (future) persistent process    | Persistent — registered entity | Its own cryptographic identity    |

### Key insight: role is not identity

A **role** (cxotech, devlead, devrev) is a function being performed. Roles have state
chains that persist across actors — whoever assumes the role picks up where the last
actor left off.

An **identity** is an addressable entity. Humans and autonomous agents have persistent
identities. Supervised agent sessions are ephemeral — the model in a Claude Code session
has no persistent identity beyond the session.

This separation means:

- Role state chains are keyed by `(role, scope)` — identity-free
- Identity is captured as attribution metadata, with assurance proportional to attestation
- The two concerns can be developed independently

## Attestation Model

### The problem with self-reported attribution

```json
{
  "authored_by": {
    "actor_type": "supervised_agent",
    "model": "claude-opus-4-6",
    "tool": "claude-code",
    "supervisor": "3leapsdave"
  }
}
```

Every field here is self-reported by the model. Nothing prevents a compromised or
malicious model from writing `"supervisor": "3leapsdave"` when Dave isn't supervising,
or `"model": "claude-opus-4-6"` when it's actually a different model.

### Session attestation: the "one more step"

Before starting a supervised session, the human authenticates to a local authority and
receives a session token:

```
$ seclusor run -- lanyte-attest begin --role cxotech --scope lanytehq
Enter passphrase: ********
Session attested. Token valid for 8 hours.
LANYTE_SESSION_TOKEN injected.
```

Under the hood:

1. A signing key lives in [seclusor](../../README.md#seclusor) (age-encrypted at rest)
2. `lanyte-attest begin` mints a JWT: `{ role, scope, supervisor, iat, exp }`
3. JWT injected as env var via seclusor's `run` mechanism (not in shell history)
4. `stashvoy` reads the token, validates the signature, records it in `session_ref`

**What this proves**: Someone with the seclusor passphrase attested this session for
this role. Not foolproof (passphrase compromise = game over), but meaningful friction —
comparable to SSH key authentication.

**What this does NOT prove**: Which model is running, whether the model is behaving
correctly, whether the human is actually watching. Those are capability/intent
assessments, not identity.

### Tampering considerations

| Vector                           | Risk level            | v1 mitigation                        | Future mitigation                        |
| -------------------------------- | --------------------- | ------------------------------------ | ---------------------------------------- |
| Model reads env var, exfiltrates | Medium                | Short-lived JWT; human supervises    | Socket-based daemon (token never in env) |
| Token replay                     | Medium                | Context binding (session start hash) | Single-use nonces via attestation daemon |
| Signing key compromise           | High impact, low prob | seclusor passphrase; key rotation    | HSM, per-supervisor keys                 |

The strongest future architecture is an **ssh-agent pattern**: `lanyte-attest` runs as a
UDS daemon, `stashvoy` requests per-checkpoint attestations via socket, the token/key
never enters the process environment.

## Autonomous Agent Identity (ADR Candidate — Not Yet Designed)

When agents operate without per-action human supervision, the trust anchor changes. The
human attestation model breaks down. We need:

- **Cryptographic identity**: Agent owns a key pair. Public key is registered.
- **Tamper-evident registry**: Identity registrations cannot be silently altered.
  Blockchain is a candidate — immutable, decentralized, verifiable without contacting
  the issuing authority.
- **Capability grants**: What the agent is authorized to do, signed by an authority.
- **Revocation**: How to revoke a compromised agent identity.

This is the scope of a dedicated ADR. It is explicitly deferred from the current work
but will be addressed in the near term.

### Open questions for arch team

1. Should autonomous agent identities be org-scoped or global? Can `agent-rust` in
   lanytehq be the same entity as `agent-rust` in 3leaps?
2. Is blockchain the right trust anchor, or is a simpler PKI sufficient for our scale?
3. How do capability grants compose? If an agent has `commit` capability in one project,
   does that imply anything about other projects?
4. What's the revocation model? CRL-style, OCSP-style, or on-chain revocation?

## Implementation Roadmap

| Artifact                                                             | Scope                                   | Status                 |
| -------------------------------------------------------------------- | --------------------------------------- | ---------------------- |
| `agent-state.schema.json` — structured `authored_by` + `session_ref` | Schema                                  | In progress (crucible) |
| CRT-011 — `stashvoy` agent state CLI                                 | Role state with attribution             | Brief ready            |
| CRT-012 — `lanyte-attest` session attestation                        | JWT minting, seclusor integration       | Brief in progress      |
| ADR — Agent identity model                                           | Supervised + autonomous identity design | Draft pending          |
| ADR — Autonomous agent trust anchors                                 | Blockchain/PKI for persistent agents    | Not started            |

## Background References

These are relative to a lanytehq dev machine. Access may require org membership.

- **Agent state schema**: `lanyte-crucible/schemas/agentic/v0/agent-state.schema.json`
- **ADR-0009** (memory store): `lanyte-crucible/docs/decisions/adr-0009-*.md`
- **ADR-0010** (LLM backend trait): `lanyte-crucible/docs/decisions/adr-0010-*.md`
- **CRT-011 brief** (stashvoy): `lanyte-productbook-internal/content/projmgmt/core-runtime/CRT-011-lanyte-ctx.md`
- **Agent coordination spec**: `lanyte-crucible/docs/specs/agent-coordination-bootstrap.md`
- **seclusor** (secrets manager): `~/dev/3leaps/seclusor/` — age-encrypted secrets, env var injection
- **Lanyte premise**: Agents operate with freedom proportional to earned trust and assessed
  capability + intent. The platform provides assurance to increase this trust. See
  `lanyte-productbook/` for the public framing (in progress).
