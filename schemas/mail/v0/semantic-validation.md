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
   make a send-class decision stricter than its grant. Neither admits `allow`.
6. A delegation with any `allow` or `require_approval` grant covering a
   send-class operation carries `recipients`, `untrusted_content`, and
   `approval`. A delegation whose send-class grants are all `deny` needs none of
   them. **(gate, structurally)**
7. `limits` is optional in v0. Without it the evaluator applies no rate cap;
   deployments that need one set it explicitly.
8. A delegation never carries credentials. The enforcing peer resolves
   `account_ref` to credentials it holds; the delegate never sees them.

## Action request rules

1. A send-class request carries `content.draft_digest` and at least one
   recipient. **(gate)**
2. `draft_digest` is SHA-256 over the canonical draft projection: recipients,
   headers, bodies, and attachment digests. Any change to the draft changes
   the digest.
3. Object references (`message_refs`, `draft_ref`, `thread_ref`) are opaque
   tokens and attachment `content_type` is a bare `type/subtype`. Addresses
   appear only in `recipients.*.address`. **(gate, structurally)** The token
   pattern rejects whitespace and punctuation-bearing text; it cannot prove a
   single-word token is not content, so producers mint references, never copy
   message fields into them.
4. `relationship` and `session.taint` are derived by the enforcing peer from
   its own state. Values asserted by the delegate are ignored.
5. `taint: unknown` is evaluated as `tainted`.
6. A session becomes `tainted` when message content from a sender outside
   `untrusted_content.trusted_senders` has been returned to the delegate in
   that session. Taint does not decay within a session.
7. `request_id` is the idempotency key. Reuse with a different canonical
   request is a hard conflict.

## Decision rules

1. `decision` is never weaker than `baseline_decision` (order:
   `allow` < `require_approval` < `deny`). **(gate)**
2. Signals raise, never lower. The decision records the signal outcomes it
   considered in `signals`. These outcomes require at least
   `require_approval`: **(gate)**

   | Class  | Escalating outcomes        | Non-escalating              |
   | ------ | -------------------------- | --------------------------- |
   | send   | `flag`, `abstain`, `error` | `clear`                     |
   | mutate | `flag`                     | `clear`, `abstain`, `error` |
   | read   | none                       | all                         |

   On read-class operations a `flag` annotates returned content for the
   delegate and may raise session taint; it does not change the decision.

3. A decision stricter than `baseline_decision` names at least one `signal`
   reason and at least one escalating signal outcome. Only signals move a
   decision above its baseline. **(gate)**
4. An `approval` binding is present exactly when `decision` is
   `require_approval`, and `approval.expires_at` is later than `decided_at`.
   **(gate)**
5. Approval is bound to `approval.draft_digest`. A gate token issued for a
   decision is single-use and valid only for a send whose current draft digest
   equals that value.
   `approval.expires_at` is no later than `decided_at + approval.token_ttl_secs`
   and no later than the delegation's `expires_at`. These bounds cross records
   and are enforced by the evaluator, not by this family's gate.
6. `reasons` are machine codes, never free text, addresses, or content.
   **(gate, structurally)**
7. An evaluator that cannot reach a decision yields `deny` for send-class and
   mutate-class operations.
8. When `chain` is present, `prev_hash` is SHA-256 of the canonical JSON of the
   previous decision record from the same producer (ADR-0008 form); the first
   record uses 64 zeros.

## Request and decision pair rules

A decision is bound to the request it decided. Given both records, a verifier
checks: **(gate, pair fixtures)**

1. `request_id`, `delegation_id`, and `op` are equal in both records.
2. `input_digest` equals the canonical digest of the request.
3. The decision `signals` equal the request `signals` projected to `source`,
   `id`, and `outcome`, in the same order. A decision cannot drop, add, or
   reorder a signal, so an empty list is valid only when the request carried
   none. `signals` is required on every decision.
4. When present, `approval.draft_digest` equals the request
   `content.draft_digest`.

## Not covered by the gate

- A decision checked without its request: the pair rules need both records.
  Consumers that retain decisions retain or can retrieve the request by
  `input_digest`.
- Single use of the gate token: enforced at send time by the token issuer.
- Peer derivation of `relationship` and `taint`: an evaluation rule. The
  fixtures prove only that the value sets are closed.
- Blind-copy recipients appear on the action request by design so policy can
  evaluate them; decision records carry no addresses.

## Canonical JSON

Digests use the JSON encoding with keys sorted lexicographically, no
insignificant whitespace, and UTF-8 output.
