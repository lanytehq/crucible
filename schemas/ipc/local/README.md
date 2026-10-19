# Local runtime-control contracts

These consumer-specific contracts are separate from numbered gateway channels.
The numbered IPC directory loader does not recurse into this directory. Validate
an explicitly selected root; a numbered-channel validation pass does not
validate these contracts. There is no channel number or gateway process-control
permission associated with this family.

## Chanvoy runtime-control v1

The family is `chanvoy-runtime-control-v1.schema.json`. Each
`<root>.selected.schema.json` selects one transport boundary and embeds the
same definitions. `chanvoy-runtime-control-v1.roots.json` lists the nine roots,
byte budgets and parsing policy. See [semantics](chanvoy-runtime-control-v1.md)
and [ADR-0018](../../../docs/decisions/adr-0018-local-runtime-control-contract.md).

Fixtures live in `fixtures/chanvoy-runtime-control-v1/`. The manifest has 100
cases; `schema` and `data` paths resolve from the repository root. Each case
names its expected validity and selected root. For example, from the root:

```sh
goneat schema validate-data \
  --schema-file schemas/ipc/local/retire_rpc_request.selected.schema.json \
  --data schemas/ipc/local/fixtures/chanvoy-runtime-control-v1/retire_rpc_request-positive.json \
  --format json
```

`make check-chanvoy-runtime-control-v1` runs the explicit family gate, also
included in `make check` and therefore in the check and release workflows. It
checks schema meta-validity with an invalid-schema control, shared definitions,
exact root selection, all 100 fixture expectations and complete positive/negative
coverage for each root. It resolves manifest paths from the repository root.

Validate every manifest case against its named selected schema and compare the
result to `expected_valid`. Independently check family and selected schemas
against JSON Schema 2020-12, including an invalid-schema negative control.
Schema validation alone cannot enforce duplicate-key rejection, byte budgets,
strict UTF-8, request/response correlation or native process authority. Consumers
must implement and test those checks separately, pin an exact upstream commit
and schema hashes, and reject unknown versions without a destructive fallback.

Adding these contracts does not activate Chanvoy lifecycle behavior. A consumer
requires separate compatibility review and native handoff/retirement evidence.
