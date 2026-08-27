# refbolt Reference Documentation Workspace

## Overview

[refbolt](https://github.com/fulmenhq/refbolt) archives web documentation sites into clean,
date-versioned Markdown trees. Every dev machine in the Lanyte ecosystem should maintain a local
refbolt workspace so that agents and developers can read API reference docs offline, without web
fetches, and with version-pinned consistency.

## Setup

### Install

Install and configure from the public
[fulmenhq/refbolt](https://github.com/fulmenhq/refbolt) README. Optional HTML
fetch credentials (if any) are documented there — do not put API keys in this
repository.

### Refresh

Follow the public refbolt README for `sync`. Archive root is an operator
choice; this repository does not pin a home-directory path.

```
<archive-root>/
├── llm-api/
│   ├── xai/
│   │   ├── 2026-03-23/          # Date-versioned snapshot
│   │   │   ├── llms.txt
│   │   │   └── developers/...   # Individual .md pages
│   │   └── latest -> 2026-03-23 # Symlink to most recent
│   ├── anthropic/
│   │   ├── 2026-03-23/
│   │   │   ├── llms-full.txt
│   │   │   └── en/...           # 488 parsed sections
│   │   └── latest -> 2026-03-23
│   └── openai/
│       ├── 2026-03-23/
│       │   ├── docs/...         # Jina-converted HTML
│       │   └── openapi.yaml     # OpenAPI spec from GitHub
│       └── latest -> 2026-03-23
├── python-libs/
│   └── pydantic/latest/
├── cloud-infra/
│   └── aws-*/latest/
├── data-platform/
│   └── trino/latest/
└── container-platform/
    └── kubernetes-kubectl/latest/
```

### Key properties

- **`latest` symlink**: Always points to the most recent sync date. Use this in briefs,
  scripts, and agent context — never hardcode a date.
- **Immutable snapshots**: Files inside a date directory are never modified after creation.
  Diff between dates to see API changes: `diff -r 2026-03-21/ 2026-03-23/`
- **Topic/provider hierarchy**: Matches refbolt's `providers.yaml` config. Topic slugs
  group related providers; provider slugs match the config `slug` field.

## Using Reference Docs in Briefs and Agent Context

### For task briefs

When a brief references a provider API, point to the refbolt archive:

```markdown
## References

- xAI Responses API: `<archive-root>/llm-api/xai/latest/developers/rest-api-reference/`
- Anthropic Messages API: `<archive-root>/llm-api/anthropic/latest/en/api-reference/`
- OpenAI API Reference: `<archive-root>/llm-api/openai/latest/docs/api-reference/`
```

### For agent sessions

Agents should read from the `latest` symlink path. Example — before implementing an LLM adapter:

```
Read <archive-root>/llm-api/openai/latest/docs/api-reference/responses.md
```

This replaces ad-hoc web fetches that may return stale or incomplete content.

### For PR reviews

When reviewing adapter code against API contracts, the reviewer reads the archived docs as the
source of truth for what the provider API actually looks like at the time of implementation.

## What Gets Synced

refbolt's `configs/providers.yaml` defines the active providers. As of v0.0.1:

| Provider           | Strategy                              | Content                            |
| ------------------ | ------------------------------------- | ---------------------------------- |
| xAI/Grok           | native (llms.txt + .md pages)         | ~100 files, full API reference     |
| Anthropic          | native (llms-full.txt, 488 sections)  | ~490 files, complete platform docs |
| OpenAI             | jina (HTML→Markdown) + GitHub OpenAPI | API reference pages + openapi.yaml |
| Pydantic           | native (llms-full.txt)                | Schema validation reference        |
| AWS Glue/Bedrock   | hierarchical llms.txt                 | Per-service docs                   |
| Trino              | github-raw                            | Query engine reference             |
| Kubernetes kubectl | github-raw                            | CLI reference                      |

To add a new provider, edit `configs/providers.yaml` in the refbolt repo. See the refbolt
README for fetch strategy options and provider configuration.

## Not in Scope

- **This guide does not replace refbolt's own documentation.** For fetch strategies, Docker
  workflows, git-commit mode, and provider quirks, see the refbolt repo.
- **No CI integration.** refbolt syncs are local, operator-initiated. CI environments should
  not depend on archived docs being present.
- **No version pinning across machines.** Each machine syncs independently. The `latest`
  symlink points to that machine's most recent sync, which may differ between developers.
  This is acceptable — API docs don't change frequently enough to cause issues within a sprint.
