---
name: release-size-check
description: Builds the POS app release APK, analyzes size, and reviews dependencies and Android build config for low-end devices. Use when the user runs /release-size-check or asks about APK size, ABI splits, or release build settings.
---

Run this procedure only when the user invoked /release-size-check or clearly asked for it. Do not start it on your own.

# /release-size-check

1. Activate skill `pos-mobile-perf-ux`. Read `.agents/skills/pos-mobile-perf-ux/resources/07-startup-assets-build.md`.
2. Read `pubspec.yaml`, `android/app/build.gradle(.kts)`, and `android/app/src/main/AndroidManifest.xml`.
3. Run `flutter build apk --analyze-size --target-platform android-arm64` and record the reported size and the analysis file path. Tell the user to open the JSON in DevTools > App Size for the breakdown.
4. Run `flutter build apk --release --split-per-abi --split-debug-info=build/symbols` and list per-ABI sizes.
5. Check config: ABI set includes `armeabi-v7a`; release shrinking (`isMinifyEnabled`, `isShrinkResources`); `minSdk`; no `largeHeap`; launch theme background color.
6. Dependencies: flag heavy or redundant ones (`excel`, duplicate HTTP stacks) with size evidence. For any proposed package, measure size before and after.
7. Compare against the budget in `.agents/rules/pos-flutter-guardrails.md`.
8. Write `docs/perf/YYYY-MM-DD-release-size.md`. Propose changes as a plan; do not change build config without approval.
9. Remind the user to run the release build on the reference device: launch, one sale, one sync.
