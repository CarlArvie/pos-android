# 06 POS Mobile UX and Low-End Adaptation

Contents: primary loop, layout, feedback, states, text, adaptive quality.

## Primary loop
Find item -> add -> adjust -> pay -> receipt. Optimize this loop before anything else.
- Add item: 1 tap from the grid. Tap again = quantity +1. Long-press or tap the cart line = quantity keypad.
- Barcode scan: focus jumps to the cart after a successful scan; no confirmation dialog.
- Exact-cash checkout in <= 3 taps. Quick-cash chips (exact, next 100, next 500, next 1000) plus a keypad.
- Repeat customers and frequent items reachable without search (favorites/recents).

## Layout for one hand, in bright light
- Primary actions in the bottom third. Persistent cart bar at the bottom: item count, total, **Charge** button.
- Touch targets >= 48x48 dp with >= 8 dp gaps. Money buttons larger than that.
- Custom numeric keypad for amounts/quantities. No system keyboard for numbers; it avoids inset relayout and saves taps.
- Contrast >= 4.5:1 body text (stores and outdoor stalls are bright). Body >= 14 sp, prices >= 16 sp. Tabular figures for money columns: `FontFeature.tabularFigures()`.
- Test at text scale 1.3 without overflow. Use `Flexible`, `maxLines`, ellipsis.

## Feedback and speed perception
- Optimistic UI: write to Drift, update immediately, sync later. Local operations never show a spinner.
- Pressed state within 100 ms. Light haptic on add and charge only. No sounds by default.
- Skeleton or flat color placeholders only for remote images. Text content renders from local data at once.
- Do not block the screen with modal dialogs for sync problems. Show a small persistent status chip: "Offline", "3 pending", "Synced".

## States and errors
- Empty state has one clear next action ("Add your first product").
- Errors are inline and actionable ("Only 2 left. Add anyway?"). Never lose the cart on back navigation or a failed sync.
- Destructive actions (void sale, delete item): snackbar with Undo where reversible; a confirm dialog only where not.
- Navigation depth <= 3 from the sales screen. Preserve scroll position and search text when returning to the product grid.

## Money display
- Convert integer minor units to text at the edge. A hand-rolled formatter is fine and free. Cache any formatter instance; never build one inside `build()`.
- `intl` is not in `pubspec.yaml`. Ask before adding it.
- Verify the currency glyph (for example the peso sign) renders on the reference device's default font.

## Adaptive quality for low-end devices (plan item; needs approval)
Detect slowness at runtime with frame timings, then degrade non-essential visuals. No new dependency.
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class PerfTier extends ValueNotifier<bool> {           // true = low tier
  PerfTier() : super(false) {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }
  final _spans = <int>[];
  int _skipped = 0;

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      if (_skipped < 60) { _skipped++; continue; }      // ignore warm-up frames
      _spans.add(t.totalSpan.inMicroseconds);
    }
    if (_spans.length < 120 || value) return;            // latch: once low, stay low
    final sorted = [..._spans]..sort();
    final p75 = sorted[(sorted.length * 0.75).floor()];
    _spans.clear();
    if (p75 > 20000) value = true;                       // p75 frame > 20 ms
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}
```
When `value == true`: disable non-essential animations, drop shadows to borders, use `NoSplash`, reduce `ImageCache` limits, use fade-only page transitions. Log how often it triggers in the sampled diagnostics (see `05-sync-scale.md`). Keep the low tier fully functional; only visuals degrade.
