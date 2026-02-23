---
title: Schemas
description: Schema catalog (human-facing index)
---

# Schemas

Schemas are SSOT artifacts intended for **machine consumption**. The canonical files live in `schemas/`.

## IPC Schemas

- `schemas/ipc/` (to be created)

## Policy

Default stance for IPC and config schemas:

- Prefer `additionalProperties: false`
- Prefer explicit `required` fields
- Version schemas intentionally (no silent drift)
