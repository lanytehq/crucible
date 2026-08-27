---
title: ADR-0016 Agent-Critical File Input Symlink Policy
description: Agent-critical named file inputs must fail closed on symlinks and special files, with bounded reads and portable baseline behavior.
---

# ADR-0016: Agent-Critical File Input Symlink Policy

Status: Accepted

Approvers: secrev, cxotech, @3leapsdave

## Context

Lanyte and adjacent 3 Leaps galaxy tools increasingly accept named files whose
contents carry meaningful agent context, instructions, findings, checkpoints,
message bodies, schemas, or contracts. Examples include:

- `chanvoy --message-file <path>` inputs that become chat posts, DMs, or
  notifications
- `stashvoy checkpoint --file <path>` checkpoint payloads
- `stashvoy schema validate <file>` and similar validation commands
- future `kanvoy`, review, audit, or orchestration tools that ingest local files
  as agent-facing context

On shared development machines, multiple agent roles share the same filesystem
and temporary directories. If a tool follows a symlink at a trust boundary, the
named path no longer identifies the file being trusted. A path such as
`/tmp/shared/message.md` can be replaced with a symlink to another readable file;
the tool then reads content the caller did not intentionally name. That content
may be posted to a channel, stored in a checkpoint, quoted into a finding, or used
as the basis for an architectural or security decision.

Following a symlink is asymmetric risk. Refusing a symlinked path costs an
operator a small correction: pass the real path. Following a planted redirect can
irreversibly disclose or propagate unintended content.

This issue surfaced during `chanvoy` PR #38. The maintainer set the
posture: for agent-critical file inputs, fail closed rather than follow and warn.

## Options Considered

### Option A: Follow symlinks and warn

The tool accepts symlinked inputs, reads the target, and emits a diagnostic.

- Pros: Convenient for operators who intentionally use symlinks.
- Cons: The read has already happened. A warning does not undo an unintended
  file read, chat post, checkpoint write, validator result, or review finding.
  It also normalizes a path shape that is unsafe in shared agent workspaces.

### Option B: Reject only final-component symlinks

The tool checks `symlink_metadata()` on the named path and refuses if the final
component is a symlink. It also rejects special files and enforces a read size
cap. This is portable and implementable immediately across Rust, Go, and other
toolchains.

- Pros: Portable. Simple. Catches the most likely shared-temp redirect attack.
  Establishes one standard remediation: pass the real path.
- Cons: Does not eliminate every filesystem race. Intermediate-directory
  symlinks and metadata-to-open time-of-check/time-of-use races remain outside
  the baseline.

### Option C: Use handle-based no-follow open everywhere

On Unix-like systems, open the path with `O_NOFOLLOW`, then verify the opened
handle with `fstat` before reading. Equivalent platform-specific techniques are
used where available.

- Pros: Stronger against final-component symlinks and metadata-to-open races.
- Cons: Platform-specific. Requires more careful implementation per language and
  OS. Not a good first floor for every current tool.

## Decision

Agent-critical named file inputs must fail closed on symlinks.

For any CLI, daemon, MCP bridge, validator, or agent tool that reads a named file
whose contents carry agent context, instructions, findings, checkpoints, message
bodies, schemas, contracts, or decision material, the required baseline is:

1. Use `symlink_metadata()` or the language/platform equivalent on the named path.
2. If the final path component is a symlink, refuse the input before reading.
3. The error message must name the cause (`symlink`) and the remediation: pass the
   real path.
4. Reject special files before reading. Directories, FIFOs, sockets, block
   devices, character devices, and other non-regular files are not acceptable
   context-file inputs.
5. Enforce a bounded read size. The default cap is 4 MiB unless a tool documents
   a tighter or wider cap with a clear reason.
6. Preserve stdin as the intentional streaming escape hatch. Stdin is not a named
   filesystem trust boundary, but stdin content should still be subject to size
   limits where practical.

The named path is part of the trust assertion. For agent-critical content, the
file named by the caller must be the file the tool reads.

A file input is agent-critical if its contents can be posted, persisted, quoted
into a durable artifact, or influence an agent action or decision. When unsure,
treat it as agent-critical. This classifier is normative; the examples in this
ADR are not an exhaustive list.

## Scope

This policy applies across Lanyte platform tools and should be carried into
adjacent 3 Leaps galaxy tools where agents rely on local file inputs for
coordination, review, checkpointing, validation, or decision support.

In scope:

- Agent message files and notification body files
- Checkpoint files and session state files
- Schema, contract, and policy files supplied to validators
- Review, audit, and security finding files
- Task, handoff, scheduler, and coordination files consumed by agent tools
- Reference-material file inputs used for architectural, security, or operational
  decisions

Out of scope:

- Ordinary source-code imports handled by language toolchains
- Binary execution lookup on `PATH`
- Repository layout symlink discussions unrelated to agent-critical file input
  reads
- Direct user-provided stdin streams, except for size-cap expectations

## Out-of-Scope But Tracked: Agent Runtime Bootstrap

This ADR governs named file reads performed by tools through a safe read path. It
does not close every symlink risk in the agent runtime bootstrap surface.

Related risks requiring separate controls:

- Warm-up profiles such as
  `~/devsecops/vars/agent-identity/<role>-<scope>.sh` are sourced as shell code.
  A symlink, file swap, or redirect there is code execution in the agent identity
  context, not merely a content read.
- `AGENTS.md`, `AGENTS.local.md`, and local `chat/` files are read by the
  harness/operator path, not necessarily by a CLI helper covered by this ADR.
- Predictable checkpoint staging paths such as
  `/tmp/checkpoint-${ROLE}-${SCOPE}.json` have a write-side symlink risk. A
  read-side guard in `stashvoy checkpoint --file` does not prevent a writer from
  following a pre-planted symlink. The separate control should use private
  per-role directories with restrictive permissions or no-follow/exclusive write
  semantics such as `O_NOFOLLOW | O_EXCL` where available.

These are security-relevant, but they are not solved by the safe context-file
read standard. They should be tracked as follow-up bootstrap hardening work.

## Non-Goals and Hardening Path

The baseline does not claim to fully solve every filesystem ambiguity.

- Intermediate-directory symlinks are documented risk at this baseline.
- Metadata-to-open time-of-check/time-of-use races are documented risk at this
  baseline.
- Unix `O_NOFOLLOW` plus `fstat` is the recommended hardening upgrade for tools
  that need stronger protection. Equivalent handle-based validation should be
  used on other platforms when available.
- Windows symlink creation is commonly privilege-gated, but Windows tools still
  must implement the portable baseline where possible.

The portable baseline is mandatory first because it is easy to apply consistently
and closes the shared-temp redirect class immediately. Stronger platform-specific
open flows may be added later without weakening the baseline.

Identity-adjacent tools should adopt handle-based no-follow validation sooner
than ordinary tools. In particular, `lanyte-attest` and any path that reads JWT,
signing-key, credential, identity-profile, or attestation material should have a
required follow-up for `O_NOFOLLOW` plus `fstat` or the platform equivalent. For
those paths, metadata-to-open replacement is a key-substitution risk, not just a
context-confusion risk.

## Drift Control

Security baselines must not silently diverge across tools.

Preferred path for Rust tools: publish and use a tiny standalone safe-read
micro-crate, following the `ipcprims` / `seclusor` pattern rather than coupling
tools to the `lanyte` TCB workspace. The crate should carry:

- the safe read helper
- consistent diagnostics or diagnostic primitives
- conformance fixtures for symlink, FIFO, socket, device, directory, and oversize
  rejection

Until that crate exists, or for non-Rust tools, every adopting repo must implement
the local helper and wire the same conformance fixture set into CI. Copying the
pattern without tests is not sufficient for a security floor.

## Implementation Pattern

Rust tools should centralize this behavior in a reusable helper rather than
re-implementing it in every command path.

```rust
fn read_agent_critical_file(path: &std::path::Path, max_bytes: u64) -> anyhow::Result<String> {
    let meta = std::fs::symlink_metadata(path)?;

    if meta.file_type().is_symlink() {
        anyhow::bail!(
            "refusing to read symlinked input {}; pass the real path",
            path.display()
        );
    }

    if !meta.is_file() {
        anyhow::bail!(
            "refusing to read non-regular input {}; expected a regular file",
            path.display()
        );
    }

    if meta.len() > max_bytes {
        anyhow::bail!(
            "refusing to read input {}; file exceeds {} byte limit",
            path.display(),
            max_bytes
        );
    }

    std::fs::read_to_string(path).map_err(Into::into)
}
```

Tools should adapt error types and diagnostics to their local style, but the
behavior must stay consistent.

## Documentation Requirements

Tool docs and briefs that introduce named agent-critical file inputs must state:

- symlinked paths are refused
- special files are refused
- the size cap
- stdin behavior, if stdin is supported

Existing guidance that encourages agents to consume symlinked paths for critical
context must be revised. For example, any "latest" symlink guidance used for
agent decision context should instruct agents to resolve or select the concrete
dated path first, then read the real path.

## Consequences

- Positive: Prevents a shared-filesystem redirect from silently turning a named
  context file into a different readable file.
- Positive: Gives tool authors one portable baseline for safe context-file reads.
- Positive: Makes the chanvoy chanvoy PR #38 hardening reusable across stashvoy, kanvoy,
  and future agent tools.
- Positive: Keeps the operator remediation simple and explicit: pass the real
  path.
- Negative: Operators who intentionally use symlinks for message files,
  checkpoints, or validator inputs must resolve them before calling the tool.
- Negative: Some existing documentation that relies on convenience symlinks must
  be updated.
- Risk: Final-component refusal does not fully address intermediate-directory
  symlinks or TOCTOU races. This is accepted as the portable floor; handle-based
  no-follow open is the future hardening path.

## Initial Follow-Up Targets

- `chanvoy`: chanvoy PR #38 / PR #38 is the reference implementation for baseline
  `--message-file` hardening.
- `stashvoy`: harden checkpoint `--file` and `schema validate <file>` reads.
- `kanvoy`: require the safe read helper before adding import/apply, message,
  review, MCP, or scheduler file inputs.
- `lanyte-attest`: add no-follow handle-based validation for identity and
  attestation material reads.
- Agent bootstrap: track a separate hardening item for sourced identity profiles,
  AGENTS/chat reads, and predictable `/tmp` checkpoint staging writes.
- `docs/guides/refbolt-workspace.md`: replace agent-critical
  `latest` symlink read guidance with concrete dated-path resolution.
- 3 Leaps galaxy tools: carry the same posture to Fulmen, Galaxy, and other
  agent-facing repos that accept context, finding, checkpoint, validator, or
  message files.

## References

- chanvoy PR #38: `chanvoy` message-writing verbs with `--message-file` and stdin
- `chanvoy` PR #38: reference baseline implementation
- `stashvoy` checkpoint `--file` and `schema validate <file>` call sites
- `AGENTS.local.md`: shared filesystem warning for concurrent agent sessions
- `docs/guides/refbolt-workspace.md`: current `latest` symlink
  guidance that should be updated for agent-critical reads
