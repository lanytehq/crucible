---
title: Schemas
description: Schema catalog (human-facing index)
---

# Schemas

Schemas are SSOT artifacts intended for **machine consumption**. The canonical files live in `schemas/`.

## IPC schemas

- `schemas/ipc/` — numbered Lanyte core-gateway channel contracts loaded by
  ipcprims. That loader does not recurse into `schemas/ipc/local/`.
- `schemas/ipc/local/` — Chanvoy runtime-control v1. Nine transport-selected
  roots, validated by `make check-chanvoy-runtime-control-v1`. Not a
  numbered channel. ADR-0018 remains Proposed.

## Common protocol schemas

- `schemas/common/chanvoy-daemon-rpc/v0/` — Chanvoy local daemon JSON-RPC
  method contracts: channel wait, process-held follow, named-DM and inbox
  wait and follow, mention filtering, and bounded coalescing. Not loaded
  by ipcprims.

## Mail policy schemas

- `schemas/mail/v0/` — provider-neutral delegation, action request, and
  policy decision. A decision is not a provider effect. The numbered MAIL
  channel is unchanged. DDR-0001 remains Proposed. Gate:
  `make check-mail-v0`.

## Agentic protocol schemas

- `schemas/agentic/v0/` — role-prompt, agent-state, ledger (v0).
- `schemas/agentic/v0.1/` — agent-state v0.1.
- `schemas/agentic/dispatch/v0/` — run envelope and harness profile.
- `schemas/agentic/mission/v0/` and `v0.1/` — mission family (lease, deadman, cancel).
- `schemas/agentic/gearwit/v0/` — Gearwit interrupt lifecycle and local
  daemon-to-waiter delivery contracts.
- `schemas/agentic/memory/v0/` — agent memory entries (a durable-record/v1
  profile), per-kind payload contracts, and the kind registry. Kinds are the
  `memory-kind` classifier dimension in `config/classifiers/`. DDR-0002
  remains Proposed. Gate: `make check-memory-v0`.

## Policy

Default stance for IPC and config schemas:

- Prefer `additionalProperties: false`
- Prefer explicit `required` fields
- Version schemas intentionally (no silent drift)
