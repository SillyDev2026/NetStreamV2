# NetStreamV2 Changelog

The current release is **v4.0.0**, using **BitFrame v1** and bundled **Compression v2.4.0** (codec **230**). Release notes describe implemented source changes. Roblox Studio performance results are **not yet measured**.

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
