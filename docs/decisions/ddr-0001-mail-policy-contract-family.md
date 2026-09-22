---
title: DDR-0001 Mail Policy Contract Family
description: Provider-neutral delegation, action-request, and decision contracts for delegated mail access
---

# DDR-0001: Mail Policy Contract Family

Status: Proposed

## Context

The MAIL channel (`schemas/ipc/channel_256.schema.json`) defines the wire
between core and the mail bridge peer. Every request carries a
`delegation_id`, and `mail_send_request` requires a draft identifier and the
single-use gate token of ADR-0007. The channel does not define:

- what a delegation contains;
- the input a policy evaluator reads for one requested operation;
- the shape of an authorization decision and its evidence.

Generic mail providers (JMAP, IMAP/SMTP) offer no server-side delegate access
control. An account credential is all-or-nothing, so bounded authority must be
evaluated by whichever component holds the credential. The mail bridge peer
and agent-facing mail connectors both need that evaluation. Without a shared
contract each would define its own delegation and decision shapes.

An agent with mail access also combines untrusted input (inbound messages),
private data (the mailbox), and external communication (send). Policy therefore
needs session-level facts, such as whether untrusted content has been read,
in addition to per-operation grants.

## Options Considered

### Option A: Extend the MAIL channel now

- Pros: one schema; the wire carries policy fields directly.
- Cons: the Schema Bump Policy bar is not met. No peer implements the channel
  yet, so there is no consumer evidence, and wire and policy concerns would be
  coupled.

### Option B: Each implementation defines its own policy shapes

- Pros: no coordination.
- Cons: guaranteed drift between the bridge peer and connectors, and no common
  decision evidence.

### Option C: New `mail/v0` policy family; MAIL channel unchanged

- Pros: defines what `delegation_id` refers to; one evaluator input and
  decision shape for every mail seam; `v0` leaves room to learn.
- Cons: a second schema family to keep aligned with the channel.

## Decision

Adopt Option C. Add `schemas/mail/v0/` with three artifacts:

1. **Delegation** — grants of operations to a delegate over an account, with
   recipient rules, untrusted-content rules, rate limits, approval token
   lifetime, and a validity window. Absence of an allow is a denial; the
   strictest overlapping effect wins. A grant that permits sending requires
   recipient, untrusted-content, and approval rules. No credentials.
2. **Action request** — the evaluator input for one operation: operation,
   session taint, targets, thread origin, recipients with peer-derived
   relationship, draft digest, and detector or assessor signals. References and
   digests only; no bodies or subjects.
3. **Policy decision** — baseline decision (delegation and facts), final
   decision (after signals), the signal outcomes considered, reason codes, evaluator identity and policy
   digest, an input digest, an approval binding to the draft digest when
   approval is required, and optional ADR-0008 hash-chain linkage.

Design choices:

- **Operation vocabulary** is a superset of the MAIL channel operations, adding
  `mark`, `trash`, `reply`, and `forward`, so the family covers connector
  surfaces the channel does not yet carry.
- **Signals only escalate.** Recording both `baseline_decision` and `decision`
  makes the rule checkable from evidence: a record whose decision is weaker
  than its baseline is non-conforming, and a record that ignores an
  escalating signal outcome for its operation class is non-conforming. A
  decision's signals must equal its request's signals, and its approval digest
  must equal the request's draft digest, so an evaluator cannot omit a signal
  or approve a different draft without the pair failing verification.
- **Approval binds to content.** A `require_approval` decision names the draft
  digest. The ADR-0007 gate token is the credential presented at send time and
  is valid only for that digest.
- **Decision is one stage.** The decision record never asserts the provider
  effect; effects are evidenced separately.
- **Naming.** Deterministic checks are _detectors_, model-backed checks are
  _assessors_, and their outputs are _signals_. This avoids overloading the
  classification-dimension vocabulary.

MAIL channel extension (`mark`, `trash`, `reply`, `forward` messages, an
untrusted-content marker on read responses, and a decision reference on
responses) is deferred. It is proposed through the Schema Bump Policy once the
bridge peer implements the channel and provides consumer evidence.

## Consequences

- Positive: the bridge peer and mail connectors share one delegation and
  decision contract; `delegation_id` has a defined referent; approval and
  escalation rules are testable from records.
- Negative: two families (wire and policy) must stay aligned until the channel
  extension lands.
- Risks: `v0` shapes will change as the first evaluator ships. Consumers pin a
  commit and vendor SHA-pinned copies until promotion.
