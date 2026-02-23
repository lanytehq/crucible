# IPC Schemas (Seed)

This folder is intended to contain JSON Schemas for each channel used at the core gateway boundary.

Bootstrap channels to define early:

- CONTROL/COMMAND/TELEMETRY/ERROR (built-in)
- MAIL (256)
- PROXY (257)
- ADMIN (258)
- SKILL_IO (259)

These schemas should be validated during development via `ipcprims echo --validate <schema_dir>`.
