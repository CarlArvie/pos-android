---
name: perf-audit
description: Runs a read-only performance, UX and scale audit of the whole Flutter POS app and produces a ranked findings report plus an implementation plan without editing source code. Use when the user runs /perf-audit or asks which parts of the app to optimize first.
---

Run this procedure only when the user invoked /perf-audit or clearly asked for it. Do not start it on your own.

# /perf-audit

1. Activate skill `pos-mobile-perf-ux`. Re-read the budgets in `.agents/rules/pos-flutter-guardrails.md`.
2. Read `pubspec.yaml`, `analysis_options.yaml`, `android/app/build.gradle(.kts)`, and list `lib/` two levels deep. Do not read every source file.
3. Ask the Phase 0 intake questions in ONE message. Wait for the answers.
4. Run `dart run .agents/skills/pos-mobile-perf-ux/scripts/audit.dart lib` and save the output to `docs/perf/audit-raw.txt`.
5. Read `.agents/skills/pos-mobile-perf-ux/resources/01-measure.md`. Run `flutter devices`. State the highest evidence tier available (`[Verified]`, `[Measured-emu]`, or `[Measured-device]`).
   - Emulator or device attached: run scenarios S1-S8 in profile mode with seeded data. Emulator timings are relative only.
   - Nothing runnable: give the user the exact commands and ask for pasted results. Otherwise label findings `[Inferred]`/`[Assumed]` at the top of the report.
6. Read fully the 5 files with the most audit hits, highest `setState` density, or largest size.
7. Inspect data and network paths. Read `.agents/skills/pos-mobile-perf-ux/resources/04-drift.md` and `.agents/skills/pos-mobile-perf-ux/resources/05-sync-scale.md`. List Drift tables and indexes, every `.watch()` query, and every network call site (`Supabase.instance`, `.from(`, `.rpc(`, `http.`). Count requests per completed sale.
8. Write the report from `.agents/skills/pos-mobile-perf-ux/resources/08-report-template.md` to `docs/perf/YYYY-MM-DD-audit.md`. Create an Implementation Plan artifact with the ranked fixes.
9. Do NOT edit source files in this workflow. End by asking which findings to implement.
