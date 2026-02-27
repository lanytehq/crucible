---
title: Decisions
description: Architecture decision records (ADRs)
---

# Decision Records

Decisions are recorded as ADRs when they are hard to reverse or when multiple viable options exist.

## ADR Index

| ID       | Decision                                                                   | Status   |
| -------- | -------------------------------------------------------------------------- | -------- |
| ADR-0001 | Secrets placement (LLM keys in core vs peer service)                       | Proposed |
| ADR-0002 | Default proxy (squid vs fulminar)                                          | Proposed |
| ADR-0003 | Forge language (Go) and bindings strategy                                  | Proposed |
| ADR-0004 | Repo layout for kitsites                                                   | Proposed |
| ADR-0005 | GitHub governance and templates                                            | Proposed |
| ADR-0006 | IPC schema design patterns (naming, bidirectional union, strict mode)      | Accepted |
| ADR-0007 | Autonomy gate architecture (gate_token flow via ADMIN channel)             | Accepted |
| ADR-0008 | Audit event integrity via wire-level hash chain                            | Accepted |
| ADR-0009 | Agent memory store v1 strategy (SQLite + app-enforced INSERT-only)         | Accepted |
| ADR-0010 | LLM adapter design (direct-to-frontier-model, no abstraction intermediary) | Accepted + Addendum |
| ADR-0011 | Provenance and blockchain strategy (Sigstore v1, blockchain Sprint 5+)     | Accepted |
