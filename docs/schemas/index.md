---
title: Schemas
description: Schema catalog (human-facing index)
---

# Schemas

Schemas are SSOT artifacts intended for **machine consumption**. The canonical files live in `schemas/`.

## IPC schemas

- `schemas/ipc/` — numbered Lanyte core-gateway channel contracts loaded by
  ipcprims.

## Common protocol schemas

- `schemas/common/chanvoy-daemon-rpc/v0/` — Chanvoy local daemon JSON-RPC
  method contracts, including the bounded multi-channel wait capability.

## Policy

Default stance for IPC and config schemas:

- Prefer `additionalProperties: false`
- Prefer explicit `required` fields
- Version schemas intentionally (no silent drift)
