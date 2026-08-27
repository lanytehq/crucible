# IPC schemas

JSON Schema 2020-12 contracts for numbered channels at the core gateway
boundary. Loaded at runtime by [ipcprims](https://github.com/3leaps/ipcprims).
User channels MUST be named `channel_NNN.schema.json` (ADR-0006).

| Channel | Schema file               | Peer                  |
| ------- | ------------------------- | --------------------- |
| 0       | `control.schema.json`     | all peers — handshake |
| 1       | `command.schema.json`     | all peers — commands  |
| 3       | `telemetry.schema.json`   | all peers — metrics   |
| 4       | `error.schema.json`       | all peers — errors    |
| 256     | `channel_256.schema.json` | mlvoy — email         |
| 257     | `channel_257.schema.json` | fulminar — HTTP proxy |
| 258     | `channel_258.schema.json` | lanyte-admin          |
| 259     | `channel_259.schema.json` | skill executor I/O    |
| 260     | `channel_260.schema.json` | chanvoy — chat bridge |

Validate:

```sh
ipcprims echo /tmp/lanyte-test.sock --validate schemas/ipc/
```
