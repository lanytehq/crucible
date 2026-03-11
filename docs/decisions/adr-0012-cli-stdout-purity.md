---
title: ADR-0012 CLI Stdout Purity Policy
description: stdout is reserved for programmatic output in all Lanyte CLI tools; diagnostics, confirmations, and errors go to stderr
---

# ADR-0012: CLI Stdout Purity Policy

Status: Accepted

## Context

Lanyte CLI tools (`lanyte-ctx`, `lanyte-attest`, and future tools) produce two kinds of output: programmatic data that callers pipe to `jq`, capture in variables, or feed to other tools, and human-facing diagnostics like confirmations, warnings, and resolved paths.

Mixing both on stdout breaks pipelines. A script that captures `lanyte-ctx resume` output to parse as JSON gets a confirmation line prepended. A CI pipeline that checks `lanyte-ctx checkpoint` exit code also gets unsolicited output that pollutes logs.

This problem is well-understood in Unix tooling. The convention is simple and nearly universal, but easy to violate in practice — especially in early development where `println!` is the path of least resistance.

## Options Considered

### Option A: Structured output mode flag (`--json`, `--quiet`)

Each command gets flags to control output format. `--json` suppresses human text; `--quiet` suppresses confirmations.

- Pros: Explicit control per invocation.
- Cons: Every command needs flag handling. Default behavior (no flags) is still ambiguous. Callers must remember to pass the flag — the tool is noisy by default.

### Option B: stdout purity by default (chosen)

stdout is unconditionally reserved for programmatic output. All diagnostics go to stderr. No flags needed — the default is pipeline-safe.

- Pros: Zero configuration for callers. Works with `jq`, `xargs`, `$()` capture out of the box. Matches `curl -s`, `git log --format`, `sqlite3 -json` behavior.
- Cons: Slightly less discoverable for interactive users (confirmations on stderr, not stdout). Mitigated by `RUST_LOG` for explicit diagnostics.

## Decision

**stdout is reserved for programmatic output only.** This applies to all Lanyte CLI tools.

### What goes to stdout

- Structured data: JSON objects, JSON arrays, or delimited text that a caller may pipe or capture.
- Raw content when the command's purpose is to emit content (e.g., `lanyte-ctx resume` outputs state JSON, `lanyte-ctx docs show` outputs markdown).

### What goes to stderr

- Success confirmations ("checkpoint saved", "database initialized")
- Diagnostic information (resolved paths, versions, timing)
- Warnings and errors
- Progress indicators
- Logging output (`RUST_LOG` / `env_logger`)

### Silent success convention

Commands that write to a store (e.g., `checkpoint`, `init`) produce **no stdout output** on success. The exit code is the signal. Diagnostics are available via `RUST_LOG=info` on stderr. This follows the Unix convention for write commands — `cp`, `mv`, `mkdir` are silent on success.

### Exit code contract

Exit codes are the primary success/failure signal, not output parsing:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Not found or I/O error |
| 2 | Unsupported operation for this backend/configuration |
| 3 | Validation or schema error |

Tool-specific codes above 3 are permitted but must be documented in the tool's CLI reference.

### Implementation pattern (Rust)

```rust
// Programmatic output → stdout
println!("{}", serde_json::to_string_pretty(&state)?);

// Diagnostics → stderr (via log crate + env_logger)
log::info!("using sqlite backend: {}", db_path.display());

// Errors → stderr (already correct via eprintln!)
eprintln!("error: {}", err);
```

Do not use `println!` for confirmations, diagnostics, or status messages. If a message is not data that a caller would parse, it belongs on stderr.

## Scope

This policy applies to:

- `lanyte-ctx` (implemented in CRT-011A)
- `lanyte-attest` (apply at initial implementation)
- All future Lanyte CLI tools

## Prior Art

- Unix convention: stdout for data, stderr for diagnostics. `grep`, `find`, `curl -s`, `jq` all follow this.
- Go tooling in the 3leaps ecosystem (goneat, gofulmen) follows the same pattern.
- `env_logger` defaults to stderr — no configuration needed.

## Consequences

- Positive: All Lanyte CLI tools are pipeline-safe by default. No `--quiet` or `--json` flags needed for basic scripting.
- Positive: `RUST_LOG` provides opt-in diagnostics without polluting stdout.
- Negative: Interactive users see no confirmation on stdout after `checkpoint` — they must check exit code or enable `RUST_LOG`. This is intentional.
- Risk: New contributors may use `println!` for confirmations out of habit. Code review and this ADR are the mitigations.
