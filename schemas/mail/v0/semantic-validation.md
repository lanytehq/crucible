# Mail policy v0 semantic validation

JSON Schema validates individual shapes. Producers and consumers must also
enforce these rules before acting on a delegation, request, or decision. Rules
marked **(gate)** are exercised by negative fixtures in `make check-mail-v0`.

## Operation classes

Consumers derive the class from `op`; it is never transmitted.

| Class  | Operations                                  |
| ------ | ------------------------------------------- |
| read   | `search`, `read`, `list_folders`            |
| mutate | `draft`, `mark`, `move`, `archive`, `trash` |
| send   | `send`, `reply`, `forward`                  |

## Delegation rules

1. `expires_at` and `revoked_at`, when non-null, are later than `valid_from`.
   **(gate)**
2. Evaluation outside `[valid_from, expires_at)` or after `revoked_at` is a
   denial.
3. Absence of a matching `allow` or `require_approval` grant is a denial.
4. When grants overlap, the strictest effect wins: `deny` over
   `require_approval` over `allow`.
5. `recipients.new_external` and `untrusted_content.tainted_send` can only
   make a send-class decision stricter than its grant.
6. A delegation never carries credentials. The enforcing peer resolves
   `account_ref` to credentials it holds; the delegate never sees them.

## Action request rules

1. A send-class request carries `content.draft_digest` and at least one
   recipient. **(gate)**
2. `draft_digest` is SHA-256 over the canonical draft projection: recipients,
   headers, bodies, and attachment digests. Any change to the draft changes
   the digest.
3. `relationship` and `session.taint` are derived by the enforcing peer from
   its own state. Values asserted by the delegate are ignored.
4. `taint: unknown` is evaluated as `tainted`.
5. A session becomes `tainted` when message content from a sender outside
   `untrusted_content.trusted_senders` has been returned to the delegate in
   that session. Taint does not decay within a session.
6. `request_id` is the idempotency key. Reuse with a different canonical
   request is a hard conflict.

## Decision rules

1. `decision` is never weaker than `baseline_decision` (order:
   `allow` < `require_approval` < `deny`). **(gate)**
2. Signals raise, never lower. A send-class request with any signal outcome of
   `abstain` or `error` is decided at least `require_approval`.
3. An `approval` binding is present exactly when `decision` is
   `require_approval`, and `approval.expires_at` is later than `decided_at`.
   **(gate)**
4. Approval is bound to `approval.draft_digest`. A gate token issued for a
   decision is single-use and valid only for a send whose current draft digest
   equals that value.
5. `reasons` are machine codes, never free text, addresses, or content.
   **(gate, structurally)**
6. An evaluator that cannot reach a decision yields `deny` for send-class and
   mutate-class operations.
7. When `chain` is present, `prev_hash` is SHA-256 of the canonical JSON of the
   previous decision record from the same producer (ADR-0008 form); the first
   record uses 64 zeros.

## Canonical JSON

Digests use the JSON encoding with keys sorted lexicographically, no
insignificant whitespace, and UTF-8 output.
