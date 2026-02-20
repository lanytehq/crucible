---
title: Public Docs Redaction Policy
status: draft
version: 0.1.0
---

# Public Docs Redaction Policy

This repository is intended to be public. The public runbook/productbook MUST avoid operationally sensitive details that turn into attacker enablement.

Do not publish:
- hostnames, IPs, internal URLs
- vendor account identifiers
- on-call contact directories
- exact production commands and scripts

Publish instead:
- contracts, schemas, invariants
- gates and acceptance criteria
- generic procedures without environment specifics

