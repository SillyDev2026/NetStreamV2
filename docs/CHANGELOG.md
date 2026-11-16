# NetStreamV2 Changelog

The current release is **v2.3.31**, using **BitFrame v1** and the bundled **Compression v2.3.5** (codec **230**). Release notes describe implemented source changes. Roblox Studio performance results are **not yet measured**.

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
