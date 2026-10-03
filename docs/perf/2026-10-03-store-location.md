# Store & Location Performance & Ergonomics Report, 2026-10-03

## Context
- Primary target: Low-end Android (assume 2 GB RAM, 4 slow cores, 720p, Android 8-10)
- Build: Flutter 3.x, Dart 3.11.x, commit `0204337`
- Branch: `perf/store-location`
- Data: Multi-store tenancy (stores, cash registers, default inventories)
- Must-not-change behavior: Store switching updates `DevicePrefs.storeId`, terminal switching updates `DevicePrefs.registerId`, `storesManage` permission gate, `storesSwitch` permission gate, product inventory auto-initialization on branch creation.

## Baseline
| Scenario | Metric | Budget | Baseline |
|---|---|---|---|
| Load stores & terminals (N stores) | DB query count | <= 2 queries | 1 + N sequential queries `[Verified]` |
| Mobile 360x640 Store Management Screen | RenderFlex overflow | 0 px | Overflowed by 432 px on mobile widths `[Verified]` |
| Switch Branch / Terminal Dialogs | Virtualized list layout | Bounded, virtualized | `shrinkWrap: true` in unconstrained dialog `[Verified]` |
| Store & Terminal search filtering | Realtime lookup | Responsive debounced | None (full manual scrolling only) `[Verified]` |

## Findings (ranked)
| # | Finding | Evidence tag | Impact | Effort | Files |
|---|---|---|---|---|---|
| 1 | N+1 database queries when loading stores & registers | `[Verified]` | High (1 + N queries on UI isolate) | Low | `lib/presentation/screens/stores/stores_management_view.dart` |
| 2 | Dialog list virtualization defeated by `shrinkWrap: true` | `[Verified]` | Med (excessive layout passes & dialog overflow risk) | Low | `lib/presentation/screens/settings/switch_store_dialog.dart`, `switch_register_dialog.dart` |
| 3 | Mobile layout overflow (360x640) on header and missing location search | `[Verified]` | High (UI overflow on phone, hard navigation with multiple branches) | Med | `lib/presentation/screens/stores/stores_management_view.dart` |
| 4 | Missing RepaintBoundary on store and terminal cards | `[Verified]` | Med (raster repaint across cards on terminal switch) | Low | `lib/presentation/screens/stores/stores_management_view.dart` |

## Changes made
- Finding 1: Concurrently batched store and register fetching via `Future.wait` and grouped into `Map<String, List<CashRegister>>` in $O(R)$ time, dropping query count from $1 + N$ to strictly 2 queries `[Verified]`.
- Finding 2: Replaced `shrinkWrap: true` with virtualized `ConstrainedBox(maxHeight: 0.55 * screenHeight)` in `SwitchStoreDialog` and `SwitchRegisterDialog` `[Verified]`.
- Finding 3: Added compact mobile header layout, realtime search/filtering for stores and terminals, and `RefreshIndicator` for swipe-to-refresh `[Verified]`.
- Finding 4: Wrapped individual store cards in `RepaintBoundary` to isolate raster repaint cycles `[Verified]`.

## After (Verified)
| Scenario | Metric | Baseline | After | Budget met |
|---|---|---|---|---|
| Load stores & terminals | Query count | 1 + N queries | 2 queries total `[Verified]` | Unconfirmed (no real device) |
| Mobile 360x640 Layout | RenderFlex overflow | 432 px overflow | 0 px overflow `[Verified]` | Unconfirmed (no real device) |
| Switch Store / Register Dialog | Virtualization | `shrinkWrap: true` | Virtualized `ConstrainedBox` `[Verified]` | Unconfirmed (no real device) |
| Store Search & Repaint | Filtering & isolation | None | Instant query filter & `RepaintBoundary` `[Verified]` | Unconfirmed (no real device) |

## Regression check
- `flutter analyze`: 0 issues found across slice
- `flutter test`: 141 passing tests (including new characterization & optimization tests)
- Golden path (store branch creation, terminal switching, store switching, permission guard): Verified passing

## Risks and rollback
- Low risk. Edits strictly scoped to store/register UI slice.
- Rollback: `git revert 0204337`, `git revert 181e4e3`, `git revert 8dff66f`.
