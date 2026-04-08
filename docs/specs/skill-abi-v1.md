---
title: Skill ABI v1
description: Canonical ABI contract between the Lanyte executor and WASM skills
status: ratified
version: 1.0.0
---

# Skill ABI v1

This document defines the canonical **Skill ABI v1** contract between the Lanyte
executor and a skill packaged as a WebAssembly module.

The ABI exists so that:

- skill authors can build portable modules without depending on executor internals
- the executor can validate, load, invoke, and retire skills predictably
- orchestrator-side `InvokeSkill` effects have a stable execution target
- capability declarations can be surfaced consistently into future taxonomy work

This is an **internal execution contract**, not an IPC schema. The peer-facing
`channel_259.schema.json` contract remains the schema boundary for SKILL_IO traffic.

## Normative Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHOULD", and "MAY" in this document
are to be interpreted as described in RFC 2119.

## Scope

This spec defines:

- the required exports of a Skill ABI v1 WebAssembly module
- the linear-memory buffer contract between executor and skill
- how `ActionIntent` input and `ActionOutcome` output cross the ABI boundary
- the skill manifest and capability declaration surface returned by `describe`
- lifecycle, error handling, and version negotiation rules

This spec does not define:

- the executor implementation itself
- skill packaging, signing, or provenance policy beyond ABI-visible metadata
- the capability taxonomy vocabulary; that is the scope of `STD-005`
- the peer-facing SKILL_IO IPC schema; that already exists in `channel_259.schema.json`

## Design Principles

### 1. Raw ABI, structured payload

The binary boundary is a simple wasm32 ABI using exported memory, pointers, and lengths.
The semantic payload crossing that boundary is UTF-8 JSON.

This avoids coupling the ABI to any one host language or Rust crate layout.

### 2. Fresh instance per execution

Skills run as isolated WASM modules inside the executor sandbox. In v1, the executor
MUST treat each skill invocation as a **fresh instance**. Skills MUST NOT depend on
persistent in-memory state across invocations.

### 3. Executor owns policy

The skill supplies logic. The executor owns:

- fuel and wall-clock limits
- memory limits
- capability grants
- validation of input/output JSON
- lifecycle and teardown

### 4. ABI versioning must fail loudly

The executor MUST reject skills that do not declare a supported ABI version before
invocation begins.

## Module Requirements

A Skill ABI v1 module MUST be a `wasm32` module that exports:

- `memory`
- `lanyte_skill_abi_version() -> i32`
- `lanyte_skill_alloc(size: i32) -> i32`
- `lanyte_skill_free(ptr: i32, len: i32)`
- `lanyte_skill_describe() -> i64`
- `lanyte_skill_invoke(input_ptr: i32, input_len: i32) -> i64`
- `lanyte_skill_last_error() -> i64`

The executor MUST reject modules that omit any required export.

## Memory Contract

Skill ABI v1 uses the module's exported linear memory as the only byte transport between
executor and skill.

### Buffer ownership

- The executor MUST call `lanyte_skill_alloc` to reserve guest memory for any input bytes
  it writes into the module.
- The executor MUST call `lanyte_skill_free` after it has finished with any guest buffer it
  caused to be allocated, including input, output, and error buffers.
- The skill MUST return pointers into its exported `memory`.
- The skill MUST NOT return pointers to freed or out-of-bounds memory.

### Packed pointer/length return value

`lanyte_skill_describe`, `lanyte_skill_invoke`, and `lanyte_skill_last_error` return an
`i64` whose low 32 bits are `ptr` and high 32 bits are `len`.

```text
packed = (len << 32) | ptr
```

Interpretation rules:

- `ptr == 0 && len == 0` means "no payload available"
- any non-zero payload MUST point to valid UTF-8 JSON bytes in guest memory
- the executor MUST bounds-check the decoded `(ptr, len)` pair before reading memory

## Export Semantics

### `lanyte_skill_abi_version`

Returns the ABI major version implemented by the module.

For this spec, the function MUST return `1`.

The executor MUST reject any module whose reported major version is not supported.

### `lanyte_skill_alloc`

Allocates a writable region in guest memory and returns the starting pointer.

Rules:

- `size` MUST be the requested byte length
- returning `0` indicates allocation failure
- the skill MUST permit the executor to write exactly `size` bytes into the returned region

### `lanyte_skill_free`

Frees a region previously returned by `lanyte_skill_alloc`, `lanyte_skill_describe`,
`lanyte_skill_invoke`, or `lanyte_skill_last_error`.

The executor MUST only free buffers once.

### `lanyte_skill_describe`

Returns a JSON-encoded skill manifest as a packed `(ptr, len)` pair.

The executor MUST call `describe` during module validation or installation before allowing
normal invocation.

If `describe` cannot produce a manifest, it MUST return `0` and make a structured error
available via `lanyte_skill_last_error`.

### `lanyte_skill_invoke`

Takes a UTF-8 JSON `ActionIntent` payload already written into guest memory at
`(input_ptr, input_len)` and returns a packed `(ptr, len)` pair for a UTF-8 JSON
`ActionOutcome` payload.

Rules:

- the skill MUST treat the input bytes as immutable
- the skill MUST validate that the input is decodable UTF-8 and valid JSON for the expected
  `ActionIntent` shape
- on success, the returned payload MUST be a valid `ActionOutcome`
- on failure, the function MUST return `0` and make a structured error available via
  `lanyte_skill_last_error`

### `lanyte_skill_last_error`

Returns a JSON-encoded `SkillError` object describing the most recent `describe` or `invoke`
failure for the current instance.

Rules:

- the returned error payload is instance-local and ephemeral
- the executor SHOULD read and free this payload immediately after a failure
- a fresh instance MUST begin with no error payload available

## Semantic Payload Contract

Skill ABI v1 deliberately separates **ABI transport** from **semantic content**.

The executor and skill exchange UTF-8 JSON bytes that map to the following logical types:

- **input**: `ActionIntent`
- **output**: `ActionOutcome`

These types are owned by the execution/verification layer, not by the ABI itself.

### ActionIntent mapping

When the orchestrator emits an `InvokeSkill` effect, the executor MUST construct an
`ActionIntent` value that captures the invocation context and serialize it to UTF-8 JSON
before calling `lanyte_skill_invoke`.

At minimum, the serialized intent SHOULD preserve:

- the target `skill_id`
- the requested operation or tool name
- the normalized input payload
- correlation references such as `action_id`, `correlation_id`, `trust_ref`, and `gate_ref`
  where available

### ActionOutcome mapping

The skill MUST return a UTF-8 JSON serialization of `ActionOutcome` on success.

The executor MUST validate the returned payload before treating the invocation as complete.
If the payload cannot be parsed or does not conform to the expected `ActionOutcome` shape,
the executor MUST treat the invocation as `output_invalid`.

### Stability rule

The ABI v1 contract is stable because the binary surface is pointers/lengths and the semantic
surface is JSON. The host and skill MUST NOT assume Rust struct layout compatibility across
crate versions, compilers, or languages.

## Skill Manifest

`lanyte_skill_describe` MUST return a JSON object with this minimum shape:

```json
{
  "skill_id": "dev.lanyte.echo",
  "name": "Echo",
  "version": "1.0.0",
  "tier": 0,
  "capabilities": ["skill.echo"]
}
```

Required fields:

- `skill_id`: reverse-domain identifier
- `name`: human-readable name
- `version`: skill version string
- `tier`: integer trust/privilege tier expected by the skill package
- `capabilities`: array of capability identifiers declared by the skill

Optional fields:

- `abi_version`: if present, MUST be `1` and MUST match `lanyte_skill_abi_version()`
- `description`
- `author`
- `operations`: array of operation descriptors
- `metadata`: additive, implementation-specific metadata

### Operation descriptors

If present, each element in `operations` SHOULD be an object with:

- `name`: operation name exposed by the skill
- `summary`: short human-readable description
- `input_schema`: optional reference or identifier for input validation
- `output_schema`: optional reference or identifier for output validation

If `operations` is omitted, the executor MAY treat the skill as having a single default
operation.

### Capability declarations

In v1, `capabilities` is an array of opaque string identifiers. The executor MAY use these
for discovery, policy checks, and future taxonomy validation.

`STD-005` will define the canonical capability vocabulary and validation rules. Until then:

- skills SHOULD use stable, lowercase, dot-namespaced identifiers
- executors MUST tolerate unknown capability strings
- unknown capabilities MUST NOT crash installation or description parsing by themselves

## Lifecycle

### 1. Load

The executor loads the module bytes and validates that the required exports exist.

The executor MUST reject modules that:

- are not valid WebAssembly
- do not export the required ABI symbols
- report an unsupported ABI version

### 2. Describe

The executor instantiates the module and calls `lanyte_skill_describe` to obtain the manifest.

The manifest drives:

- install-time validation
- skill listing and describe responses on `channel_259`
- capability visibility and future policy decisions

### 3. Invoke

For each execution:

1. the executor creates a fresh skill instance
2. the executor serializes `ActionIntent` to UTF-8 JSON
3. the executor allocates guest memory and writes the bytes
4. the executor calls `lanyte_skill_invoke`
5. the executor reads either `ActionOutcome` or `SkillError`
6. the executor frees guest buffers
7. the executor tears down the instance

### 4. Teardown

The executor MUST drop the instance after the invocation completes or fails.

Fresh-instance execution means a skill MUST NOT rely on cached state between runs. Any needed
durable state must live in executor-managed storage or a future explicit state ABI.

## Error Handling

### Structured skill error

`lanyte_skill_last_error` MUST return a UTF-8 JSON object with this minimum shape:

```json
{
  "code": "execution_failed",
  "message": "explanation",
  "retryable": false
}
```

Required fields:

- `code`
- `message`
- `retryable`

Optional field:

- `details`

### Error code alignment

Where possible, `code` SHOULD align with the existing `skill_error.error_code` values on
`channel_259`:

- `execution_failed`
- `timeout`
- `fuel_exhausted`
- `memory_exceeded`
- `input_invalid`
- `output_invalid`
- `permission_denied`
- `rate_limited`

The executor MAY map lower-level runtime failures into these normalized codes before they are
surfaced beyond the ABI boundary.

### Trap behavior

If the skill traps instead of returning a structured error:

- the executor MUST treat the invocation as failed
- the executor SHOULD map the failure to `execution_failed` unless a more precise mapping exists
- the executor MUST NOT treat a trap as a successful `ActionOutcome`

## Resource and Security Constraints

The executor MUST enforce runtime policy outside the skill itself, including:

- fuel limits
- memory ceilings
- wall-clock timeout
- sandbox boundaries
- denied ambient filesystem/network/process access unless an explicit future host ABI grants it

Skills MUST assume no ambient host privileges.

## Relationship to IPC and Executor Boundaries

The Skill ABI v1 contract is **not** the same as the SKILL_IO IPC contract.

- `channel_259.schema.json` defines peer-visible JSON messages for install/list/describe/invoke
- Skill ABI v1 defines the in-process executor-to-WASM contract

The open JSON fields in `skill_invoke_request.input` and `skill_invoke_response.output` remain
correct under ADR-0006 because skill-specific validation happens at the executor boundary.

Compatibility note:

- the current `skill_describe_response.manifest` schema on `channel_259` is still the narrower
  `skill_summary` shape
- therefore, an executor MAY need to project the full ABI manifest into that wire-safe subset when
  answering peer-visible describe requests
- richer manifest exposure over IPC is a future schema decision, not part of Skill ABI v1 itself

## Versioning Rules

### Major version

`lanyte_skill_abi_version()` returns the ABI major version.

- v1 executors MUST accept `1`
- v1 executors MUST reject unsupported majors
- breaking changes require a new ABI major version

### Additive changes

Additive manifest fields and additive error `details` content MAY be introduced as long as v1
executors can safely ignore unknown fields.

### Forward compatibility

Future work may define:

- an explicit host-call ABI
- richer operation schemas
- typed capability taxonomy validation
- component-model packaging instead of the raw wasm32 ABI used here

Those changes MUST either remain backward-compatible with v1 or ship as a new ABI major.

## Executor Compliance Checklist

A Skill ABI v1 executor is compliant if it:

1. validates required exports and ABI version before invocation
2. uses the module's exported linear memory with the alloc/free contract defined here
3. passes UTF-8 JSON `ActionIntent` bytes into `lanyte_skill_invoke`
4. validates UTF-8 JSON `ActionOutcome` bytes on success
5. reads `SkillError` on failure and normalizes traps
6. enforces fresh-instance execution and runtime limits
7. surfaces manifest capability declarations without requiring taxonomy enforcement in v1

## Open Questions

1. Should a future v1.x extension define an optional host-call table for safe access to core
   services, or should all such interaction remain mediated through executor-owned input/output only?
2. Do we want to standardize `operations` as required in a future revision once STD-005 lands?
3. When `lanyte-verify` types are pinned in crucible, should this spec reference a concrete JSON
   schema for `ActionIntent` and `ActionOutcome` rather than just the logical types?

## References

- `schemas/ipc/channel_259.schema.json`
- `docs/specs/peer-contract.md`
- `docs/decisions/adr-0006-ipc-schema-design-patterns.md`
- `docs/decisions/adr-0007-autonomy-gate-architecture.md`
- `docs/specs/agent-identity-attestation.md`
