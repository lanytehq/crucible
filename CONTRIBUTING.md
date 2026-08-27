# Contributing to Lanyte Crucible

Thank you for contributing to Lanyte Crucible, the contract SSOT for the Lanyte
platform (`lanytehq/crucible`). This tree is documentation, JSON Schema, role
copies, and lightweight scripts — not a runtime.

## Related repositories

| Repository            | Purpose                                           |
| --------------------- | ------------------------------------------------- |
| `lanytehq/crucible`   | Lanyte platform contracts (this repo)             |
| `3leaps/crucible`     | Foundation coding, commit, SOP, and portable `v0` |
| `3leaps/oss-policies` | Governance, Code of Conduct, security, trademark  |

Generic coding and commit style live in
[3leaps/crucible](https://github.com/3leaps/crucible). Do not duplicate them
here.

## How to contribute

1. Open an issue describing the change, or a pull request if the change is
   small and already specified.
2. Create a branch from `main`.
3. Run `make check` before opening a PR.
4. Open a pull request. Default merge is **squash-merge**.

You do not need a private clone layout. A GitHub fork or clone of this
repository is enough.

## Schema changes

Governed by
[docs/policies/schema-bump-policy.md](docs/policies/schema-bump-policy.md).
Default: **do not bump** versioned schemas without a justified case.

- New IPC message types need a schema in `schemas/ipc/` **before**
  implementation in any consumer.
- Breaking changes need an ADR and lockstep consumer updates.
- Additions go through `oneOf`. Do not remove or rename types without an ADR
  and a migration plan.
- Validate: `ipcprims echo /tmp/test.sock --validate schemas/ipc/`

## ADRs

Copy `docs/decisions/adr-template.md`, number sequentially, and add a row to
`docs/decisions/index.md`. Status: `Proposed` → `Accepted` only with explicit
approval from @3leapsdave.

## Role files

Role YAML in `config/agentic/roles/` validates against
`schemas/agentic/v0/role-prompt.schema.json`. The **operating** catalog for
estate seats is `3leaps/crucible`. This tree keeps Lanyte product copies and
Lanyte-only seats. Do not rewrite roles without discussion.

## Attribution

Agent-generated commits and PRs must carry attribution per
[docs/policies/commit-attribution-policy.md](docs/policies/commit-attribution-policy.md)
and [AGENTS.md](AGENTS.md). Durable git surfaces stay short and public-safe.

## Quality

```sh
make check
```

Expect format (goneat), schema gates, and repository checks defined in the
Makefile.

## What we accept

- Contract, schema, policy, and documentation improvements for Lanyte
- Fixtures and validation scripts that keep those contracts honest

## What belongs elsewhere

- Runtime or kernel code (`lanytehq/lanyte`)
- Foundation coding standards (`3leaps/crucible`)
- Legal/governance policy text (`3leaps/oss-policies`)
