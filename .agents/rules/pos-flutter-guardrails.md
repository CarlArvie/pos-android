---
trigger: always_on
description: Standing constraints for the POS Flutter mobile app. Always loaded.
---

# POS Mobile: Standing Guardrails

## Project facts (source: pubspec.yaml; re-read it if it may have changed)
- Flutter, **mobile only** (Android + iOS). Dart SDK `^3.11.5`.
- Local DB: `drift` + `sqlite3_flutter_libs`. Backend: `supabase_flutter`. Export: `excel`, `csv`, `share_plus`. Also `image_picker`, `permission_handler` (pinned to exactly `11.4.0`; do not change), `shared_preferences`, `http`, `uuid`, `path`, `path_provider`.
- **Not present** (never assume they exist, never add silently): state-management package, image-cache package, connectivity package, crash reporting, logger, `intl`, `integration_test`/`flutter_driver`.
- **Testing setup:** a `flutter test` suite exists. The developer tests manually on **two Android emulators**. No physical low-end device is assumed available.
- Primary target: **low-end Android** (assume 2 GB RAM, 4 slow cores, 720p, Android 8-10).

## Hard rules
1. Mobile only. Web/desktop runs are never evidence. Antigravity's browser tools do not apply to this app.
2. Correctness before speed. Never alter without an approved plan: money math, stock deduction, sale/receipt numbering, sync outbox ordering, audit trail, auth.
3. Money is integer minor units (centavos). Never `double` for money.
4. Local-first. Screens read and write Drift. A network call must never block adding to cart or completing a sale.
5. **Evidence tiers.** Tag every finding and every result:
   - `[Verified]`: hardware-independent fact: passing test, `EXPLAIN QUERY PLAN`, rebuild count, DB-query count, request count, APK size. Valid on any machine.
   - `[Measured-emu]`: timing on an emulator. Valid only as a **relative** before/after on the same AVD, same data, same build mode. Report ratios, never absolute claims.
   - `[Measured-device]`: timing on a real device. The only tier that can declare a budget "met".
   - `[Inferred]`, `[Assumed]`: code reading and guesses. Never build a plan on `[Assumed]` alone.
   Without `[Measured-device]`, write "budget unconfirmed", never "budget met".
6. No new dependency without asking. State: package, size cost, why a zero-dependency option is worse.
7. Small diffs, one concern per change. Never edit `*.g.dart`.
8. Drift schema change = bump `schemaVersion` + additive migration + `dart run build_runner build --delete-conflicting-outputs`. Never drop or rewrite production data.
9. Never run load tests against production. Never put a `service_role` key or any secret in the app or these files.
10. Before finishing any change: `dart format .`, `flutter analyze` (no new issues), `flutter test` (must pass). Never delete, skip, or weaken an existing test to make a change pass.
11. **Scope lock.** When invoked for one feature, edit only that feature's files. Anything found elsewhere goes to `docs/perf/backlog.md`, not into the diff. Shared files (used by other features) need plan approval and a full `flutter test` run.
12. **Git safety.** Work on branch `perf/<feature>`, one commit per finding. Undo with `git revert`. Never run `git reset --hard`, `git clean`, or force-push unless the user explicitly asks. Never commit to the main branch.

## Performance budgets (defaults; declared met only with `[Measured-device]`)
| Metric | Target |
|---|---|
| Cold start to interactive product screen | <= 2.5 s median |
| Frame build and raster time (each) | <= 8 ms at p95 |
| Janky frames (> 16 ms) while scrolling product grid | <= 1%, zero frames > 100 ms |
| Tap to visible feedback | <= 100 ms |
| Search keystroke to results (10k products) | <= 150 ms |
| "Charge" tap to receipt visible (local commit) | <= 300 ms |
| Steady-state memory (PSS) | <= 200 MB, no growth over 100 cart cycles |
| Release APK (arm64, split per ABI) | <= 25 MB; flag any dependency adding > 1 MB |

If the user changes a target, edit this table, not the skill.

## How to work here (Antigravity)
- Any perf, UX, scale, sync, or startup task: activate skill `pos-mobile-perf-ux`.
- Main entry point: `/optimize-feature <feature> [ui|logic|db|sync]` optimizes one feature slice. Others: `/perf-audit`, `/db-sync-review`, `/release-size-check`.
- **Stop and ask (plan approval) only for:** schema/migration changes, stock or money semantics, shared-file edits, new dependencies, sync protocol/RPC changes, deleting APIs used elsewhere. Everything else inside the feature slice proceeds without stopping.
- List terminal commands before running them. Never chain destructive commands. Do not enable non-workspace file access.
- If something cannot be measured here, say so, name the tier you reached, and never invent numbers.
- If a request conflicts with these rules, name the rule and propose an alternative. Do not silently comply and do not silently refuse.
