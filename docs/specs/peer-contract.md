---
title: Peer Service Contract
status: draft
version: 0.1.0
---

# Peer Service Contract

This document defines the **minimum contract** between `lanyte` core and any peer service (mlvoy, proxy, admin, mocks, fixtures).

Goals:
- Core progress MUST NOT be blocked on external peer readiness.
- Any peer MUST be swappable with a mock/fixture without changing core logic.

## Normative Language

The key words "MUST", "MUST NOT", "SHOULD", and "MAY" are to be interpreted as described in RFC 2119.

## Transport

- Peers MUST connect to the core gateway over a local IPC transport.
- Peers MUST negotiate channels via `ipcprims` CONTROL handshake.
- Peers MUST NOT send frames on channels not negotiated in the handshake.

## Channel Assignments (Bootstrap)

Built-in channels:
- `0` = CONTROL
- `1` = COMMAND
- `3` = TELEMETRY
- `4` = ERROR

Lanyte reserved channels:
- `256` = MAIL
- `257` = PROXY
- `258` = ADMIN
- `259` = SKILL_IO

## Schema Validation

- All peer messages MUST be schema-valid at the boundary.
- Schemas SHOULD be strict (`additionalProperties: false`) to prevent drift.

## Health And Lifecycle

- Peers SHOULD respond to `PING` on CONTROL within the configured deadline.
- Peers MUST implement graceful shutdown when requested on CONTROL.

## Version Pinning

- Peers MUST declare the schema version they implement.
- Core MUST reject incompatible versions early and loudly.

