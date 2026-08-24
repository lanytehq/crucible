# Gearwit interrupt contracts v0

This family defines the first public control-plane seam for equipping an
existing coding-agent seat with interrupt handling. It does not define agent
orchestration, prompt delivery, work scheduling, or a generic multimodal
waiter.

## Artifacts

| Artifact                        | Purpose                                     |
| ------------------------------- | ------------------------------------------- |
| `arm-request.schema.json`       | Seat intent, trigger condition, and route   |
| `arm-record.schema.json`        | Control-plane admission and coverage window |
| `ring-request.schema.json`      | Bounded external signal for an admitted arm |
| `waiter-link.schema.json`       | Local daemon-to-attached-waiter protocol    |
| `handled-cursor.schema.json`    | Seat ACK of a delivered prefix cursor       |
| `lifecycle-receipt.schema.json` | One independently evidenced lifecycle fact  |
| `semantic-validation.md`        | Cross-value and evidence-source invariants  |
| `fixtures/`                     | Conforming and negative contract examples   |

Run `make check-gearwit-interrupt-v0` to validate every schema, fixture, and
semantic negative control.

## Boundary

An arm names a condition and one explicit return route. The first provider
condition is a Mattermost channel wait implemented through Chanvoy. The
contract copies only the provider-neutral values Gearwit needs; Chanvoy's own
daemon RPC remains authoritative for provider wait ownership and seam
behavior.

A ring is an external signal reference, not a prompt. It never carries raw
provider bodies, terminal content, controller credentials, or an executable
command.

A waiter link is a local, provider-neutral delivery seam. It admits only
harness-owned foreground or background-tool return routes. A delivery carries
the bounded event set drained by the provider adapter; it is untrusted event
data, not prompt or command text. Operator notification does not require a
waiter link. The five waiter-link messages do not record a handled cursor.

A handled-cursor acknowledgement is a separate contract. It authenticates the
live arm, generation, and seat, names the stable `signal_id` (not a retry
`delivery_id`), and names a cursor that is a member of the exact delivered
ordered batch. A valid ACK may advance the handled cursor and permit coverage
to re-arm from that cursor. It must not claim `turn_started`.

A lifecycle receipt proves exactly one fact. Neighboring phases remain
unknown until they receive their own evidence. In particular,
`waiter_completed` never proves `turn_started`, and a first match never proves
that later events were drained or handled.
