---
title: Peer Service Contract
status: ratified
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
- Core MUST treat the peer identity established by CONTROL `hello` / `hello_ack` as authoritative
  for the lifetime of the connection.
- Core MUST reject frames received on channels not accepted for that peer connection during the
  handshake. Repeated protocol violations SHOULD result in disconnect.

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

For lanyte-reserved user channels in v1, each reserved channel is owned by at most one peer
process at a time.

## Schema Validation

- All peer messages MUST be schema-valid at the boundary.
- Schemas SHOULD be strict (`additionalProperties: false`) to prevent drift.
- Application-level recipient or target mistakes MUST fail as explicit request-correlated errors in
  the relevant channel contract; the gateway/core MUST NOT silently reroute a request to a
  different peer.

## Resource Limits And Backpressure

- Peers MUST respect the active `ipcprims` frame-size limit. With current runtime defaults this is
  `16 MiB` for regular peer traffic; handshake limits MAY be lower.
- Core/gateway MUST reject oversized or otherwise unprocessable frames loudly and deterministically.
- Peer IPC/event streams MUST use bounded buffering unless a peer-specific spec documents why
  unbounded buffering is safe for that producer profile.
- Any peer-facing overflow strategy (backpressure, drop, disconnect) MUST be documented by the
  relevant peer implementation or peer-specific spec.
- If core/gateway drops frames under sustained overload or policy enforcement, it MUST log the
  condition at `WARN` severity or above and SHOULD emit an ERROR-channel diagnostic when practical.
- For retry, backoff, timeout, and streaming reconnect policy on point-to-point paths, see
  ADR-0014.

## Health And Lifecycle

- Peers SHOULD respond to `PING` on CONTROL within the configured deadline.
- Peers MUST implement graceful shutdown when requested on CONTROL.

## Version Pinning

- Peers MUST declare the schema version they implement.
- Core MUST reject incompatible versions early and loudly.
