# 09 Feature Scope, Tests, Git

Contents: invoking, slice discovery, aspects, gates, git protocol, characterization tests, hardware-independent perf tests, manual QA template, status files.

## Invoking
`/optimize-feature inventory` or `/optimize-feature inventory db` or `/optimize-feature inventory ui logic`.
The text after the command is the feature name, then optional aspects. If the agent did not receive it, it asks once.

## Slice discovery
1. Search `lib/` for the feature keyword and obvious synonyms (for inventory: `inventory`, `stock`, `adjust`, `low_stock`) in file paths and identifiers.
2. Print a table of files by layer: **UI** (screens, pages, widgets), **State/logic** (controllers, notifiers, repositories, services), **Data** (Drift tables, DAOs, queries, migrations), **Sync** (outbox writes, `.from(`/`.rpc(` calls), **Tests**.
3. List **shared files**: files outside the slice that import the slice, or that the slice imports and other features also use (common widgets, `database.dart`, theme, utils). Shared files are read-only unless the plan is approved and the full test suite is run afterward.
4. Slice over ~25 files or unclear boundaries: ask the user to confirm once. Otherwise print the map and continue.

## Aspects
| Aspect | Covers | Read |
|---|---|---|
| `ui` | screens, widgets, lists, images, animations, touch targets, feedback, states | 02, 06, 07 (images), 03 (rebuilds) |
| `logic` | controllers/repositories, isolates, debounce, N+1 calls, disposal, async correctness | 03 |
| `db` | Drift tables, indexes, queries, pagination, transactions, streams | 04 |
| `sync` | outbox, batching, backoff, requests per action | 05 (report-only unless asked) |
Default with no aspect given: `ui logic db`.

## Gates: stop and ask before doing any of these
- schema change or migration
- change to stock or money semantics (how quantities or amounts are computed, rounded, deducted)
- edit to a shared file
- new dependency
- sync protocol or RPC change
- removing or changing a public API used outside the slice
Everything else inside the slice proceeds without stopping.

## Git protocol
- `git status` clean first. If dirty, ask the user to commit or stash; do not do it for them.
- `git switch -c perf/<feature>`.
- One commit per finding: `perf(<feature>): <what> [<tag>]`. Test-only commits: `test(<feature>): characterize <behavior>`.
- Undo a bad change with `git revert <hash>`. Never `git reset --hard`, `git clean`, or force-push unless the user explicitly asks.

## Characterization tests (before touching logic)
Goal: pin what the code does today so an optimization cannot silently change it.
- Cover the slice's logic that could change: stock in/out/adjust, oversell handling, low-stock threshold, search results and order, list filters, totals and rounding.
- Use an in-memory Drift database. Adapt class names to the project:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db; // project's database class
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('adjusting stock down by 3 leaves 7', () async {
    // arrange with the project's real DAO/repository API, act, assert
  });
}
```
- If `NativeDatabase.memory()` fails to load SQLite on the host machine, report the exact error and ask the user. Do not add packages to work around it.
- These tests must pass on the unchanged code before any optimization. Commit them first.
- Never delete, skip, or loosen an existing test. A test that must change because behavior changes on purpose is a gate.

## Hardware-independent performance checks (`[Verified]`)
These run anywhere, including on your emulator machine, and do not depend on CPU speed.
1. **Query plan.** For each hot query:
```dart
final plan = await db.customSelect(
  'EXPLAIN QUERY PLAN SELECT * FROM products WHERE barcode = ?',
  variables: [Variable.withString('123')],
).get();
final detail = plan.map((r) => r.read<String>('detail')).join(' | ');
expect(detail, contains('USING INDEX'));
```
Import `package:drift/drift.dart` for `Variable`. Use the real table and column names from the generated SQL.
2. **Query count per user action.** Count statements executed for one action (for example "open inventory list", "adjust stock") using Drift's `QueryInterceptor` (check current Drift docs for the exact API) or `logStatements` output. Assert the count does not exceed the baseline. A list that runs 1 + N queries is an N+1 finding.
3. **Rebuild count.** Put a probe widget that increments a counter in `build()` under the subtree that should NOT rebuild, trigger a state change, assert the counter did not grow. Example:
```dart
int probeBuilds = 0;
class Probe extends StatelessWidget {
  const Probe({super.key});
  @override
  Widget build(BuildContext context) { probeBuilds++; return const SizedBox(); }
}
```
4. **Volume smoke test.** Seed 10,000 rows into the in-memory DB, run the slice's list and search queries, assert correct results and index usage. Print elapsed time; do not assert an absolute time (machines vary).
5. **Request count per action** for `sync` aspect: count `.from(`/`.rpc(` calls in the code path for one user action.

## Manual QA checklist (give to the user after each feature; tailor it)
For the two emulators (use both: low-spec AVD and the modern one):
1. Open the feature screen with 10k seeded rows. Does the list scroll without visible stutter?
2. Search a partial name and a barcode. Are results instant and correct?
3. Create, edit, and delete one item. Do totals and counts update at once?
4. Perform the feature's main write action (for inventory: adjust stock in and out). Is the quantity correct on screen and after restarting the app?
5. Turn on airplane mode, repeat step 4, turn it off. Does the pending count clear and stay correct?
6. Open and close the keyboard, rotate if supported, use text scale 1.3. Any overflow or lost input?
7. Back-navigate and return. Are scroll position and search text preserved?
8. Rapid-tap the primary button 10 times. Any duplicate writes or freeze?

## Status files (create if absent)
- `docs/perf/feature-status.md`: one row per feature: `Feature | Date | Aspects | Branch | Highest evidence tier | Result | Open backlog items`.
- `docs/perf/backlog.md`: one row per parked finding: `Feature/area | File | Finding | Tag | Suggested aspect`. Append only.
