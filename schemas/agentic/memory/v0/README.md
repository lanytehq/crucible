# agentic/memory v0

The information an agent stores, retrieves, and searches across sessions:
identity, charter, plans, handoffs, decisions, learned facts, references,
credential references, and blobs. Checkpoints keep their existing format and
are listed here as a legacy kind.

## Shape

An entry is a [durable-record/v1](https://github.com/3leaps/crucible) record.
This family is a profile: it narrows the record and adds no fields, so an
entry stays valid wherever a durable-record record is expected.

| Piece                                                | File                                                       |
| ---------------------------------------------------- | ---------------------------------------------------------- |
| Entry envelope (profile of durable-record/v1 record) | `entry.schema.json`                                        |
| One payload contract per kind                        | `kinds/agent-<kind>.schema.json`                           |
| Kind registry schema                                 | `kind-registry.schema.json`                                |
| Kind registry instance                               | `config/agentic/memory/v0/kinds.json`                      |
| Kind vocabulary (classifier dimension)               | `config/classifiers/dimensions/memory-kind.dimension.json` |
| Rules JSON Schema cannot express                     | `semantic-validation.md`                                   |
| Revision digest vectors (RFC 8785 + sha256)          | `digest-vectors.json`                                      |
| Fixtures                                             | `fixtures/{entry,kind-registry}/`                          |

`payload_contract` tokens are `contract: agent-<kind>/v0`. The registry maps
each kind to its token, writer class, revision policy, and classification
floor. Writer class and classification are registry properties; nothing in a
payload changes them.

## Classification

Entries carry `classification{retention, sensitivity}` with the 3leaps
classifier keys. The registry sets a per-kind floor for sensitivity,
access-tier, and retention-lifecycle, and the expected volatility of each
kind's stream. The enums are inlined and checked against vendored copies of
the 3leaps dimension definitions.

## Vendored files

`config/classifiers/vendor/3leaps/`, `schemas/vendor/3leaps/`, and
`scripts/vendor/3leaps/` hold verbatim copies of 3leaps/crucible files, each
pinned by commit and sha256 in its `MANIFEST.json`. Refresh with
`scripts/vendor-3leaps-contracts.sh` and review the diff.

## Validate

```bash
make check-memory-v0
```
