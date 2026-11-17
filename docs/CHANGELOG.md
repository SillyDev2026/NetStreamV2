# NetStreamV2 Changelog

The current release is **v2.9.0**, using **BitFrame v1** and the bundled **Compression v2.3.5** (codec **230**). Release notes describe implemented source changes. Roblox Studio performance results are **not yet measured**.

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
