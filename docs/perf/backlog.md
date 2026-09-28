# Performance & Architecture Backlog

| Feature/area | File | Finding | Tag | Suggested aspect |
|---|---|---|---|---|
| SyncEngine | `lib/core/sync_engine.dart` | Supabase Realtime WebSocket timeouts on emulator/offline loop trigger periodic `notifyListeners()` and concurrent 13-table `_executePullCycle()` pull sweeps on UI isolate | `[Inferred]` | `sync` |
| SyncEngine | `lib/core/sync_engine.dart` | Large payload `upsertFromCloud()` runs on main isolate; consider moving bulk JSON decodes and multi-table bulk writes to background isolate or staging batches | `[Verified]` | `sync` |
