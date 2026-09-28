# 01 Measure

Contents: rules, emulators, reference device, commands, seeding, scenarios, reading results, evidence tags.

## Rules
- Never debug mode, never web. Use `--profile` for timing and `--release` only for final startup and size sanity checks.
- Same device or AVD, same data, same build mode, same scenario, 3 runs. Report median and worst. Do not discard runs silently.
- Realistic data volume. A test on 20 rows proves nothing.
- Evidence tiers (see the always-on rule): `[Verified]` runs anywhere; `[Measured-emu]` is relative only; `[Measured-device]` is the only tier that can declare a budget met.

## Emulators (current setup: two AVDs)
- Emulators run on the host CPU/GPU, usually far faster than a 2 GB phone, and x86_64 code paths differ from ARM. Emulator absolute times are NOT budget evidence.
- Valid on emulators: relative before/after ratios on the same AVD; and all `[Verified]` facts (query plans, query counts, rebuild counts, request counts, APK size, memory growth trend over 100 cycles).
- Use one AVD as the **low-end proxy**: 2 GB RAM, 2 CPU cores, ~720x1280 at ~280 dpi, API 28-30, x86_64 image. Start it with `emulator -avd <name> -memory 2048 -cores 2` (flags vary by SDK; check `emulator -help`). Keep the second AVD as a modern-config regression check.
- Do not enable software GPU rendering to "simulate slowness". It distorts raster numbers in a different way than a real low-end GPU.
- Profile mode: `flutter run --profile -d <emulator-id>` on an x86_64 image. If it is refused, say so and stay at `[Verified]`.
- Cheapest way to close the gap: run S1-S8 once on any real 2 GB Android phone before release. Until then every budget is "unconfirmed".

## Reference device (real device, when one becomes available)
- Model:
- RAM / Android version / ABI (arm64-v8a or armeabi-v7a):
- Notes (thermal throttling, storage type):

## Commands
```
flutter devices
adb devices
flutter run --profile -d <deviceId> --dart-define=SEED_ROWS=10000
flutter run --profile --trace-startup -d <deviceId>     # writes build/start_up_info.json
adb shell am force-stop <applicationId>                 # forces a true cold start
adb shell dumpsys meminfo <applicationId>               # read TOTAL PSS
flutter build apk --analyze-size --target-platform android-arm64
```
- `applicationId` comes from `android/app/build.gradle(.kts)`.
- Startup number: `timeToFirstFrameRasterizedMicros` in `build/start_up_info.json`.
- DevTools > Performance: read the UI (build) thread and the Raster thread separately. Slow UI = Dart work or rebuild scope. Slow raster = `saveLayer`, clips, shadows, oversized images.
- Turn on "Track widget builds" only while hunting rebuilds; it distorts timings.
- DevTools "Highlight repaints" shows repaint scope. DevTools Memory snapshot diff finds leaks.
- Do not use `adb shell dumpsys gfxinfo` for Flutter frame data. It does not reflect Flutter's own rasterizer.
- Flags change between Flutter releases. If a flag errors, run `flutter run --help` and adapt.

## Seeding
Add a seeder that runs only when `const int.fromEnvironment('SEED_ROWS') > 0`. Guard with the dart-define, not `kDebugMode`, because profile mode is not debug. The default of 0 lets release builds tree-shake it out.
- Products: SEED_ROWS rows, varied names (some 40+ chars), barcodes, categories, ~30% with thumbnails.
- Sales: 5x SEED_ROWS over 12 months, 1-8 items each. Outbox: 500 queued rows.
- Insert with Drift `batch()` inside one transaction. Put the seeder in `lib/dev/seed.dart`.

## Standard scenarios
| ID | Scenario | Metric |
|---|---|---|
| S1 | Force-stop, launch, reach product grid | time to first rasterized frame; time to interactive |
| S2 | Fling product grid up and down 5 times | frame build/raster p95, janky %, worst frame |
| S3 | Type "cola" into search, 10k products | ms from keystroke to results |
| S4 | Tap-add 30 items rapidly | tap-to-feedback, dropped frames |
| S5 | Cash checkout, local commit | ms from Charge tap to receipt visible |
| S6 | Open daily and monthly sales report, 50k sales | ms to first content, UI-thread stall |
| S7 | Go online with 500 queued sales | flush time, requests sent, UI jank during sync |
| S8 | 100 cart -> checkout cycles | PSS start vs end |

## Zero-dependency frame counter (profile builds)
Register `SchedulerBinding.instance.addTimingsCallback` and count frames where `totalSpan > 16 ms` and `> 100 ms`, plus p95 of `buildDuration` and `rasterDuration`. Print at the end of a scenario. Remove or gate behind the dart-define after use.

## Automated frame timing (needs dev dependencies; ask first)
Templates in `examples/`. They need `integration_test` and `flutter_driver` (both from the Flutter SDK) under `dev_dependencies`. Run:
```
flutter drive --driver=test_driver/perf_driver.dart --target=integration_test/scroll_perf_test.dart --profile --no-dds -d <deviceId>
```
Output: `build/scroll_summary.timeline_summary.json` with average, 90th, 99th and worst frame build/raster times and missed-frame counts.

## Evidence tags (use in every finding)
- `[Verified]`: hardware-independent fact (test, query plan, counts, size).
- `[Measured-emu]`: emulator timing; relative comparison only.
- `[Measured-device]`: number from a profile run on a real device.
- `[Inferred]`: follows from code reading or static audit; no number yet.
- `[Assumed]`: plausible but unverified. Never build a plan around `[Assumed]` alone.
