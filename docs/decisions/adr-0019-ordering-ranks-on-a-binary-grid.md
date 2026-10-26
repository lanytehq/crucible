---
title: ADR-0019 Ordering Ranks on a Binary Grid
description: Ordering ranks in Lanyte contracts are multiples of 1/16 so every implementation compares them exactly
---

# ADR-0019: Ordering Ranks on a Binary Grid

## Status

Proposed

## Context

Ordered lists in Lanyte contracts (first: goal items in `agentic/content/v0`
week and day entries) carry an optional numeric `rank`. Lower rank sorts
first. Writers need to insert an item between two others without
renumbering the whole list, which calls for fractional ranks.

JSON numbers are IEEE 754 binary64 in practice. Python, ECMAScript, and
Rust all read them that way, and RFC 8785 canonicalization (used for
revision digests) serializes them that way. Most short decimals have no
exact binary64 value: `0.1`, `1.1`, and `0.0001` are each stored as the
nearest binary fraction. A rule written in decimal places ("at most four")
therefore fails in two directions:

- Checked against the stored binary64 value, it accepts long spellings that
  round to a four-place value. The exact binary64 value of `0.1` written in
  full (`0.1000000000000000055511151231257827021181583404541015625`) passes
  a "rounds to itself at four places" test, and canonicalization then
  rewrites it as `0.1`.
- Checked exactly, it rejects most values a person would write, because
  `1.1` is not exactly representable, and so does not truly have one
  decimal place.

Checking the original decimal text instead would need decimal arithmetic in
every consumer and would still let peers disagree when they compare the
stored binary64 values.

## Options Considered

### Option A: decimal places on the number text

- Pros: Matches how people write numbers (`1.1`, `2.25`).
- Cons: Every consumer needs decimal parsing; stored values are still
  binary64, so equality and ordering at the edges can differ by language.

### Option B: integer ranks only

- Pros: Exact everywhere; trivial to check.
- Cons: Inserting between adjacent integers forces a renumber; writers have
  to leave gaps (10, 20, 30) by convention.

### Option C: multiples of 1/16 (chosen)

- Pros: Every allowed value is exact in binary64, so every language stores,
  compares, sorts, and canonicalizes it identically. The check is integer
  arithmetic: `rank × 16` is an integer. Between two adjacent integers a
  writer can insert by halving (1.5, 1.25, 1.125, 1.0625): fifteen
  positions before a renumber.
- Cons: Values such as `1.1` are not allowed; writers use `1.125` or
  renumber.

## Decision

A `rank` is a number within ±2³¹ that is a multiple of 1/16. Lower rank
sorts first. When a writer needs a position between two ranks and no
multiple of 1/16 fits, it renumbers the list rather than adding precision.

Sort key for a list: each item's effective rank (its `rank`, or its list
index when it has none), then its list index. Plain-text items have no
rank and sort by index. An unordered set is goal objects that share one
rank.

## Consequences

- Positive: Ordering is exact and identical across Python, ECMAScript, and
  Rust; revision digests never shift because a rank was rewritten during
  canonicalization.
- Positive: The rule is reusable for any ordered list in a Lanyte contract.
- Negative: Writers cannot use arbitrary decimals; tooling that suggests
  an insert position should pick the midpoint and renumber when the
  midpoint is not a multiple of 1/16.
