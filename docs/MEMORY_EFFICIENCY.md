# NetStreamV2 v4.3.0 — Memory retention audit

These are source-level changes to reduce the **retained Luau heap after traffic bursts**. They do not alter BitFrame v1, the bundled Compression 2.4.2 codec (230), route IDs, packet ordering, or the encoded wire bytes.

## Findings and changes

| Finding in previous source | Change | Expected effect / trade-off |
|---|---|---|
| Idle legacy `Writer` and scratch writer pool members kept `strings`, `stringToIndex`, and the last route cache until acquired again | Call `writer:reset()` **when returning an eligible writer to its pool** | Drop references to packet strings immediately, rather than allowing idle writers to keep them alive; a reset during acquisition remains for safety |
| Pooled string dictionaries used `table.clear`, which preserves a large array/hash table's allocated capacity | `MaxPooledDictionaryEntries=128` by default; replace oversized BitFrame writer, BitFrame reader, legacy writer and legacy reader dictionaries with new tables | Reclaim high-water dictionary capacity after large unique-string packets (at the cost of fresh table allocations when packets again exceed the cap) |
| Native dynamic payload size estimator reused `state.strings` after clearing, keeping a large hash capacity | Track the count of distinct new estimator strings; replace dictionary table when it exceeds `MaxPooledDictionaryEntries` | Do not retain big per-packet measurement hashes while estimator states are pooled |
| Long-lived outbound queues kept array slots at ever-growing indices while draining without emptying | Copy the remaining pending FIFO elements to a fresh compact array if `head > 1024` and `head > floor(tail / 2)` | Bound retained sparse storage under continuous traffic; limited occasional copy/allocation cost |
| An outbound queue that drained completely kept a large allocated array in persistent client/broadcast buckets | `QueueRetainMaxSlots=512` default; replace the array on drain when the old tail exceeded this count | Release burst high-water array capacity rather than retaining it during idle periods |

`QueueRetainMaxSlots=0` rebuilds storage whenever a queue drains, which creates more GC activity. Increasing the threshold retains more capacity and may reduce churn. The default attempts to balance low idle heap with throughput. `MaxPooledDictionaryEntries=0` always rebuilds a nonempty dictionary at release, while larger values trade memory for fewer allocations. Caps only affect **pooled idle memory**, not allowed message payloads or accepted queue sizes.

## Diagnostics

```luau
NetStream.Configure({
    MaxPooledDictionaryEntries = 128,
    QueueRetainMaxSlots = 512,
})
local memory = NetStream.GetMemoryDiagnostics()
print(memory.QueueCompactions, memory.QueueStorageRebuilds)
print(memory.DictionaryPoolRebuilds, memory.NativeMeasureDictionaryRebuilds)
print(memory.PooledWriterResets, memory.LuaHeapKB)
```

`QueueCompactions` counts copies of a live sparse FIFO into a smaller array. `QueueStorageRebuilds` counts a fresh queue array after a large drain. `DictionaryPoolRebuilds` and `NativeMeasureDictionaryRebuilds` count discarded large-capacity packet/estimator dictionaries. `PooledWriterResets` counts legacy/scratch writer cleanup on release.

These counters indicate that retention controls **executed**, not the number of bytes saved. `LuaHeapKB` is `gcinfo()` for the whole Luau VM; it includes application allocations and is not NetStream-exclusive. The object pools may temporarily allocate new tables; a reduction in long-lived retention can increase short-term GC and CPU cost.

## Regression and performance procedure

1. In an **isolated** Roblox Studio session, pair `tests/MemoryRetentionRegression.server.lua` in ServerScriptService with `tests/MemoryRetentionRegression.client.lua` in StarterPlayerScripts. Keep `Netstream.lua` in ReplicatedStorage with `Compression.lua` as a child.
2. The server queues 1,200 ordered U16 events and 128 distinct strings, flushes the reliable queue in 32-message batches, then asserts compaction, oversized drained-array rebuild, dictionary rebuild and no remaining queued work. The client asserts exact FIFO, string equality, and completion. The test config uses intentionally small thresholds (16 entries/slots) to trigger cleanup, but **must not be deployed as a production preset**.
3. For a meaningful heap comparison use the same game/place, hardware, player count and packet mix on the pre-patch commit and patched commit. Warm up, run a burst, stop sending, let the GC settle, and record `gcinfo()`, memory profiler allocations, counters, and encode/decode/flush CPU p95/p99 for several sessions. Also compare a sustained nonempty queue to detect compaction overhead. Repeat with the thresholds disabled/raised to observe allocation versus retention trade-offs.
4. Confirm `GetStats().DroppedReliable`, sent message count, and encoded bytes are unchanged for same workload. A source-audit/parse pass cannot establish network delivery or a measured memory win.

**Verification status:** Deterministic source audit and official Luau parse/compile are CI gates; Roblox Studio Play tests and matched heap-after-GC benchmarks are pending. Avoid percentage memory claims until measured.
