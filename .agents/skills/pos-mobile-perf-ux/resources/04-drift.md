# 04 Drift and SQLite

Contents: connection setup, indexes, search, pagination, aggregation, writes, streams, migrations, IDs and money.

## Verify before proposing
Check the actual Drift/SQLite setup in the code. Confirm which SQLite build is bundled before proposing FTS5 or other extensions. Read the current Drift docs for APIs you are not certain of; do not guess signatures.

## Connection
- Open with `NativeDatabase.createInBackground(file, setup: (rawDb) { ... })` so SQLite runs off the UI isolate. Open lazily; do not block `runApp` on it.
- In `setup`: `PRAGMA journal_mode = WAL;`, `PRAGMA foreign_keys = ON;`, `PRAGMA busy_timeout = 5000;`, `PRAGMA temp_store = MEMORY;`, `PRAGMA cache_size = -8000;` (8 MB; negative means KiB). Do not set `mmap_size` on low-end devices.
- **Leave `synchronous` at its default (FULL).** `NORMAL` with WAL is faster but a power loss can drop the most recent committed sale. For a POS that is a business decision, not an optimization. Change only with explicit user sign-off.
- Run `PRAGMA optimize;` when the app is backgrounded or on a periodic maintenance tick. Run `ANALYZE;` after large imports. Do not `VACUUM` on the hot path.

## Indexes
- Every column in a hot `WHERE`, `ORDER BY`, or `JOIN` on a table > 1k rows needs a justified index. Composite index order = equality columns first, then range/order column.
- Typical set: `sales(store_id, created_at)`, `sale_items(sale_id)`, `products(barcode)` unique, `products(name_search)`, `sync_outbox(status, next_attempt_at)`, plus `updated_at` where delta sync reads.
- Declare with `@TableIndex(name: ..., columns: {#col})` (check current Drift docs for composite/unique syntax).
- Each index slows writes and grows the file. Do not index speculatively; the checkout insert path must stay fast.
- Prove with the query plan: `EXPLAIN QUERY PLAN <sql>` through `customSelect`. `SCAN` on a large table in a hot path is a finding; `SEARCH ... USING INDEX` is the goal.

## Search
- `LIKE '%term%'` cannot use an index and scans the table. Measure first (scenario S3). If it exceeds the budget:
  1. Add a normalized `name_search` column (lowercase, accents stripped), indexed, and query `name_search >= ? AND name_search < ?` for prefix matches; or
  2. Use FTS5 if the bundled SQLite supports it (verify), kept in sync in the same transaction.
- Always `LIMIT` (30-50). Debounce input (see `03-state-isolates.md`).

## Pagination
- No `OFFSET` on large tables. Use keyset: `WHERE (created_at, id) < (?, ?) ORDER BY created_at DESC, id DESC LIMIT 50`.
- Sales history, reports, and audit logs must page. Never load all rows to the UI.

## Aggregation
- Compute `SUM`, `COUNT`, `GROUP BY` in SQL over an indexed date range. Never loop rows in Dart to total them.
- If dashboards are still slow, propose (as a plan item, not a silent change) a daily-summary table updated inside the same transaction as the sale. It adds write cost and correctness risk; justify with a measured S6.

## Writes
- One sale = one `transaction()` that writes sale, items, stock movement, payment, and the outbox row together. All or nothing.
- Multi-row inserts use `batch()`. No `await` inside per-row loops when a batch works.
- Never perform network calls or long computation inside a transaction.

## Streams
- Assume every write to a watched table re-runs the query and re-emits (verify by counting emissions). Keep watched queries narrow, limited, and consumed by one leaf widget.
- Do not `.watch()` big joins on the checkout screen. Prefer a one-shot `get()` plus manual refresh on known events.

## Migrations
- Bump `schemaVersion`; write an additive `onUpgrade` step (`addColumn`, `createIndex`, `createTable`). Never drop columns or tables that hold sales, payments, or stock history.
- Test upgrading a database created by the previous release, with realistic data volume, before merging.
- Regenerate: `dart run build_runner build --delete-conflicting-outputs`.

## IDs and money
- Money: integer minor units (centavos). Convert at the UI edge only. Flag every `double` price/total.
- IDs created on device: prefer time-ordered UUIDv7 (`Uuid().v7()` in the `uuid` package) for new tables. Random UUIDv4 primary keys fragment indexes in SQLite and Postgres. Do not rewrite existing IDs.
