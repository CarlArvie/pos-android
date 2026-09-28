# Feature Performance & UX Report: Inventory

**Date:** 2026-09-28  
**Feature:** Inventory  
**Aspects:** UI, Logic, DB  
**Branch:** `perf/inventory`  
**Budgets:** Unconfirmed (no real device; tested on Android emulators and test suites)

---

## 1. Problem Statement & User Symptoms
- **Navigation Lag & Frame Drops:** Terminal logged Choreographer dropping 251 frames (~4.1s UI freeze) during navigation and sync events (`[SyncEngine Realtime] Subscription status: RealtimeSubscribeStatus.timedOut`).
- **Crowded UI/UX:** On mobile viewport (360–390dp), inventory cards packed 9 separate visual elements (category tag, stock badge, image, variant count, variant tag chips, name, SKU, divider line, price, and action button) into an undersized box, making the catalog screen cluttered and hard to read.
- **Rendering Overhead:** Each card executed an internal `LayoutBuilder` (forcing a secondary layout pass per card per frame) and blurred `BoxShadow` rasterization.
- **Uncached Grouping:** Every screen rebuild executed full product filtering and multi-variant grouping allocations synchronously on the UI thread.

---

## 2. Optimizations Implemented

### UI & Layout Optimizations (`[Verified]`)
- **Eliminated `LayoutBuilder` per Card:** Removed `LayoutBuilder` from [`InventoryItemCard`](file:///c:/Users/carla/Desktop/POS%20android/pos/lib/presentation/widgets/inventory_item_card.dart); layout now uses natural `Column` and `Expanded` flex sizing in a single layout pass.
- **Removed Rasterization Cost:** Replaced GPU-costly blurred `BoxShadow` with a crisp 1px card border (`AppTheme.cardBorderColor`).
- **Spacious Ergonomic Card Hierarchy:**
  - Placed floating category and stock status badges directly on top corners of the thumbnail.
  - Allocated prominent 2-line title room with high-contrast text and clean mono SKU subtitle.
  - Eliminated the full-width divider line to reduce visual noise.
  - Raised aspect ratio on mobile from 0.82 to 0.78, giving card content vertical breathing room.
- **Sleeker Header:** Reduced vertical margins on the search bar and stats strip, recovering ~40dp of vertical viewport for product cards.
- **Grid Virtualization:** Configured `GridView.builder` with `addAutomaticKeepAlives: false`, `addRepaintBoundaries: true`, and `cacheExtent: 300` for 60fps scrolling.

### State & Logic Layer (`[Verified]`)
- **Memoized Filtering & Grouping:** [`_InventoryScreenState`](file:///c:/Users/carla/Desktop/POS%20android/pos/lib/presentation/screens/inventory_screen.dart) now caches `categoryCounts`, stock breakdown counts, and grouped variant items. Rebuilds triggered by keyboard/focus/navigation now skip all $O(N)$ calculations and allocations.

---

## 3. Sync & Terminal Error Diagnosis (`[Inferred]`)
- **`RealtimeSubscribeStatus.timedOut`:** On emulators without active internet or when Supabase websocket connectivity is severed, Supabase Realtime triggers timeouts and retries, invoking `notifyListeners()`.
- **Concurrent Pull Cycle:** Concurrently, `SyncEngine.startSyncLoop()` executes 13 PostgREST queries and runs `db.posDao.upsertFromCloud()`, triggering mass Drift table invalidations on the UI isolate. Parked in `docs/perf/backlog.md` for background isolate offloading.

---

## 4. Verification & QA
- **Test Suite (`[Verified]`):** Full suite of 129 test cases passing.
- **Formatting & Analysis (`[Verified]`):** `dart format` and `flutter analyze` verified.
- **Git Repo:** Pushed to GitHub repository at `https://github.com/CarlArvie/pos-android` (`main` and `perf/inventory`).
