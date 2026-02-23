---
title: ADR-0006 IPC Schema Design Patterns
description: Naming convention, bidirectional union design, and strict-mode rules for all IPC channel schemas
---

# ADR-0006: IPC Schema Design Patterns

Status: Accepted

## Context

ipcprims `SchemaRegistry::from_directory()` validates every frame at the IPC boundary using JSON Schema 2020-12. Before writing the first schemas we needed to establish patterns that all peer implementers and code generators must follow. Four constraints drove the design: ipcprims strict mode behaviour, the single-schema-per-channel requirement, the bidirectional nature of each channel, and the binary-data transport problem.

## Decision

### 1. File naming

User channels (256–259) use the numeric form required by ipcprims:

- `channel_256.schema.json` (MAIL)
- `channel_257.schema.json` (PROXY)
- `channel_258.schema.json` (ADMIN)
- `channel_259.schema.json` (SKILL_IO)

Built-in channels use their ipcprims name:

- `control.schema.json`, `command.schema.json`, `telemetry.schema.json`, `error.schema.json`

Logical names (`mail.schema.json`, `proxy.schema.json`) are NOT used. ipcprims will silently ignore files it cannot map.

### 2. Bidirectional discriminated union

Each schema covers both directions (core→peer and peer→core) using `oneOf` with a `type: const` discriminator. Every message object carries `"type": { "const": "<message_type_name>" }` as its first required property.

This avoids per-direction schema files and keeps the channel contract self-contained.

### 3. Strict mode and open objects

ipcprims strict mode recursively adds `"additionalProperties": false` to any JSON Schema object that does not already have that key. This is the desired default (prevents data exfiltration via extra fields).

Exceptions — where an object must remain open — require explicit `"additionalProperties": true` in the schema. Current cases:

- `skill_invoke_request.input` and `skill_invoke_response.output` (skill-specific, validated at executor boundary)
- `command.args` and `command.result` (open command channel, handler-specific)
- `telemetry.audit_event.details` (action-specific fields)

Objects in `$defs` that are referenced via `$ref` also receive strict mode treatment; ensure they are correctly typed.

### 4. Binary data convention

Binary payloads are base64-encoded strings with a `_b64` suffix on the field name (e.g. `body_b64`, `package_b64`). This avoids binary-in-JSON encoding ambiguity and makes size limits expressible as `maxLength`.

### 5. Request correlation

All request/response pairs use a `request_id` field typed as UUID v4:

```
pattern: ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$
```

Every channel schema defines `request_id` in its `$defs` section for DRY reference.

## Consequences

- Positive: A single schema file per channel is the complete source of truth for that channel's contract. Peer implementers need only read one file.
- Positive: Strict mode catches field additions in both implementation and tests at the IPC boundary, not at runtime deep in business logic.
- Negative: Adding a new message type to a channel requires editing the canonical schema and versioning the change; there is no additive-only path.
- Risk: Open objects (`additionalProperties: true`) bypass schema enforcement at the IPC boundary. Each exception must be explicitly justified and documented.
