# Mail policy contracts v0

This family defines the provider-neutral authorization seam for delegated mail
access: what a delegate may do with an account, what one requested operation
looks like to a policy evaluator, and what the evaluator decided. It does not
define a provider protocol, a transport, or message content.

## Artifacts

| Artifact                      | Purpose                                                            |
| ----------------------------- | ------------------------------------------------------------------ |
| `delegation.schema.json`      | Bounded mail authority from an account principal to a delegate     |
| `action-request.schema.json`  | Policy input for one requested operation (refs and digests)        |
| `policy-decision.schema.json` | Decision stage for one request, with reasons and approval bind     |
| `semantic-validation.md`      | Cross-value invariants JSON Schema cannot express                  |
| `fixtures/`                   | Conforming and negative examples, including request/decision pairs |

Run `make check-mail-v0` to validate every schema, fixture, and semantic
negative control.

## Relationship to the MAIL channel

The numbered MAIL channel (`schemas/ipc/channel_256.schema.json`) is the wire
contract between core and the mail bridge peer. This family is the policy
contract both sides of any mail seam evaluate against:

- `delegation_id` shares the MAIL channel value space; this family defines the
  delegation that identifier refers to.
- The operation vocabulary is a superset of the MAIL channel operations
  (`search`, `read`, `list_folders`, `draft`, `send`, `archive`, `move`), adding
  `mark`, `trash`, `reply`, and `forward`.
- A `require_approval` decision binds approval to the exact draft digest. The
  single-use gate token of ADR-0007 is the approval credential presented at
  send time.

Extending the MAIL channel itself is deferred; see
[DDR-0001](../../../docs/decisions/ddr-0001-mail-policy-contract-family.md).

## Boundary

- Requests and decisions carry references, digests, derived facts, and reason
  codes. They never carry message bodies, subjects, or free text.
- Recipient `relationship` is derived by the enforcing peer. A delegate never
  supplies it.
- Signals come from deterministic **detectors** or model-backed **assessors**.
  A signal can only make a decision stricter. Signals are not classification
  dimensions in the sense of the classifiers framework.
- A decision records the decision stage only. The provider effect is evidenced
  separately and is never inferred from a decision.
- JSON Schema provides a structural validation surface. The behavioral rules in
  `semantic-validation.md` are enforced by producers and consumers, not by
  schema validation.

Status: `v0`. No compatibility promise; pin a commit for stability.
