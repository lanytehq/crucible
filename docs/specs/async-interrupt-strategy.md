---
title: Async Interrupt Strategy for Agent Harnesses
description: How Lanyte agents receive off-turn signals without a human relaying chat activity.
status: draft
owner: cxotech
---

# Async Interrupt Strategy for Agent Harnesses

## Problem

Harness sessions are turn-bounded. Events that arrive between turns (chat
replies, scheduled follow-ups, supervisor nudges) are invisible until the next
prompt unless the agent polls.

Polling burns tokens, misses activity during long model calls, and still
requires the agent to decide to poll.

## Goal

Agents notice relevant off-turn events through a mechanism that is (1) cheap
in tokens, (2) deterministic about what arrived since the last check, and
(3) consistent enough across harnesses that role conventions can rely on it.

## Options

### Option A — CLI polling between turns

Each harness runs a lightweight chat check between turns using cursor-based
primitives (`check` / `wait` after a post id). Lowest common denominator.
Does not see events during a long model call.

### Option B — Per-harness native hooks

Each harness vendor's hook or notification API. Highest fidelity, highest
per-harness cost.

### Option C — Shared waiter plus optional native hooks

Cursor-based wait is the portable baseline. Harnesses that can attach a native
hook do so as an accelerator, not a second contract.

## Decision

**Option C.** Portable wait/check is the contract. Native hooks are optional.
Absence of a collector or hook means the agent only sees events at turn
boundaries. That is acceptable; chat is coordination, not evidence.

## Non-goals

This spec does not name private planning codes, live server hostnames, or
operator clone paths. Implementation lives in the chat CLI and harness
adapters.
