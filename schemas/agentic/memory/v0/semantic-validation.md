# agentic/memory v0 semantic validation

JSON Schema validates the entry envelope, each kind's payload, and the kind
registry. Writers and readers must also enforce these rules. The numbered
rules marked **(gate)** are checked by `make check-memory-v0`; the others need
runtime state the fixtures cannot carry.

## Envelope rules

1. Every entry is a durable-record/v1 record. The profile narrows the record;
   it never adds a field. **(gate)**
2. `payload_contract` names exactly one registered kind, and the payload
   validates against that kind's schema. **(gate)**
3. `stream` is `<role>.<scope>` of the seat that owns the stream. Session
   tags are labels (`tag:<name>`), not part of the stream.
4. A kind whose registry `carrier` is `body` carries a body reference and no
   inline payload; every other kind carries a payload. **(gate)**
5. The revision digest is sha256 over the RFC 8785 (JCS) bytes of the whole
   entry, prefixed `sha256:`. `digest-vectors.json` pins expected values that
   every implementation must reproduce. **(gate)**
6. Store-assigned values (row id, store time, idempotency key, current or
   retired status) stay outside the entry and outside the digest. Authored
   times belong in the payload.

## Revision rules

1. `revision_policy: single` kinds are written at revision 1 only. A
   correction is a new entry that links to the old one.
2. `revision_policy: revisioned` kinds supersede by `record_id`; each
   revision names the previous revision and its digest. A stale `supersedes`
   is a revision conflict and is never merged.
3. Every write carries an idempotency key scoped to the stream. A repeat with
   the same digest returns the original outcome; a repeat with a different
   digest is an idempotency conflict.
4. Withdrawing an entry marks it retired. Retired entries keep their history
   and are skipped by current reads; nothing is deleted or rewritten.
5. The legacy checkpoint lane keeps its own hash chain. Its stored values are
   never recomputed or reinterpreted as entry digests.

## Authority rules

1. `writer_class` comes from the registry, never from the entry.
2. `provenance.actor_kind` is a claim. The writer's credential is the
   authority. A writer must present a credential whose role matches the
   claimed writer class; with no credential, the write fails closed rather
   than falling back to the claim.
3. Offline validation has no credential. It rejects a claim that cannot match
   the writer class (an agent claiming a maintainer-class kind) and accepts a
   consistent claim without treating it as proof. **(gate)**
4. Agent-class kinds are written into the writer's own stream. The one
   exception is a handoff acknowledgement: a later revision of a handoff
   written by the receiving seat. **(gate)**
5. `attestation: required` kinds need a verified attestation session
   reference on the write.

## Classification rules

1. Classifier values are the 3leaps dimension keys, used as opaque strings.
   The enums inlined in these schemas must equal the vendored dimension
   definitions. **(gate)**
2. A registry kind's access tier meets the floor for its sensitivity:
   0-public → public; 1-confidential and 2-blinded → internal;
   3-proprietary → restricted; 4-personal and 5-privileged → privileged;
   6-eyes-only → eyes-only. **(gate)**
3. An entry's sensitivity and retention are at or above its kind's floor.
   Writers may raise classification and never lower it below the floor.
   **(gate)**
4. `unknown` records a decision not yet made. It is never a default. A kind
   marked `classification_at_write: required` rejects `unknown`. **(gate)**
5. Readers do not serve an entry whose access tier exceeds the reading seat's
   tier. `wake` and `recall` renders take the strictest classification of the
   entries they include.
6. Volatility describes how often a kind changes within a stream. It is set
   in the registry, never on an entry.

## Content rules

1. No payload carries a secret value. Member names matching
   `common/v0/secret-keys.schema.json#/$defs/secretShapedName` are rejected at
   any depth. **(gate)**
2. A credential reference names where a credential lives and how to unlock
   it. It never holds the credential.
3. A blob body is capped by the registry's `max_body_bytes`. **(gate)** Blobs
   are excluded from `wake`, `export`, and `seed`.
4. A reference is a pointer with a content digest. It never copies the
   referenced document.
