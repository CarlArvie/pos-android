---
name: db-sync-review
description: Reviews the POS app Drift schema, indexes, queries, sync outbox, Supabase call patterns and load readiness. Use when the user runs /db-sync-review or asks about slow queries, sync design, request volume, or capacity for thousands of concurrent users.
---

Run this procedure only when the user invoked /db-sync-review or clearly asked for it. Do not start it on your own.

# /db-sync-review

1. Activate skill `pos-mobile-perf-ux`. Read `.agents/skills/pos-mobile-perf-ux/resources/04-drift.md` and `.agents/skills/pos-mobile-perf-ux/resources/05-sync-scale.md`.
2. Ask for peak load numbers if unknown: devices, sales per device per minute, items per sale.
3. Drift review: list tables, columns used in `WHERE`/`ORDER BY`/`JOIN`, existing indexes, `schemaVersion`, PRAGMAs set at open, every `.watch()` query, every transaction. Flag missing indexes, offset pagination, Dart-side aggregation, `LIKE '%..%'` on large tables, and writes outside a transaction.
4. Capture `EXPLAIN QUERY PLAN` for the hot queries (search, list, report, outbox pick) through an in-memory Drift test (see `.agents/skills/pos-mobile-perf-ux/resources/09-feature-scope-tests.md`). These are `[Verified]` and need no device. If that is impossible, mark plan findings `[Inferred]`.
5. Sync review: find the outbox (or its absence). Check idempotency keys, batch size, backoff and jitter, delta cursor, soft deletes, reconnect behavior, and any `Timer.periodic`. Count requests per completed sale.
6. Supabase review: list every `.from(`, `.rpc(`, `.select(`, realtime channel, storage call. Flag `select('*')`, per-item requests, `auth.getUser()` per call, and realtime on high-write tables. If SQL/migrations exist in the repo, check RLS policy form and indexes on policy columns.
7. Compute the load model (`.agents/skills/pos-mobile-perf-ux/resources/05-sync-scale.md`) with naive vs current vs batched request rates.
8. Write findings to `docs/perf/YYYY-MM-DD-db-sync.md` and produce an Implementation Plan. Any schema or sync change needs approval first.
9. Offer to draft `loadtest/k6-sync.js`. Do NOT run it. It must target a staging project only, with keys from environment variables.
