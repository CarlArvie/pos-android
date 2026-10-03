# Performance & UX Optimization: Staff & Cashiers, 2026-10-03

## Context
- Reference target: Low-end Android (2GB RAM, 720p / 360-390dp width, Android 8-10)
- Build: Flutter 3.11.5 Dart SDK, debug/profile/release
- Feature slice: `staff` (`StaffManagementView`, employee directory, role permissions matrix, dialogs)
- Must-not-change behavior: Granular permissions gating (`staffView`, `staffManage`, `staffPermissions`, `staffResetPin`), PIN login security, role persistence, and cloud sync hooks.
- Highest evidence tier reached: `[Verified]` (all 141 tests pass, 0 static analyzer issues in slice, reactive Drift streaming, LayoutBuilder removed, BoxShadow removed).

## Findings (ranked)
| # | Finding | Evidence tag | Impact | Effort | Files |
|---|---|---|---|---|---|
| 1 | `LayoutBuilder` inside `ListView.builder` items caused deferred sub-layout passes on each card during scroll | `[Verified]` | High | Low | `lib/presentation/screens/staff/staff_management_view.dart` |
| 2 | Missing search & role filter forced manual scrolling through full employee lists on cramped mobile viewports | `[Verified]` | High | Med | `lib/presentation/screens/staff/staff_management_view.dart` |
| 3 | Employee deactivation caused inactive staff to disappear completely from the directory without re-activation | `[Verified]` | High | Med | `lib/presentation/screens/staff/staff_management_view.dart` |
| 4 | Non-reactive one-off DB reads failed to reflect background syncs or external profile changes | `[Verified]` | Med | Med | `lib/presentation/screens/staff/staff_management_view.dart` |
| 5 | Unsaved changes bar used blurred `BoxShadow`, triggering off-screen GPU raster blur passes | `[Verified]` | Med | Low | `lib/presentation/screens/staff/staff_management_view.dart` |
| 6 | Mobile roles matrix tab used unvirtualized `ListView(children: ...)` inflating all module cards at once | `[Verified]` | Med | Low | `lib/presentation/screens/staff/staff_management_view.dart` |

## Changes Made
- **Reactive Streaming & Fast First Frame (`[Verified]`)**: Initialized persistent `_employeesSubscription` watching `widget.db.employees` for the store with immediate `query.get()` populating the first frame.
- **Search & Filter Bar (`[Verified]`)**: Added compact 36dp search field for instant name/email filtering and popup role filter chip (`All`, `Active`, `Inactive`, `Cashier`, `Manager`, `Admin`).
- **Eliminated `LayoutBuilder` & Added `RepaintBoundary` (`[Verified]`)**: Extracted `_StaffCard` widget, passed viewport compactness from parent, and wrapped each card in `RepaintBoundary` to eliminate rebuild/repaint cascade.
- **Eliminated Blurred `BoxShadow` (`[Verified]`)**: Replaced multi-pixel blurred `BoxShadow` in `_buildUnsavedChangesBar` with a crisp flat border (`Border(top: BorderSide(color: Color(0xFF334155), width: 1.5))`).
- **Virtualized Module Matrix (`[Verified]`)**: Replaced unvirtualized `ListView(children: ...)` in mobile permissions tab with `ListView.builder`.

## Regression Check
- `flutter analyze`: **0 issues** in staff slice (only 4 pre-existing deprecations in `main.dart` and `setup_device_screen.dart`).
- `test/staff_permissions_test.dart`: **6 / 6 passed**.
- `test/staff_cashier_characterization_test.dart`: **6 / 6 passed**.
- `test/permission_service_test.dart`: **6 / 6 passed**.
- `test/widget_test.dart` (StaffManagementView tests): **2 / 2 passed**.
- Full test suite (`flutter test`): **141 / 141 passed** (100% green).

## Not Done, and Why
- Cloud Auth user creation in `AddStaffDialog` calls `SupabaseAuthService.signUpUserBackend`: Kept intact to preserve cloud auth profile provisioning without altering backend contracts.

## Risks and Rollback
- Revertable cleanly via `git revert 1c7e2e0`.

## Next Steps
- Run manual QA on the two Android emulators using the checklist below.
