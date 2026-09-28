# 03 State, Rebuilds, Isolates

Contents: current state situation, zero-dependency pattern, rules, isolates, debounce.

## Situation
`pubspec.yaml` has no state-management package. Assume `setState` and manual wiring until code reading proves otherwise. Do not introduce Riverpod, Bloc, Provider or GetX on your own. If rebuild data justifies one, propose it as a plan item with cost and a per-feature migration path.

## Zero-dependency pattern (default)
- One controller per feature (`CartController`, `ProductSearchController`) extending `ChangeNotifier`. Created once, provided with an `InheritedWidget`/`InheritedNotifier` or passed through constructors. Disposed by its owner.
- Expose **granular** listenables: `ValueNotifier<int> itemCount`, `ValueNotifier<int> totalMinor`, and per-line notifiers. The cart badge listens to `itemCount` only; the total bar to `totalMinor` only.
- Listen with `ListenableBuilder`/`ValueListenableBuilder`, always passing static content via `child:`.
- Update a notifier only when the value actually changed (`if (v == value) return;`). Batch multi-field updates into one `notifyListeners()`.
- `setState` only for ephemeral state inside a leaf widget (focus, toggle, tab index). Never in a State that owns a whole screen's tree.
- Drift streams: subscribe in the controller (or a `StreamBuilder` around the smallest widget), cancel in `dispose`. Never call `.watch()` inside `build()`.
- After every `await` in a State, check `if (!mounted) return;` before using `context`.

## Isolates
Move work off the UI isolate when it exceeds ~8 ms or the payload exceeds ~50 KB:
- `jsonDecode` of large sync payloads
- `excel` parse/export, `csv` parse/export
- report aggregation that cannot be expressed in SQL
- image resize/compress (or use `image_picker`'s `maxWidth`, `maxHeight`, `imageQuality` and skip the work)

Use `Isolate.run(() => ...)` for one-shot jobs. Rules:
- Send only sendable data (primitives, lists, maps, typed data). A closure that captures `this`, a `BuildContext`, or a widget throws at runtime. Build plain input objects first.
- Spawning costs milliseconds. Never wrap microwork. For frequent calls keep one long-lived worker isolate.
- Platform channels inside a background isolate need `BackgroundIsolateBinaryMessenger.ensureInitialized(RootIsolateToken.instance!)`, and the token must be captured on the main isolate and passed in.
- Drift already runs SQLite in a background isolate when opened with `NativeDatabase.createInBackground` (see `04-drift.md`). Do not wrap Drift calls in another isolate.
- Large exports: prefer streaming CSV to a file over building a huge `excel` workbook in memory. Above ~10k rows use CSV.

## Debounce
Search input: 250 ms `Timer` debounce, cancel the previous timer on each keystroke, cancel on `dispose`. Cancel or ignore stale results: keep a request counter and drop results whose counter is old.

## Anti-patterns to flag
- `setState(() {})` called from a stream listener on a big screen State.
- A `ChangeNotifier` that notifies inside loops.
- Rebuilding the whole checkout screen because one quantity changed.
- Holding full Drift row lists in memory for screens that show 20 rows.
