# Lanyte Crucible

[![lifecycle](https://img.shields.io/badge/lifecycle-alpha-orange)](LIFECYCLE_PHASE)
[![version](https://img.shields.io/badge/version-0.0.1-blue)](VERSION)

Single source of truth (SSOT) for all contracts in the Lanyte platform.

Message types, agent role definitions, peer service specifications, and
architectural decisions live here before they are implemented anywhere else.
All other repos in the lanytehq ecosystem are downstream consumers of this
repository.

## Contents

### `schemas/ipc/`

JSON Schema 2020-12 files for all IPC channels at the core gateway boundary.
Loaded at runtime by [ipcprims](https://github.com/3leaps/ipcprims) for
schema-validated message framing.

| Channel | Schema file               | Peer                    |
| ------- | ------------------------- | ----------------------- |
| 0       | `control.schema.json`     | all peers — handshake   |
| 1       | `command.schema.json`     | all peers — commands    |
| 3       | `telemetry.schema.json`   | all peers — metrics     |
| 4       | `error.schema.json`       | all peers — errors      |
| 256     | `channel_256.schema.json` | mlvoy — email bridge    |
| 257     | `channel_257.schema.json` | fulminar — HTTP proxy   |
| 258     | `channel_258.schema.json` | lanyte-admin — admin UI |
| 259     | `channel_259.schema.json` | skill executor I/O      |
| 260     | `channel_260.schema.json` | chanvoy — CHAT bridge   |

### `schemas/agentic/`

Schemas for agent-side contracts:

- `v0/agent-state.schema.json` — structured checkpoint format for AI agent
  sessions. Embedded by [stashvoy](https://github.com/lanytehq/stashvoy).
- `v0/role-prompt.schema.json` — validation schema for agent role definitions
  in `config/agentic/roles/`.
- `dispatch/v0/` — dispatch runner supervision seam (run envelope, harness
  profile, semantic layer). See
  [`schemas/agentic/dispatch/v0/README.md`](schemas/agentic/dispatch/v0/README.md).
- `mission/v0/` — Wave 1/2 mission family (frozen). See
  [`schemas/agentic/mission/v0/README.md`](schemas/agentic/mission/v0/README.md).
- `mission/v0.1/` — Wave 3 lease, deadman, and `mission.cancel`. See
  [`schemas/agentic/mission/v0.1/README.md`](schemas/agentic/mission/v0.1/README.md).

Release-note and release-doc conventions for platform packages live under
[`docs/releases/`](docs/releases/) and the release-signing baseline in
[`docs/policies/release-signing-manual-baseline-policy.md`](docs/policies/release-signing-manual-baseline-policy.md).

### `schemas/common/`

Shared type definitions referenced across schemas:

- `v0/naming.schema.json` — naming conventions (role slugs, instance names,
  scope paths).
- `chanvoy-daemon-rpc/v0/` — versioned contracts for Chanvoy's local daemon
  JSON-RPC boundary. This is separate from the numbered core-gateway IPC
  channels.

### `config/agentic/roles/`

Lanyte product copies of agent role definitions, including Lanyte-only seats.
The **operating** catalog for estate seats is
[3leaps/crucible](https://github.com/3leaps/crucible). See the
[role catalog](config/agentic/roles/README.md) for the files in this tree.

### `docs/specs/`

Canonical specifications:

- [Peer Service Contract](docs/specs/peer-contract.md) — minimum contract
  between `lanyte` core and any peer service.
- [Agent Coordination Bootstrap](docs/specs/agent-coordination-bootstrap.md)
  — multi-agent session coordination conventions (messaging, context, roles).
- [Agent Identity Attestation](docs/specs/agent-identity-attestation.md)
  — session identity and attestation model.

### `docs/decisions/`

Architecture decision records (ADRs). Decisions are recorded when they are
hard to reverse or when multiple viable options exist. See the
[ADR index](docs/decisions/index.md) for the current list.

### `docs/guides/`

Developer and agent warm-up guides. Start with
[dev-warmup.md](docs/guides/dev-warmup.md) at the beginning of every session.

### `docs/policies/`

Security and operational policies for the platform.

## Schema validation

```sh
# Validate all IPC schemas via ipcprims
ipcprims echo /tmp/lanyte-test.sock --validate schemas/ipc/

# Check JSON validity
for f in schemas/ipc/*.schema.json; do
  python3 -m json.tool "$f" > /dev/null && echo "ok $f" || echo "FAIL $f"
done
```

## Local docs preview

```sh
make dev
# Serves at http://localhost:4012
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Schema-bump rules live in
[docs/policies/schema-bump-policy.md](docs/policies/schema-bump-policy.md).
Generic coding and commit style: [3leaps/crucible](https://github.com/3leaps/crucible).
Governance: [3leaps/oss-policies](https://github.com/3leaps/oss-policies).

## Agent sessions

Read [AGENTS.md](AGENTS.md) before starting any session in this repo. The
platform-wide warm-up sequence is in
[docs/guides/dev-warmup.md](docs/guides/dev-warmup.md).

## License

- **Schemas, documentation, data**: [CC0 1.0](LICENSE-CC0) — no rights reserved.
- **Code and scripts**: [MIT](LICENSE-MIT) OR [Apache-2.0](LICENSE-APACHE).
- **Trademark**: "Lanyte" and "LanyteHQ" are reserved marks of LanyteHQ. The
  CC0 license on content does not grant trademark rights.
