# Classifiers

Discrete choice sets that Lanyte contracts use as opaque keys. The layout and
the definition format follow the 3leaps/crucible classifiers framework.

| Path                                                     | Holds                                                             |
| -------------------------------------------------------- | ----------------------------------------------------------------- |
| `dimensions/<key>.dimension.json`                        | Lanyte-owned dimensions                                           |
| `vendor/3leaps/dimensions/`                              | 3leaps dimensions Lanyte contracts inline (verbatim, pinned)      |
| `vendor/3leaps/schemas/dimension-definition.schema.json` | The dimension meta-schema every definition here validates against |

## Rules

- A dimension is identified by its `key`; a value by its value key. Consumers
  use both as opaque strings and do not depend on ordinals.
- `unknown` is an explicit, deferred decision. It is never a default, and
  missing classification is an error.
- A contract that uses a dimension inlines its value set and adds a drift
  check against the definition here, so the two cannot diverge silently.
- Vendored files are never edited. Refresh them with
  `scripts/vendor-3leaps-contracts.sh`, which rewrites `MANIFEST.json` with the
  source commit and sha256 of each file.

## Dimensions

| Key                   | Owner             | Status | Used by                      |
| --------------------- | ----------------- | ------ | ---------------------------- |
| `content-kind`        | lanytehq          | draft  | `schemas/agentic/content/v0` |
| `week-start`          | lanytehq          | draft  | reader display convention    |
| `sensitivity`         | 3leaps (vendored) | stable | `schemas/agentic/content/v0` |
| `access-tier`         | 3leaps (vendored) | stable | `schemas/agentic/content/v0` |
| `retention-lifecycle` | 3leaps (vendored) | stable | `schemas/agentic/content/v0` |
| `volatility`          | 3leaps (vendored) | stable | `schemas/agentic/content/v0` |
