# Chanvoy daemon RPC v0

This family defines versioned contracts at Chanvoy's local daemon JSON-RPC
boundary. It is intentionally outside `schemas/ipc/`: these methods are not
numbered Lanyte core-gateway channels and are not loaded by ipcprims.

## Artifacts

| Artifact                              | Purpose                                                                   |
| ------------------------------------- | ------------------------------------------------------------------------- |
| `methods.md`                          | Method catalog, outcome mapping, capability rule, and semantic invariants |
| `wait_channels_v1.params.schema.json` | Strict parameters for bounded multi-channel wait                          |
| `wait_channels_v1.result.schema.json` | Successful first-match result                                             |
| `wait_channels_v1.error.schema.json`  | Existing daemon JSON-RPC error-detail shape and allowed codes             |
| `fixtures/`                           | Conforming and negative examples for every schema                         |

All schemas use JSON Schema 2020-12 and reject unknown object properties.
The family validator also enforces the cross-value relations named in
`methods.md` that JSON Schema cannot express. Run
`make check-chanvoy-daemon-rpc-v0` to validate schemas and fixtures.

## Boundary and versioning

The family version (`v0`) versions the daemon protocol catalog. The method
suffix (`wait_channels_v1`) is the capability version visible to a client.
Changing an existing method incompatibly requires a new method name; clients
must not infer support from the family directory name.

The schemas cover wire-shape constraints. Cross-value relations which JSON
Schema cannot express are normative in `methods.md` and must be enforced by
the producer and consumer.
