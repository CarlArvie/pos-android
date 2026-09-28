---
name: pos-mobile-perf-ux
description: Audits and optimizes performance, UX and scalability of the Flutter POS mobile app (Drift local database, Supabase sync) so it runs smoothly on low-end Android devices and survives thousands of concurrent users. Use for slow startup, jank, laggy lists or search, slow checkout, high memory or APK size, poor mobile POS ergonomics, offline and sync behavior, and load readiness, either app-wide or one feature at a time (for example inventory). Not for building new features.
---

# POS Mobile Performance, UX and Scale

## 1. What this skill can and cannot do
- **Can:** cut per-device cost (CPU, memory, frames, battery, requests per sale) and make the UI fast and thumb-friendly on weak hardware.
- **Cannot:** make the backend serve thousands of concurrent users by itself. That is decided by Supabase compute tier, schema, indexes, RLS and the sync pattern. This skill reduces per-device load and forces a staging load test. Never write "supports N users" without a load-test result.
- **Cannot:** prove low-end performance from emulators. See evidence tiers in the always-on rule and `resources/01-measure.md`.

## 2. Modes
- **Feature mode (default when the user names a feature):** run `/optimize-feature <feature> [aspects]`. Read `resources/09-feature-scope-tests.md` first. Work only inside the feature slice. Aspects: `ui`, `logic`, `db`, `sync`. Default = `ui logic db`; `sync` findings are report-only unless the user asks.
- **App mode:** `/perf-audit` for a ranked, read-only audit of the whole app.
- In feature mode do NOT re-run the full intake. Use defaults from the rule file. Ask only if the slice boundary is ambiguous.

## 3. Operating procedure
Follow the phases in order.

### Phase 0: Safety and scope
- Git branch `perf/<feature>`, clean working tree. Slice map printed. Scope lock active (see `resources/09-feature-scope-tests.md`).

### Phase 1: Lock behavior, then baseline
- Run the existing `flutter test` for the slice. Where the logic you may change has no test, write **characterization tests** that pass on the current code first (`resources/09-feature-scope-tests.md`). No logic edits before this.
- Baseline at the highest tier available: `[Verified]` facts first (query plans, query counts, rebuild counts, request counts, static audit hits inside the slice), then `[Measured-emu]` timings on the low-spec emulator (`resources/01-measure.md`).
- Run `dart run .agents/skills/pos-mobile-perf-ux/scripts/audit.dart lib` and keep only hits inside the slice. Run it with `--help` first; do not read the script source.

### Phase 2: Diagnose
- Rank findings by (user-visible impact x confidence) / effort, restricted to the requested aspects. Walk the priority ladder (section 5).
- Out-of-slice findings go to `docs/perf/backlog.md`. Do not fix them now.

### Phase 3: Implement
- One finding per commit: `perf(<feature>): <what> [<tag>]`. Smallest diff that moves the metric. Behavior stays identical.
- After each change: `dart format`, `flutter analyze`, `flutter test` for the slice.
- Stop for approval only on the gate list in the rule file (schema, stock/money semantics, shared files, new dependency, sync protocol, removed APIs).

### Phase 4: Verify
- Re-run the same measurements. Report before/after. Run the FULL `flutter test` and `flutter analyze`.
- A change that does not move its metric is reverted with `git revert`. Complexity without gain is a defect.
- Give the user a short **manual QA checklist** for the two emulators, tailored to the feature (template in `resources/09-feature-scope-tests.md`).

### Phase 5: Report
- Write `docs/perf/YYYY-MM-DD-<feature>.md` from `resources/08-report-template.md`. Update `docs/perf/feature-status.md`. Summarize in chat in 10 lines or fewer, including which evidence tier each result reached and the line "Budgets: unconfirmed (no real device)" unless a real device was used.

## 4. Load only the resource the task needs
| Task | Read |
|---|---|
| Feature slicing, scope lock, git, tests, manual QA | `resources/09-feature-scope-tests.md` |
| Measuring, evidence tiers, emulator setup, scenarios | `resources/01-measure.md` |
| Jank, slow lists or grids, costly widgets, animations | `resources/02-rendering.md` |
| Excess rebuilds, state, isolates, debounce | `resources/03-state-isolates.md` |
| Slow queries, indexes, search, pagination, migrations | `resources/04-drift.md` |
| Sync, Supabase calls, concurrency, load testing, observability | `resources/05-sync-scale.md` |
| Layouts, touch targets, flows, feedback, low-end adaptation | `resources/06-pos-ux.md` |
| Cold start, images, memory, APK size, Android build config | `resources/07-startup-assets-build.md` |
| Writing the deliverable | `resources/08-report-template.md` |
| Automated frame-timing test (needs dev dependencies) | `examples/` |

## 5. Priority ladder (highest return first)
1. Move blocking work off the UI isolate: large JSON decode, `excel`/`csv`, aggregation, image processing.
2. Shrink rebuild scope: granular listeners, `const`, widget classes instead of helper methods.
3. Virtualize: builder lists and slivers, no `shrinkWrap`, no `Intrinsic*`.
4. Images: decode at display size, cap the ImageCache, use thumbnails.
5. Database: indexes for real query plans, SQL aggregation, keyset pagination, short transactions.
6. Network: fewer, batched, idempotent requests; jittered backoff; delta pull.
7. Startup: first frame before non-critical init.
8. Size: dependencies, ABI split, `--split-debug-info`.
9. Polish: animations, shadows, ripples. Only after 1-8.

## 6. Push back (say no, explain, offer the alternative)
- "RepaintBoundary / caching everywhere" -> only where a measurement or rebuild count shows a gain.
- "Migrate all state management to X" -> one feature at a time, only if rebuild data justifies it.
- "Isolate for everything" -> only for work > ~8 ms or payloads > ~50 KB.
- "Loosen `synchronous` / skip fsync for speed" -> can lose the last sale on power loss. Explicit user sign-off only.
- "It is fast on the emulator, so the budget is met" -> no. Emulator timing is relative evidence only.
- "Realtime subscription to sales or stock tables on every device" -> does not scale; see `resources/05-sync-scale.md`.
- "Just upgrade the Supabase plan" -> only after a load test shows where the limit is.
- "Also fix that other screen while you are there" -> scope lock. Add it to the backlog.

## 7. Definition of done (per feature)
- Every claimed improvement carries an evidence tag; no "budget met" without `[Measured-device]`.
- Full `flutter test` and `flutter analyze` pass; no test deleted or weakened.
- Golden path for the feature unchanged, verified by tests and the manual QA checklist, including offline and sync where the feature writes data.
- Report and `docs/perf/feature-status.md` updated; out-of-scope findings recorded in `docs/perf/backlog.md`.
