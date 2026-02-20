# REPOSITORY SAFETY PROTOCOLS

This repo is intended to be **public SSOT**. Treat it as an external-facing artifact.

## Never Commit

- secrets (API keys, tokens, credentials)
- private hostnames/IPs/internal URLs
- vendor account identifiers
- contact directories or escalation targets

## Contracts First

- Schemas and specs land before implementations.
- Prefer strict schemas (`additionalProperties: false`) unless explicitly justified.

## Decisions

Decision records live in `docs/decisions/`:
- `ADR-####-...` for architecture decisions
- `SDR-####-...` for standards decisions
- `DDR-####-...` for deep design decisions

If unsure, start with an ADR.

