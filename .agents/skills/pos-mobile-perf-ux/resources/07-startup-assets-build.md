# 07 Startup, Assets, Memory, Build

Contents: startup, images, memory, dependencies, build and Android config.

## Startup
- `main()`: `WidgetsFlutterBinding.ensureInitialized()`, then `runApp` as early as possible. Do only what the first screen strictly needs before it.
- Open Drift lazily in a background isolate. Read `shared_preferences` once, cache the instance; prefer the newer `SharedPreferencesAsync`/`SharedPreferencesWithCache` APIs if the installed version has them.
- `Supabase.initialize` must complete before `Supabase.instance` is used. If the first screen can render from local data, start it after the first frame (`addPostFrameCallback`). Do not break the auth gate: verify sign-in restore still works.
- No heavy top-level or static initializers. No synchronous file I/O on the main isolate at startup.
- Launch theme: set the Android launch background to the app's background color so there is no white flash. Zero dependency (edit `styles.xml` / `launch_background.xml`). A splash package is optional and needs approval.
- Measure with S1 in `01-measure.md`; report the number, not the feeling.

## Images (biggest memory lever)
- Decode at display size: `Image.file(f, cacheWidth: (logicalW * dpr).round())` (or `cacheHeight`), or wrap the provider in `ResizeImage`. Never decode a 12 MP photo for a 96 dp thumbnail.
- `image_picker`: always pass `maxWidth`, `maxHeight` (for example 1024) and `imageQuality` (for example 80) at pick time. Generate and store a ~200 px thumbnail for grids.
- Cap the cache at startup, tuned per device tier: `PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20;` and `maximumSize = 100;`.
- `Image.network` has no disk cache. Prefer local thumbnails. Adding a cache package needs approval. If Supabase Storage image transformations are enabled on the plan, request resized variants instead of originals; confirm plan support in current docs.
- `gaplessPlayback: true` when swapping images to avoid flicker. Provide `errorBuilder` and a flat-color placeholder.

## Memory
- Dispose every controller, `AnimationController`, `ScrollController`, `TextEditingController`, `FocusNode`, timer, and stream subscription. Leaks show up in S8.
- Do not hold full row lists for screens that show one page. Page results.
- Look for growth between iteration 1 and 100 of the cart cycle with the DevTools Memory diff. Fix the retained-object chain, not the symptom.
- Cancel timers and pause sync when the app goes to the background.

## Dependencies
- `excel`: heavy and memory-hungry. Only in an isolate. Prefer CSV for large exports.
- `permission_handler`: request permissions at the point of use, not at startup. Pinned at `11.4.0`; leave it.
- `share_plus`, `http`: fine; do not add duplicates. Check whether `http` is redundant with `supabase_flutter` before adding more HTTP code.
- Before proposing any new package, check its transitive size with `flutter build apk --analyze-size` before/after.

## Build and Android config (inspect first, change only with evidence)
```
flutter build apk --release --split-per-abi --split-debug-info=build/symbols
flutter build appbundle --release --split-debug-info=build/symbols
flutter build apk --analyze-size --target-platform android-arm64
```
- Keep `armeabi-v7a` in the ABI set. Many 2 GB devices run a 32-bit userspace. Dropping it silently excludes your target hardware.
- Verify the release build type shrinks code and resources (`isMinifyEnabled`, `isShrinkResources`). Enable if absent, then test the release build thoroughly.
- Keep `minSdk` as low as the app genuinely supports. Do not raise it for convenience.
- Store `build/symbols` for crash de-obfuscation. Do not commit it.
- Do not add `android:largeHeap`. It hides memory problems and hurts low-RAM devices.
- Renderer flags: see `02-rendering.md`. Change only with A/B device data.
- Always finish with a `--release` run on the reference device: launch, sale, sync.
