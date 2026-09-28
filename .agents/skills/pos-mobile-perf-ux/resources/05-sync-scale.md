# 05 Sync, Supabase, Concurrency

Contents: load model, client sync rules, reconnect storms, realtime, server-side review, load test, observability.

## Reality check
Thousands of concurrent users is decided mostly on the server and by request patterns. The app's job: send **few, small, batched, idempotent, jittered** requests, and never make the UI wait for them. Prove capacity with a load test on staging. Do not quote user-count capacity from reasoning alone.

## Load model (do this first)
Ask for: devices D, peak sales per device per minute s, average items per sale i, sync interval.
- Sales per second = D x s / 60.
- Requests per sale, naive (insert sale + i item inserts + i stock updates) = 1 + 2i.
- Requests per sale, batched RPC = 1 (or 1 per batch of many sales).
- Example: D = 3,000, s = 1, i = 5 -> 50 sales/s. Naive = 550 requests/s. Batched RPC = 50/s or far less. Count the real requests per sale in the code (`Supabase.instance`, `.from(`, `.rpc(`, `http.`) and report the number.

## Client sync rules
- **Outbox**: table `sync_outbox` (id UUIDv7, entity, op, payload JSON, created_at, attempts, next_attempt_at, status). Write local rows and the outbox row in the same Drift transaction.
- **Push in batches** (50-200 operations) through one Supabase RPC. The server function applies them in one transaction and is **idempotent** on the client-generated id (`ON CONFLICT DO NOTHING` or upsert). Retrying must never duplicate a sale or double-deduct stock.
- **Pull deltas**, not tables: `updated_at > cursor`, cursor stored locally, page with `.range()` or keyset. `updated_at` must be set by a server trigger (device clocks lie). Deletes are soft (tombstone column) so deltas can carry them.
- **Select explicit columns.** No `.select()` / `.select('*')` on large tables.
- **Backoff with full jitter**: `delay = random(0, min(cap, base * 2^attempt))`, base 2 s, cap 5 min. Retry on network errors, 5xx, 429. Do not retry 4xx validation errors; mark the row failed and surface it in the UI.
- **Do not read the session over the network per call.** Use the local `currentSession`/`currentUser`; `auth.getUser()` is a server call.
- **Payloads**: no base64 images in rows. Upload compressed images to Storage; store the path.
- Cancel timers and sync loops when the app is paused; resume on `AppLifecycleState.resumed`.

## Reconnect and resume storms
Thousands of devices reconnecting at once (network outage ends, store opens at 9:00) create synchronized spikes.
- On reconnect/resume, wait `random(0-30 s)` before bulk pull; push queued sales first because they are small and valuable.
- Periodic sync interval = base +/- 20% random. No fixed wall-clock alignment (:00, :30).
- Limit concurrency to one sync loop per device.

## Realtime
Supabase Realtime has connection and message quotas that vary by plan. Check current Supabase docs for the numbers; do not quote from memory. Rules:
- Do not subscribe every device to high-write tables (sales, stock movements).
- Use it only for low-volume, high-value channels (menu/price change notice), or replace it with pull-on-resume plus a push notification.
- Unsubscribe when the screen or app is inactive.

## Server-side review (when SQL/migrations are in the repo; otherwise list as recommendations)
- RLS: write `(select auth.uid())` instead of bare `auth.uid()` so it evaluates once per statement. Index every column used in policies (`store_id`, `user_id`). Avoid per-row subqueries in policies; use a stable helper function.
- Index foreign keys and filter columns. Use `EXPLAIN (ANALYZE, BUFFERS)` on hot queries and the dashboard's Query Performance report.
- Append-only, time-based tables (sales, stock movements): consider monthly partitioning or a BRIN index on `created_at`.
- No heavy per-row triggers on hot inserts. No `count(*)` on big tables in hot paths.
- Multi-row business operations live in RPC functions, not in N client round-trips.
- Pooling: PostgREST already pools. If Edge Functions or servers connect directly to Postgres, use the pooler in transaction mode.

## Load test (staging only)
- Create a **staging** Supabase project from the production schema with synthetic data. Never point tests at production. Never use real customer data. Warn the user that heavy tests can hit plan limits.
- Use one distinct test user (JWT) per virtual device; RLS cost depends on realistic identities.
- Ramp 100 -> 1,000 -> 3,000 virtual devices with the real sync pattern (push batches, delta pulls, jitter).
- Watch p95 latency, error rate, DB CPU, connection count, replication/queue lag. Record the load level where p95 or error rate breaks budget; that is the measured limit for that compute tier.
- Do not run it yourself without an explicit go-ahead and a staging URL. Keys come from environment variables, never from committed files.

Skeleton `loadtest/k6-sync.js` (k6):
```js
import http from 'k6/http';
import { check, sleep } from 'k6';
export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 1000 },
    { duration: '5m', target: 3000 },
    { duration: '2m', target: 0 },
  ],
  thresholds: { http_req_failed: ['rate<0.01'], http_req_duration: ['p(95)<800'] },
};
export default function () {
  const res = http.post(
    `${__ENV.SUPABASE_URL}/rest/v1/rpc/apply_sale_batch`,
    JSON.stringify({ ops: [] }), // replace with a realistic batch
    { headers: { 'Content-Type': 'application/json', apikey: __ENV.SUPABASE_ANON_KEY,
                 Authorization: `Bearer ${__ENV.TEST_USER_JWT}` } });
  check(res, { ok: (r) => r.status === 200 });
  sleep(60 + Math.random() * 10);
}
```
Adapt the RPC name and payload to the project's real function.

## Observability (you are blind without it)
No crash reporting exists in `pubspec.yaml`. With thousands of devices you cannot fix what you cannot see. Ask the user to choose: a crash/perf SDK (dependency cost) or a minimal zero-dependency option: sampled (1-5% of sessions), batched diagnostics rows to a Supabase table with app version, device model, RAM class, jank counters, sync failures, and outbox depth. Never log customer data or payment details.
