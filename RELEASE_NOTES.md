# Release Notes

Current release notes for Lanyte Crucible. For complete history, see
[CHANGELOG.md](CHANGELOG.md). Per-release archives live in
[docs/releases/](docs/releases/).

**Content policy**: keep the most recent 3 releases in this file
(reverse chronological). Older entries remain only under `docs/releases/`.

---

## v0.3.0 (2026-10-26)

Contract release since v0.2.0. Three additions, and the limit that
travels with them.

- **Agentic content v0** — what a seat captures so work can continue
  across sessions, as a durable-record/v1 profile with a kind registry
  and `make check-content-v0`. Week and day lists accept optional
  structured goals; ranks are multiples of 1/16 (ADR-0019). DDR-0002
  remains Proposed.
- **Classifiers** — `content-kind` and `week-start` dimensions, and
  pinned copies of four 3leaps dimensions, under `config/classifiers/`.
- **Secret-shaped names and values** — one shared rule in
  `schemas/common/v0/secret-keys`, with a conformance table every regex
  engine must match.

Publishing the contracts does not qualify an implementation. `make check`
qualifies this repository only.

See [docs/releases/v0.3.0.md](docs/releases/v0.3.0.md).

---

## v0.2.0 (2026-10-19)

Contract release since v0.1.0. Three additions, and two limits that
travel with them.

- **Local runtime control v1** — nine transport-selected roots under
  `schemas/ipc/local/`, with 100 conformance cases and
  `make check-chanvoy-runtime-control-v1`. The numbered gateway loader
  does not discover this directory. Select the root your transport
  uses. Schema acceptance is not process-death, lease-release, or
  readiness proof. ADR-0018 remains Proposed.
- **Chanvoy wait and follow RPC** — process-held channel follow,
  named-DM wait and follow, and inbox wait and follow, plus mention
  filtering and bounded coalescing on the v2 methods. Call the method
  you implement. A missing method is a hard capability failure.
  Inbox resume uses the inbox cursor, not a post id.
- **Mail policy v0** — delegation, action request, and policy decision
  under `schemas/mail/v0/`, with `make check-mail-v0`. These records
  carry references and decisions, not message bodies or provider
  effects. DDR-0001 remains Proposed. The numbered MAIL channel is
  unchanged.

Existing numbered IPC schema files are unchanged. Pin the published
commit and verify embedded schema hashes. `make check` and
`make quality` qualify this repository only.

See [docs/releases/v0.2.0.md](docs/releases/v0.2.0.md).

---

## v0.1.0 (2026-08-27)

**First public-track release of Lanyte Crucible.** GitHub slug
[`lanytehq/crucible`](https://github.com/lanytehq/crucible). Display name
unchanged.

- **Vessel identity** — clone and docs paths use `lanytehq/crucible`.
- **Public surface** — community health files, `LIFECYCLE_PHASE=alpha`,
  three-org crucible map, role-catalog split vs `3leaps/crucible`.
- **Indexes** — ADR index matches disk; IPC bootstrap list includes
  channel 260.
- **No schema bumps** — contract families are unchanged from `v0.0.1`.

See [docs/releases/v0.1.0.md](docs/releases/v0.1.0.md).
