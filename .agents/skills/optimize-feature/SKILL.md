---
name: optimize-feature
description: Optimizes ONE feature slice of the Flutter POS app (UI/UX, logic, Drift database) for low-end Android performance, for example inventory or checkout. Use when the user runs /optimize-feature or explicitly asks to optimize, speed up, or clean up a named feature. Usage: /optimize-feature <feature> [ui|logic|db|sync].
---

Run this procedure only when the user invoked /optimize-feature or clearly asked for it. Do not start it on your own.

# /optimize-feature

Input: the feature name, then optional aspects (`ui`, `logic`, `db`, `sync`). Default aspects: `ui logic db`. If no feature name arrived, ask once.

1. **Load context.** Activate skill `pos-mobile-perf-ux`. Read `.agents/skills/pos-mobile-perf-ux/resources/09-feature-scope-tests.md`, then only the resources for the chosen aspects (ui: 02, 06, 03; logic: 03; db: 04; sync: 05).
2. **Safety.** Run `git status`. If dirty, ask the user to commit or stash and wait. Then `git switch -c perf/<feature>`.
3. **Slice map.** Build and print the file map (UI, state/logic, data, sync, tests, shared). Apply the scope lock: edit only slice files. If the slice is over ~25 files or unclear, ask the user to confirm once.
4. **Environment.** Run `flutter devices`. Note which emulator is the low-spec proxy. State the evidence tier you can reach: `[Verified]` always; `[Measured-emu]` if an emulator runs profile mode; `[Measured-device]` only with a real phone.
5. **Lock behavior.** Run `flutter test` for the slice's tests. For any logic you might change that lacks tests, write characterization tests that pass on the current code, run them, commit `test(<feature>): characterize ...`. No logic edits before this step.
6. **Baseline.** Record, for the requested aspects:
   - static audit hits inside the slice (`dart run .agents/skills/pos-mobile-perf-ux/scripts/audit.dart lib`, filtered)
   - `EXPLAIN QUERY PLAN` for each hot slice query; DB queries per user action; requests per action
   - rebuild counts for the main widgets on the main interaction
   - `[Measured-emu]` timings for the relevant scenarios (S2/S3/S4 or feature equivalent) when possible: 3 runs, median and worst
7. **Diagnose.** Rank findings by (impact x confidence) / effort, only within the requested aspects. Append out-of-slice findings to `docs/perf/backlog.md`; do not fix them.
8. **Implement.** Follow the priority ladder. One finding per commit: `perf(<feature>): <what> [<tag>]`. After each: `dart format .`, `flutter analyze`, `flutter test` for the slice. Stop and ask ONLY at a gate: schema/migration, stock or money semantics, shared-file edit, new dependency, sync protocol, removed public API. Present the gated item as a short plan (change, files, risk, rollback) and wait.
9. **Verify.** Re-run the baseline measurements. Revert (`git revert`) any change that did not improve its metric. Run the FULL `flutter test` and `flutter analyze`.
10. **Report.** Write `docs/perf/YYYY-MM-DD-<feature>.md` (template 08). Update `docs/perf/feature-status.md`. Give the user the tailored manual QA checklist for the two emulators (template in `.agents/skills/pos-mobile-perf-ux/resources/09-feature-scope-tests.md`).
11. **Chat summary, 10 lines or fewer:** what changed, before/after with evidence tags, backlog items added, and "Budgets: unconfirmed (no real device)" unless a real device was used.
