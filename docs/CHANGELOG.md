# NetStreamV2 Changelog

The current release candidate is **v4.3.0**, using **BitFrame v1** and bundled **Compression v2.4.2** (codec **230**). Release notes describe implemented source changes. Roblox Studio performance results are **not yet measured**.

## v4.3.0 — Bounded idle memory and sparse queue storage

- Clean up eligible legacy/scratch packet writers **upon pooling**, so retained writers cannot hold the last packet's string dictionaries or route caches during idle periods.
- Bound idle dictionary storage with `MaxPooledDictionaryEntries=128`; release oversized Luau string dictionary arrays/maps in BitFrame and legacy writer/reader pools. Rebuild large native dynamic-size measurement dictionaries instead of retaining cleared hash capacity.
- Compact sustained sparse outbound queues by copying live entries into a new array after a sufficient head advance; release oversized array storage on drain using `QueueRetainMaxSlots=512`. Surviving message order, logical queue count and packet format are preserved.
- Extend `GetMemoryDiagnostics()` with pool rebuild, writer-release reset, and FIFO compaction counters/caps.
- Add 2 paired `MemoryRetentionRegression` scripts and source-level deterministic FIFO + cleanup models (92 Studio script sources total). Measurements of GC/heap savings in Roblox Studio remain pending; table rebuilds may add allocation overhead.

## v4.3.0 — Homogeneous integer codec specialization

- Specialized 2–32-field U16/U32 tuples and packed runs with single bounds preflight and direct bit reads/writes, avoiding per-field type dispatch.
- Added `TypedTupleFastPathEnabled=true` by default; false uses the previous wire-identical generic mixed fixed-width path. Both settings are interoperable between peers.
- Exposed six scalar and batched tuple fast-path counters in `GetStats()` / `GetPerformanceStats()`.
- Added paired 12-field U16/U32 test cases and deterministic bit-parity models at unaligned offsets. The full suite now contains 92 Studio-script sources, including a paired on/off A/B performance probe and memory retention regression.
- No benchmark-derived performance claim; BitFrame v1 and Compression codec 230 unchanged.

## v4.3.0 — Dispatch overload protection and fair outbound processing

- Protect the global bounded dispatch queue with a separate per-Player pending callback limit (default 2048, 0 disables), covering both scalar and argument-table callbacks. Dequeue releases that quota before callback invocation; Destroy clears accounting.
- Drop already-queued event callbacks after the Player disconnects, releasing argument arrays and recording `DispatchDisconnectedDrops`.
- Configurable elapsed-time check every 8 callbacks, previously 32; callers may tune 1–128.
- When broadcasts compete with queued player-specific traffic, split the periodic flush CPU budget using `BroadcastFlushBudgetFraction` (default 0.5, 1 = previous scheduling). Existing per-target FIFO and bandwidth governor remain unchanged.
- Expose `GetDispatchStats(player?)` and queue peak/per-player drop counters. Add 2 paired Studio test scripts (4 files) and deterministic source audit checks; Studio runtime and CPU/network improvements are unverified.
- Preserve BitFrame v1 and bundled Compression v2.4.2, codec 230.

## v4.2.3 — Server-controlled interest groups
- Server-created groups restrict reliable/unreliable event and state fanout to connected subscribers. Member add/remove/clear/destroy are explicit and server-owned.
- Prevalidate fanout payloads before the first enqueue to prevent partial sends on malformed input; provide acceptance count (not confirmed delivery).
- Add interest-route counters and paired membership/no-leak Studio regression. No automatic spatial interest computation.

## v4.2.2 — Explicit field-delta codec
- `CreateDeltaCodec` supports 1–32 named primitive fields, changed/deleted bit masks, no-change suppression and revision-checked full/delta application.
- Reject malformed/stale/gap frames without altering previous state. Requires reliable ordered Event and app-managed per-target resync; no implicit StateRoute transport.
- Paired full→delta Studio regression tests scalar changes, nil deletion, malformed masks and wrong base revisions.

## v4.2.1 — Whole-run mixed-schema preflight
- Mixed fixed-width Bool/U8/U16/I16/U32/I32 packed runs use a single aggregate encoder/decoder bounds preflight, preserving signed integer two's-complement layout.
- Adds packed-run usage counters, does not alter BitFrame v1 or Compression codec 230.

## v4.2.0 — Mixed integer schema packing and wider packed runs

- Compiles bit widths for 2–32-field Bool/U8/U16/I16/U32/I32 schemas. The BitFrame writer preflights the whole payload once and writes each field directly to the buffer; the reader preflights once and reconstructs signed integers. Existing all-Boolean/all-U8 paths are retained.
- Raises default `PackedSchemaRunMaxFields` from 8 to 16 so 9–16-field fixed-schema event runs can share one header. Larger temporary packed arrays may cost memory; profile and override to 8 if necessary.
- Adds `BitFrameFixedSchemaFastWrites` and `BitFrameFixedSchemaFastReads` counters, deterministic bit-layout checks, and paired Studio regression testing boundary values, FIFO, and two-way traffic.
- BitFrame v1 and bundled Compression v2.4.2 codec 230 remain unchanged. Runtime performance gains are unverified until matched Studio benchmarks.

## v4.1.1 — Exact BitFrame packet-size audit

- Adds opt-in `PacketSizeAuditEnabled` (off by default) with `NetStream.GetPacketSizeAudit()`: last successfully transmitted packet plus aggregate counts, presence flags, message kind, route IDs, request IDs, packed-run markers/counts, payload, end markers, byte padding and physical encoded bytes.
- Records actual BitFrame writer bit positions and commits totals only when the remote send succeeds; budget probes, oversized-batch re-encodes, deferrals and failures do not inflate sent totals.
- Wire encoding and decoder remain unchanged (BitFrame v1 + Compression codec 230), with optional measurement bookkeeping only. Adds paired PacketSizeAuditRegression tests for 7-byte U32, 5-byte U16, 4-byte short-route U16 and 20-byte U16 packed run cases; byte arithmetic is also modeled in source-audit. Real Studio execution still required.
- Audit data excludes Roblox RemoteEvent envelope and engine replication; Packet Profiler's estimated remote call size is not the encoded buffer length.

## v4.1.0 — Low-traffic batching and safe State deduplication

- **Opt-in low-traffic preset:** `NetStream.ConfigureLowTraffic(overrides?)` selects a 30 Hz periodic flush, 50 ms Normal-priority batch window and 32-message target packet size. Critical and Realtime fast flush behavior is unchanged; explicit overrides win.
- **Opt-in reliable State dedup:** `NetStream.State(..., {Coalesce=true, SuppressUnchanged=true})` suppresses unchanged, already-delivered primitive states for individual targets and client-to-server states; only after a real successful send, only while no other outbound messages are pending, and never for RPC/events, unreliable updates, broadcasts or `Now` calls.
- **Correctness:** Broadcast state sends invalidate all per-player cache entries; any other sent state for the same route replaces or invalidates the cached value; resetting the client handshake clears its cache. No suppression of unconfirmed/queued sends. State value strings are cache-limited and target caches bounded.
- **Diagnostics:** `LowTrafficStateDuplicatesSuppressed` and `LowTrafficStateCacheWrites` in `GetStats()` to count logical events (not bytes saved). Studio paired `LowTrafficRegression` script checks duplicate suppression, changed state delivery and forced resync.
- **Wire:** No format change; still BitFrame v1 and Compression 2.4.2, codec 230. Existing APIs and defaults remain unchanged unless the profile or per-route suppression is explicitly enabled.
- **Qualification:** Roblox engine physics, character traffic and transport headers are not controlled by NetStream. Live bandwidth and p95 latency improvements require matched Studio measurements.

## v4.0.2 — Isolated-send fallback reliability and low-allocation compression

- **NetStream correctness:** During isolated send recovery after batch encoding failure, released slots use `false` instead of `nil`, preserving the original batch length for deferred-tail reconstruction. Addresses potential message loss when a partial retry hits bandwidth throttling.
- **NetStream FIFO/heap:** Deferred-queue restore reserves nonnegative array indices and shifts remaining pending entries only when the prepend prefix has insufficient room.
- **Compression 2.4.2:** Shared frozen empty dictionary for no-dictionary/scalar encode and decode; omit scalar seen-table allocation and empty duplicate-dictionary tracking.
- **Input hardening:** Reject map-key container tags before recursively materializing malformed composite keys. Preserve codec 230, packet headers, canonical varints and primitive map key behavior.
- **Testing:** Added paired `TransportRecoveryRegression` and standalone `CompressionV242Regression` scripts, deterministic JS queue recovery models, and synchronized version guards. Source checks are not live Studio performance measurements.

## v4.0.1 — Sustained dispatch-queue bound and lower codec allocation

- **NetStream correctness/memory:** Compact live dispatch rows when `dispatchHead` grows beyond the configured `MaxDispatchBacklog` under sustained nonempty traffic. Preserve route/player/args/scalar-flag rows in order, clear previous indices and expose `DispatchQueueCompactions` in `GetStats()`.
- **Compression v2.4.1:** Drop the temporary `seenKeys` map during decoded map reconstruction. Check duplicate keys using non-nil outputs (including valid false values), preserving duplicate/rejected-key validation.
- **Compression CPU:** Omit dictionary candidate traversal for scalars, because no references can be reused. Reduce minimum estimated buffer capacity for very small packets from 256 to 64 bytes; larger packets grow normally.
- **Verification:** Added `DispatchCompactionRegression` paired Studio scripts, `CompressionV241Regression.server.lua`, and deterministic dispatch compaction model assertions in source audit. Updated all Studio version guards.
- Preserves all message formats and all existing APIs: BitFrame v1, Compression codec 230. Studio runtime benchmarks remain pending; source-level CI cannot guarantee every gameplay workflow.

## v4.0.0 — Packed receive optimization and Compression v2.4.0 hardening

- **NetStream receive performance:** Packed one-field Bool/U8/U16 event runs get one total-bit capacity preflight and direct `buffer.readbits` iteration. Preserve scalar atomic staging, rate-limit groups and FIFO, recording `BitFramePackedScalarFastReads`.
- **Compression v2.4.0:** A dedicated one-byte varuint writer/reader path, exact multi-byte preallocation instead of reserving eight bytes on each varuint, and O(1) eligible writer-pool removal.
- **Correctness:** Reject table/reference map keys that cannot preserve identity across the packet boundary on both encode and decode; malformed varuint decode stays canonical and bounded.
- **Wire:** Retain Compression magic and codec 230, BitFrame v1, all tags/headers, route IDs and existing APIs. NetStream accepts bundled 2.3.x or 2.4.x compressor only if the expected codec metadata matches.
- **Testing:** Added `CompressionV24Regression.server.lua` including integer/writer-pool/malformed data cases; refreshed version assertions across all existing Studio scripts and expanded source audit. Source CI is not a Studio runtime benchmark.

## v3.9.0 — Burst throughput, packed hot path and regression benchmarking

- **Send bursts:** Drain adjacent FIFO entries directly from the outbound queue; do the queue logical-count decrement once per batch instead of calling `queuePop` for every entry. Preserve first oversized-run behavior, message order and latest/coalescing semantics.
- **Receive dispatch:** Switch the dispatch CPU budget check from a modulo operation on every processed event to a 32-event checkpoint. Maintain the same callback order, maximum dispatch count and time budget.
- **Packed hot path:** Write one-field Bool, U8 and U16 runs directly through a single bit-capacity preflight and bulk buffer bit writes. Preserve exact BitFrame field layout, send-side schema validation and size caps. Optimize one-, two- and three-field value packing without argument tables.
- **Profiling:** Expose `BitFramePackedScalarRunWrites` via `GetStats()` and add the paired `BurstSaturationBenchmark` with 30,000 reliable logical messages and FIFO/payload assertions. Add JS reference-model source audit for burst-drain invariants.
- Existing Studio test version guards are synchronized to 3.9.0; the wire format remains BitFrame v1, Compression 2.3.5. **Roblox Studio measured throughput, CPU p95/p99 and GC savings remain unverified.**

## v3.8.0 — Packed-run high-water memory retention fix

- Keep a weak-key high-water marker for packed value backing tables that ever exceed `MaxPooledPackedValues`, including arrays grown by appended events and arrays whose message was split.
- Do not pool those backing tables after a later split reduces their live element count; this avoids keeping a high-capacity array in the small-value pool.
- Prefer direct unpooled allocation when the requested packed array is already oversized, preserving warm small-object pool entries.
- Add `PackedValueHighWaterDrops` memory diagnostics and paired `PackedHighWaterRegression` Studio scripts.

## v3.7.0 — Packed one-field numeric runs without per-value argument tables

- Decode packed one-field Bool/U8/U16/I16/U32/I32/F32/F64 event runs directly into scalar staging.
- Extend signed group tags so the first item retains its run rate-limit allowance and followers consume it without repeated bucket calls.
- Preserve FIFO order and scalar nil handling, and expose `BitFramePackedScalarRunItems`.
- Add paired `PackedScalarRunRegression` Studio scripts.

## v3.6.0 — Bit-write and small outgoing varargs CPU hot paths

- Avoid an `ensureBits` method invocation for ordinary in-capacity writes in `BitFrameWriter:bits`, while checking both buffer and maximum packet limits.
- Pack one-, two- and three-argument outgoing messages directly instead of repeating indexed `select` calls.
- Retain arbitrary arity and nil-preserving fallback behavior.

## v3.5.0 — Bounded retained pools and reduced cleanup work

- Add independent, validated defaults `MaxArgsPoolSize=512` and `MaxMessagePoolSize=512` (both still respect `MaxPoolSize`) to cap idle argument/message allocations retained after bursts.
- Add `MaxPooledBatchItems=512`; track oversized transient batches through a weak-key set so they are never retained even if split down to a small live count.
- Skip `table.clear` when batch, packed-value or BitFrame stage pools are already full. Keep old cleanup when objects actually reenter a pool.
- Add `ArgsPoolLimitDrops`, `MessagePoolLimitDrops`, `BatchPoolOversizeDrops` and memory diagnostics; add `BoundedPoolRegression` Studio pair.
- These caps trade some allocation churn under sustained peaks for reduced idle retained heap. Measure GC and CPU before lowering them further.

## v3.4.0 — Consolidated scalar dispatch and allocation-free rejected dynamic args

- Remove the `dispatchScalarValues` queue array; store scalar payloads in `dispatchArgs` and use the existing scalar flag to distinguish `nil` from regular argument arrays.
- For globally rejected dynamic multi-value frames and RPC returns, consume and validate fields without acquiring an arguments table.
- Track `BitFrameRejectedDynamicArgsAvoided`; add `DynamicDiscardHeapRegression` tests.

## v3.3.0 — Bulk fixed schema drop and scalar rate-limit hardening

- Compute the exact bit length of an entire rejected fixed-width schema run, preflight once, advance once, and preserve schema discard counters.
- Keep variable-width/domain-validated values on individual validating decoders.
- Fix route-level scalar rejection so numbers/bools are not passed to `releaseArgs` as Lua tables.
- Keep the BitFrame stage referenced through commit for cleanup if a commit action fails.
- Add `BitFrameBulkDiscardedRuns` and `ScalarThrottleHeapRegression` Studio pair.

## v3.2.0 — Single numeric schemas without allocated argument tables

- Compile `scalarKind` for one-field Bool, U8, U16, I16, U32, I32, F32 and F64 schemas.
- Decode single-field numeric event/state messages directly to atomic scalar storage and use scalar dispatch, instead of creating args tables.
- Retain F32/F64 nonfinite validation and original message order.
- Add `BitFrameScalarSchemaReads` to statistics and paired `ExtendedScalarStringRegression` Studio coverage.

## v3.1.0 — Short unaligned binary strings without per-character tables

- Decode a single byte directly into `string.char`, without allocating a buffer.
- Decode unaligned 2–15 byte strings into one buffer instead of a Lua table and individual character strings.
- Preserve byte-aligned and empty-string behavior, and use the single-byte fast path for hybrid strings.

## v3.0.0 — Fixed-width rejected schema skip

- Precompute bit lengths for fully representable BOOL, U8, U16/I16, U32/I32 and Color3 field combinations at schema compilation.
- Consume rate-limited fixed schemas with one bounds check and a bit-position increment rather than per-field decoding.
- Keep float, variable-width and domain-restricted types on the original validating decoder path.
- Add `BitFrameDiscardedFixedBits` and paired `FixedDiscardRegression` Studio scripts.

## v2.9.0 — Rejected schema payloads without args-table allocations

- Add `Internal.bitFrameDiscardSchemaArgs` to consume rate-limited BitFrame schema data while preserving schema field validation.
- Skip U8 runs and packed booleans via bounds-checked bit-position advancement, avoiding per-field allocations and individual reads.
- Use the discard fast path for rejected schema event runs and rejected schema RPC/state messages.
- Add `BitFrameDiscardedSchemaArgs` diagnostics and paired `HeapDiscardRegression` Studio tests.

## v2.8.0 — Five-table compact atomic staging

- Replace scalar `flags` and `values` parallel staging arrays with a signed group tag and the existing argument slot.
- Preserve nil scalar handling and FIFO semantics, while skipping argument-table release for scalar slots.
- Reduce parallel staging tables from eight in v2.6.0 to five in v2.8.0.

## v2.7.0 — Leaner route storage and bounded stage pooling

- Remove redundant route ID table from atomic BitFrame stages, retrieving the registered route `Id` at commit.
- Cap pooled staging objects independently with `MaxBitFrameStagePoolSize` (default 8), instead of sharing the 64-object generic batch cap.
- Add stage pool configuration to memory diagnostics and paired `StagePoolMemoryRegression` Studio tests.

## v2.6.0 — Allocation-free scalar staging and unsigned integer encoding

- Specialize BitFrame dynamic tiny scalar events/states and single U8/Bool schema events/states to avoid per-message args tables.
- Dispatch scalar values through the existing scalar lane after packet validation.
- Encode 0–127 BitFrame unsigned integers using a direct one-byte write; reuse the same writer function for `varUInt` and `adaptiveUInt`.
- Add paired `AtomicScalarRegression` Studio tests.

## v2.5.0 — Retained-heap discipline and small-integer decode

- Bound retained decoded action staging arrays with `MaxPooledBitFrameActions` (default 64).
- Record `BitFrameStagePoolHits`, `BitFrameAtomicRejectedPackets`, and `BitFrameAtomicDiscardedActions`.
- Inline the common one-byte adaptive uint decoder, preserving noncanonical, truncation, overflow and safe-integer rejection.

## v2.4.0 — Transactional inbound BitFrame decoding

- Parse entire BitFrame into reusable structure-of-arrays staging storage before applying event dispatch, RPC effects or state updates.
- Validate the end bit and all trailing padding, then commit staged actions in FIFO order; reject malformed packets without partial gameplay mutations.
- Keep schema-run token-bucket allowance applied as a group only after validation.
- Recycle staged scratch and release argument objects on parsing failures.
- Add paired `AtomicPacketRegression` malformed-packet recovery tests.
- The legacy non-BitFrame decoder is unchanged.

## v2.3.37 — Binary F64 and small-string decoding optimization

- Preflight 64-bit BitFrame float encoding and decoding with a single capacity or bounds check.
- Decode short hybrid strings into one bounded binary buffer rather than constructing a table and a string per byte.
- Add paired `BinaryPrecisionRegression` Studio tests for 80 F64 tuples and five small strings.

## v2.3.36 — Oversized packed-run recovery

- Split a single oversized packed-schema message into a prefix and deferred suffix, retaining reliable event FIFO order.
- Bound packed-run lengths by BitFrame and outgoing transport byte capacities even when the bandwidth governor is off.
- Add `PackedRunBatchSplits` statistics and paired `PackedBudgetRegression` Studio tests.

## v2.3.35 — State rate-limit correctness and configuration validation

- In both schema and dynamic BitFrame state decoders, check route rate allowance before mutating the stored state.
- Require `MaxBatchMessages` to be a bounded integer (1–65535) while keeping incoming and outgoing batch limits independently configurable.
- Add paired `StateThrottleRegression` Studio tests for blocked state updates.

## v2.3.34 — Unaligned binary string decoding and pool trim

- Decode unaligned schema strings of 16–63 bytes into a binary buffer instead of allocating a character table and per-character strings.
- Add `NetStream.TrimPools()` for explicit release of idle pool storage, without altering queued messages or active objects.
- Add `AllWriterPoolsBytes` and `ScratchWriterPooledBytes` memory diagnostics.
- Add a dedicated paired Studio regression for U8 packed runs, unaligned strings and trimming. Live Studio results remain pending.

## v2.3.33 — Smaller binary writer pools

- Initialize BitFrame writers to 128 bytes by default, rather than 1024 bytes, expanding on demand.
- Limit idle BitFrame writer retention to 4096 bytes by default, preserving the existing global writer cap for legacy paths.
- Expose binary writer pool capacity and configuration in memory diagnostics.

## v2.3.32 — Packed run memory allocation correction

- Stop allocating space for `MaxBatchMessages` whenever a single packed message is created; start with only the fields needed for one message.
- Skip re-pooling packed arrays used for more than `MaxPooledPackedValues` values (default 64), preventing large transient runs from permanently retaining oversized arrays.
- Add `PackedValuePoolOversizeDrops` and validate `MaxPooledPackedValues`.
- Preserve the existing BitFrame v1 format and Compression v2.3.5 codec.

## v2.3.31 — Legacy fixed-schema composite float validation

- Reject NaN and positive/negative infinity in ten legacy fixed-schema composite F64 read sites (UDim, UDim2, Rect, NumberRange and DateTime).
- Retain fixed field widths and unchanged BitFrame v1 / legacy protocol bytes.
- Add `LegacyFixedFiniteGuard` paired Studio scripts for three invalid F64 payloads and recovery.

## v2.3.30 — Packed U8 BitFrame read/write preflight

- For 2–32 U8 schema fields, ensure write capacity once and directly write bytes to the BitFrame buffer.
- Preflight read bounds once and read bytes directly, preserving field order and bit alignment.
- Source-level randomized checks covered 10,000 U8 tuples and varying initial bit offsets; this is not a Roblox Studio benchmark.

## v2.3.29 — Avoid repeated BitFrame varuint validation

- `BitFrameWriter:varUInt` now validates and sizes its integer once before calling the existing unchecked internal bit writer.
- Source-level parity checks covered 6,014 valid cases and eight invalid values, without changing the canonical varuint representation.

## v2.3.28 — Control-remote rebind and varuint hot-path handling

- `RetryHandshake()` now re-resolves a replacement `H` RemoteEvent even if an older control remote was referenced.
- Replace rather than accumulate client handshake listeners; add `HandshakeRemoteRebinds` stats.
- Skip duplicate varuint validation after the BitFrame writer has already validated the requested encoding size; public writer remains guarded.
- Add a paired handshake rebind test, preserving BitFrame v1 and compression codec 230.

## v2.3.27 — Non-finite BitFrame float rejection

- Reject NaN and positive/negative infinity at the shared BitFrame F32/F64 reader boundary, including composite schema fields such as `UDim.Scale`.
- Prevent malformed float values reaching gameplay callbacks and preserve the decoder error path and later valid traffic.
- Add a server/client malformed-bitframe regression pair, including valid traffic recovery.
- No packet field widths, protocol IDs, or compression formats changed.

## v2.3.26 — Adaptive uint encoding input safety

- Reject negative, fractional, non-finite, non-number, or over-safe-range integers before the adaptive encoder can loop or emit invalid data.
- Apply the same bounded integer contract to adaptive byte-length estimates so the size predictor matches the encoder.
- Extend `VarUIntRegression.server.lua` with invalid-input and maximum safe integer coverage.
- Preserve the existing canonical varuint wire representation and decoder.

## v2.3.25 — Compression eligibility allocation reduction

- Scans argument lists containing at most eight values for compressible tables or repeated eligible strings **without constructing a temporary dictionary**.
- Uses a dictionary for longer argument lists to keep lookup work bounded.
- Preserves the existing compression candidate decision and encoding format.
- Adds `CompressionEligibilityShortScans` and `CompressionEligibilityShortSkips` in `GetStats()`, and `EligibilityShortScans` / `EligibilityShortSkips` in `GetCompressionStats()`.
- Adds the `CompressionEligibility.server.lua` / `.client.lua` Studio regression pair.

## v2.3.24 — Homogeneous U8 schema fast path

- Compiles a `byteRunU8` flag for schemas with **2–32 U8 fields**.
- Encodes/decodes these fields directly using eight-bit buffer operations, avoiding the generic schema kind-dispatch loop.
- Preserves the same 8-bit-per-field wire representation and default BitFrame v1 protocol.
- Adds `U8SchemaFastWrites` and `U8SchemaFastReads` counters and 4/32-field Studio probes.

## v2.3.23 — Handshake HELLO retry recovery

- When a server peer is already READY but receives a matching duplicate HELLO, it **resends WELCOME**, not READY. This allows a client that is still waiting in HELLO to move through CONFIRM and READY.
- Maintains stale-nonce replay protection, compatibility checks and retry limits.
- Adds `HandshakeRecoveredHellos` counter and an explicit handshake recovery Studio probe.
- This change is not encryption, authentication or a new anti-cheat mechanism.

## Earlier releases (selected)

| Version | Focus |
|---|---|
| 2.3.22 | Allocation-free deferred queue restoration |
| 2.3.21 | BitFrame Boolean schema fast path, 2–32 fields |
| 2.3.20 | Writer-pool error cleanup and strict BitFrame tail padding |
| 2.3.19 | Queue/payload/memory diagnostics, p50/p95/p99 RTT and jitter |
| 2.3.18 | Encoder, decoder, dispatch and outgoing packet size timing |
| 2.3.17 | Bounded percentile samples and public telemetry API |
| 2.3.16 | Adaptive per-route compression CPU budget |
| 2.3.15 | BitFrame reader pooling and dictionary cleanup |
| 2.3.14 | Handshake nonce replay and duplicate handling |
| 2.3.13 | Fast flush scheduling |
| 2.3.12 | Realtime compression skip and scratch writer pooling |
| 2.3.11 | Dedicated HELLO/WELCOME/CONFIRM/READY control handshake |
| 2.3.8–2.3.10 | Reliability fixes, compression/packet bounds and lane splitting |
| 2.3.5–2.3.7 | BitFrame/packing and performance maintenance |
| 2.3.2–2.3.4 | Regression fixes and source hardening |

The original detailed v2.3.22 README is preserved in [README_LEGACY_v2.3.22.md](README_LEGACY_v2.3.22.md). For the current usage guide see [README](../README.md).
