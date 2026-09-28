# 02 Rendering and Widget Cost

Contents: lists, rebuild cost, paint cost, animations, text and layout, review checklist.

## Lists and grids
- Use `ListView.builder`, `GridView.builder`, or `SliverList`/`SliverGrid` with a delegate. Never `ListView(children: [...])` or `GridView.count(children: ...)` for data-driven content.
- Uniform rows: set `itemExtent` or `prototypeItem`. It removes per-item layout measurement.
- Give items `ValueKey(entity.id)` when the list can reorder or change.
- One scroll view per screen: a `CustomScrollView` with slivers. Never `ListView(shrinkWrap: true)` inside a `Column` inside a `SingleChildScrollView`; that builds every item.
- `itemBuilder` must be cheap: no sorting, formatting loops, or DB calls. Precompute display strings in the view-model or query.
- Lists with simple rows and no state: `addAutomaticKeepAlives: false`. Keep the default `addRepaintBoundaries: true`.
- Product grid: fixed `childAspectRatio` and cell sizes. No `IntrinsicHeight` to equalize cells.

## Rebuild cost
- Use `const` constructors everywhere they compile. Suggested lints (ask before editing `analysis_options.yaml`): `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, `prefer_const_declarations`, `use_key_in_widget_constructors`, `sized_box_for_whitespace`, `avoid_unnecessary_containers`.
- Split big `build()` methods into small **widget classes**, not helper methods returning `Widget`. A class can be skipped by the framework when its inputs are unchanged; a method is rebuilt every time.
- Read the narrow MediaQuery value: `MediaQuery.sizeOf(context)`, `paddingOf`, `viewInsetsOf`, `textScalerOf`, `disableAnimationsOf`. `MediaQuery.of(context)` rebuilds on any change, including the keyboard opening.
- Do not create `Future`/`Stream`/controllers/formatters inside `build()`. Create once in `initState`, a controller, or a provider.
- Hoist `Theme.of(context)` into a local variable once per build.

## Paint cost (raster thread; hurts low-end GPUs most)
- Avoid `Opacity` (can force `saveLayer`). Use `FadeTransition`/`AnimatedOpacity`, or put alpha in the color.
- Avoid `BackdropFilter`, `ShaderMask`, `ColorFiltered`, and `Clip.antiAliasWithSaveLayer`.
- Clips: prefer `BoxDecoration(borderRadius: ...)` over `ClipRRect`. When a clip is required use `Clip.hardEdge` or default `antiAlias`.
- Shadows: large blurred `BoxShadow` and elevated `Card` repeated per list item are expensive. In lists use `Card(elevation: 0)` plus a 1 px border.
- `RepaintBoundary`: add only around small subtrees that repaint independently of their parent (cart badge, pulsing button, scan overlay). Confirm with "Highlight repaints". Each boundary costs memory.
- Impeller is the default renderer on current Flutter. If a specific low-end GPU shows raster glitches, A/B test with `--no-enable-impeller` on that device and decide from numbers. Do not ship a renderer change without device data.
- Material ripple: on Android, Material 3 can default to `InkSparkle`, a shader-based splash. On low-end devices set `splashFactory: InkRipple.splashFactory` (or `NoSplash.splashFactory` inside dense lists) in `ThemeData`.

## Animations
- Keep durations <= 200 ms. Animate transform and opacity only. Never animate size/padding/layout inside list items.
- `AnimatedBuilder`/`ListenableBuilder`: pass static subtree via `child:` so it is not rebuilt per tick.
- No `AnimatedSwitcher` or `Hero` inside list items. Respect `MediaQuery.disableAnimationsOf(context)`.
- Dispose every `AnimationController`. Use `SingleTickerProviderStateMixin` for one, `TickerProviderStateMixin` for several.

## Text and layout
- Set `maxLines` and `overflow: TextOverflow.ellipsis` on product names and list text.
- Avoid `Text.rich` and `FittedBox` in per-item widgets unless required.
- Avoid `IntrinsicHeight`/`IntrinsicWidth` (extra layout pass; quadratic when nested). Use fixed heights or `Table` with fixed column widths.
- Avoid `LayoutBuilder` per item. Avoid `Wrap` with more than ~50 children; use slivers.
- One font family, at most 3 weights. The default system font costs zero bytes and zero load time.

## Review checklist (run per screen)
- [ ] Any non-builder list over ~20 items?
- [ ] Any `shrinkWrap: true`, `Intrinsic*`, `Opacity`, `BackdropFilter`, big shadows?
- [ ] Does `setState` sit high in a screen-level State?
- [ ] Any future/stream/controller created in `build()`?
- [ ] Any `MediaQuery.of(context)`?
- [ ] Image decode size set? (see `07-startup-assets-build.md`)
- [ ] Controllers, subscriptions, timers disposed?
