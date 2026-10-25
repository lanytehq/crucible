# agentic/content v0 semantic validation

JSON Schema validates the entry envelope, each kind's payload, and the kind
registry. Writers and readers must also enforce these rules. Rules marked
**(gate)** are checked by `make check-content-v0`, and each negative fixture
names the rule it must be rejected for. The gate also fails if any rule
it declares has neither a negative fixture nor a self-test. **(gate, pairs)** rules relate a
revision to the revision it supersedes and are checked on
`fixtures/pairs/`; **(gate, parents)** rules relate a goal to the entry
that holds its parent and are checked on `fixtures/parents/`. The others need runtime state the
fixtures cannot carry.

## Envelope rules

Semantic rules run only on entries that pass the envelope schema and the
durable-record/v1 record schema; an entry that fails either is judged on
those errors alone. Pair rules likewise run only when both entries are
valid, and registry rules only on a registry that passes its schema.

1. Every entry is a durable-record/v1 record. The profile narrows the record;
   it never adds a field. **(gate)**
2. `payload_contract` names exactly one registered kind. A payload-carrier
   kind's payload validates against `kinds/agent-<kind>.schema.json`. A
   body-carrier kind (blob) has no payload schema: its token names the kind,
   descriptive metadata goes in `labels`, and the registry lists the body
   media types it accepts. **(gate)**
3. `stream` is `<role>.<scope>` of the seat that owns the stream. Session
   tags are labels (`tag:<name>`), not part of the stream.
4. A kind whose registry `carrier` is `body` carries a body reference and no
   inline payload; every other kind carries a payload. **(gate)**
5. Every string in a kind payload has a maximum length and every array a
   maximum item count, so one entry's size is bounded. **(gate)**
6. The revision digest is sha256 over the RFC 8785 (JCS) bytes of the whole
   entry, prefixed `sha256:`. `digest-vectors.json` pins expected values that
   every implementation must reproduce, including a vector with non-ASCII
   member values. **(gate)**
7. Store-assigned values (row id, store time, idempotency key, current or
   retired status) stay outside the entry and outside the digest. Authored
   times belong in the payload.

## Revision rules

1. `revision_policy: single` kinds are written at revision 1 only. A
   correction is a new entry that links to the old one. **(gate)**
2. `revision_policy: revisioned` kinds supersede by `record_id`; each
   revision names the immediately previous revision **(gate)** and its
   digest. A stale `supersedes` is a revision conflict and is never
   merged. **(gate, pairs)**
3. A revision keeps its predecessor's `stream`, `record_id`, and
   `payload_contract`. A revision cannot change an entry's kind, so an agent
   cannot supersede a maintainer-class entry through another kind.
   **(gate, pairs)**
4. Every write carries an idempotency key scoped to the stream. A repeat with
   the same digest returns the original outcome; a repeat with a different
   digest is an idempotency conflict.
5. Withdrawing an entry marks it retired. Retired entries keep their history
   and are skipped by current reads; nothing is deleted or rewritten.
6. The legacy checkpoint lane keeps its own hash chain. Its stored values are
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
4. `provenance.actor` for an agent is the writing seat as `<role>.<scope>`.
   Agent-class kinds are written only into the stream equal to the actor.
   **(gate)**
5. The one exception is a handoff acknowledgement. A revision above 1 of a
   handoff may be written by the seat named in `payload.to`, and only with
   `state: acknowledged`. **(gate)** Every acknowledgement, whoever writes it,
   holds the predecessor rules below. A handoff in state `acknowledged` is
   always a revision above 1 written by the seat named in `payload.to`, in
   the sender's stream; a seat never acknowledges a handoff in its own
   stream, even one that names itself. **(gate)** `acknowledged_at` is set
   only by an acknowledgement and never changes afterwards, so the owner can
   close an acknowledged handoff but cannot forge or move its
   acknowledgement. **(gate, pairs)** A new handoff (revision 1) is `open` and
   carries no `acknowledged_at`. **(gate)** Once acknowledged, a handoff keeps its recipient, content, classification, labels, and links; later revisions change only its state. `provenance` is not frozen: it
   describes who wrote each revision, so a closing revision records its own
   writer.
   **(gate, pairs)** Relative to the revision it supersedes,
   the predecessor is `open`, and the acknowledgement keeps
   `classification`, `labels`, `links`, and every payload member other than
   `state` and `acknowledged_at`. **(gate, pairs)**
6. An identity entry's `agent.role` and `agent.scope` equal its stream.
   **(gate)**
7. `attestation: required` kinds need a verified attestation session
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
5. An entry carries sensitivity, not access tier. The tier a reader needs is
   the higher of the kind's registry tier and the floor for the entry's
   sensitivity, so raising an entry's sensitivity raises the tier needed to
   read it. **(gate)** Readers do not serve an entry above the reading seat's
   tier. `wake` and `recall` renders take the strictest classification of
   the entries they include.
6. Volatility describes how often a kind changes within a stream. It is set
   in the registry, never on an entry.

## Input rules

1. Entries are I-JSON: unique member names, well-formed Unicode, and numbers
   exact in IEEE 754 binary64. Numbers are checked from their decimal text,
   before any conversion, so a value that would round is rejected. An
   integral value is an integer however it is written (`2`, `2.0`, `2e0`).
   Revisions are integers from 1 to 2^53 − 1, the range every JSON peer
   holds exactly. **(gate)** An entry
   that cannot be canonicalized is rejected. **(gate)**
2. No string anywhere in an entry, envelope included, contains a control
   character (U+0000–U+001F, U+007F) or a line or paragraph separator.
   Inherited durable-record patterns end in `$`, which some regex engines let
   match before a trailing newline; this rule closes that gap for every
   engine. **(gate)**
3. Every `format` is asserted. `date-time` is RFC 3339 with an offset in
   range, clock fields within 00–23:00–59:00–59, at most six fractional-second
   digits, and no leap second, so every
   reader parses the same instant and stored instants stay totally ordered,
   `date` is an RFC 3339 full-date. `uri` holds schema identifiers, so it is
   held to the RFC 3986 subset they use: `https`, a registered host, an
   optional numeric port, and an absolute path, with no userinfo, query, or
   fragment. Dimension definitions are
   checked with the same formats. A schema that uses
   a format the gate has no checker for fails the gate. **(gate)**
4. A `week` names an ISO week that exists in its year: week 53 only in years
   that have one. **(gate)**

## Goal rules

Week `goals` and `commitments`, and day `plan`, `outcomes`, and
`carry_over`, hold goal items (`kinds/common/goal-item.schema.json`). An item
is plain text or a goal object; plain text stays valid on its own.

1. A goal object needs an `outcome`. `status` and `priority` use the
   contract: project-work/v0 values, so a goal can become a ready packet
   without translation. **(gate)**
2. Order: each item's sort key is its effective rank, then its list index.
   The effective rank is the item's `rank`, or its list index when it has
   none, so plain-text items sort by position. Lower rank sorts first. An
   unordered set is goal objects that share one rank. `priority` (`p0`
   most urgent) is a separate field and does not change order.
3. `rank` is a number within ±2^31 that is a multiple of 1/16, so every
   implementation stores and compares it exactly. A writer inserts by
   halving (1.5, 1.25, …) and renumbers the list when no multiple of 1/16
   fits. See ADR-0019. **(gate)**
4. Goal `id`s are unique within an entry. **(gate)**
5. `parent` names the goal a goal serves, as `<record_id>#<goal id>` in the
   same stream, and must resolve to an existing goal. A goal is never its
   own parent **(gate)**, and parent links form a forest: no cycles across
   entries. **(gate, parents)**
6. Stored weeks are ISO 8601 (Monday start). A reader that shows weeks
   another way converts at display time using the `week-start` dimension;
   stored values never change.

## Rendering rules

1. `wake` renders a bounded summary: at most 30 lines and 2 KiB. Field caps
   bound each entry; the renderer truncates in a fixed order to stay within
   the total.

## Content rules

1. No payload carries a secret value. At any depth, a member name that fails
   `common/v0/secret-keys.schema.json#/$defs/memberName` or matches
   `secretShapedName`, and a string value that matches
   `credentialShapedValue`, rejects the entry. Values are also checked in the
   envelope (for example a body's `encryption.key_ref`). **(gate)** The value
   check is a
   backstop for recognisable credentials; it cannot prove a string holds no
   secret.
2. A credential reference names where a credential lives and how to unlock
   it. Its `locator` must be a reference in its store's format, and
   `recipient` a public key or a name. It never holds the credential.
   **(gate)**
3. A blob body is capped by the registry's `max_body_bytes` and limited to
   its `body_media_types`. **(gate)** Blobs are excluded from `wake`,
   `export`, and `seed`.
4. A reference is a pointer with a content digest. It never copies the
   referenced document.
