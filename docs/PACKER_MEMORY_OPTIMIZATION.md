# Codec memory and packer optimization (unreleased)

## What changed

- `NetStream.Codec._EncodeArgs` now borrows a bounded transport writer instead of allocating a new `Writer` object and 256-byte backing buffer for every call.
- `NetStream.Codec._DecodeArgs` now borrows a bounded transport reader and returns it even when a malformed native packet throws. This avoids allocating fresh reader metadata and string-dictionary tables for routine decoding and rejected packets.
- `Codec.Encode`, `Codec.TryEncode`, and `Codec.Analyze` reuse the existing bounded argument-array pool. For successful calls, temporary arrays are returned immediately. Unexpected encoding errors discard the partially written writer for garbage collection rather than recycling potentially inconsistent state.
- `Writer:varUInt` now directly writes single-byte values and reserves the **actual** required varint size when close to capacity. Previously, it pessimistically reserved eight bytes, sometimes rejecting a valid short varint at the output boundary.
- `BitFrameWriter:adaptiveUInt` avoids the `ensureBits` helper when a one-byte ID fits in its current buffer.

**Wire format is unchanged**: default BitFrame v1, legacy fallback, Compression v2.4.2 and codec 230 are compatible with the previous build. No claim of reduced bytes-per-packet is made; these are temporary allocation and CPU-path optimizations.

## Reproduce

```sh
# Requires official Luau CLI
node scripts/runtime-tests.mjs --profile-only
node scripts/runtime-tests.mjs --compare-only
node scripts/runtime-tests.mjs
node scripts/runtime-tests.mjs --stress-only
```

GitHub CI runs all three commands on the pinned Luau toolchain. The benchmark compares an untouched `main` baseline branch (`bench/packer-baseline-v431`) with the optimized feature branch (`perf/codec-pools-packer-v431`), using identical `tests/runtime/packer_profile.luau` workloads.

The profile prints best-of-three Luau CPU timings, writer/reader pool hits, and golden packet bytes. CI worker variation and compiler warmup can affect timings, so treat a single comparison as **indicative**, not a controlled performance guarantee. `tests/runtime/packer_regression.luau` asserts 2,750 pooled encode/decode cycles, malformed-input recovery, unchanged golden wire bytes, and exact max-size varint boundaries.

## Production limitations

- Pool hits are evidence of reuse, not a direct measurement of Lua heap or Roblox engine allocation counts.
- These optimizations do not reduce network ping or Roblox RemoteEvent overhead.
- Real Studio MicroProfiler, heap snapshots, and matched throughput tests against Zap/Blink/ByteNet remain needed to establish production efficiency.
- Large persistent application payloads still dominate memory; app code must respect configured size limits and avoid constructing unnecessary temporary tables.
