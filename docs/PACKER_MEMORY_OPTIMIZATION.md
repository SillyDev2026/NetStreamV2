# Codec Memory and Packer Optimization

> **Status:** Implemented on the v4.3.1-compatible `main` branch. Fast paths preserve BitFrame v1, codec 230, and valid encoded packet bytes. The limitations and measured trade-offs below still apply.

## Implementation summary

- A new **tiny native tuple path** handles up to four nil, boolean, small signed/unsigned integer, or short distinct-string values directly. A tiny encode creates only the final packet buffer; a tiny decode builds the returned value table without allocating a Reader wrapper. Duplicate strings, longer strings, extended numbers, tables and other values automatically fall back to the existing codec. Byte format is identical to the pre-patch native codec.
- Decoded native messages still follow the original validation rules, including the exact count and trailing-byte checks. Fuzz tests and golden-byte tests cover the new parser.

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

GitHub CI runs these commands on the pinned Luau toolchain. The historical baseline branch (`bench/packer-baseline-v431`) and optimized branch (`perf/codec-pools-packer-v431`) use the same `tests/runtime/packer_profile.luau` workloads. For a fairer CPU comparison on current code, `--compare-only` runs the original and optimized native Codec paths within one Luau process.

The profile prints best-of-three Luau CPU timings, writer/reader pool hits, and golden packet bytes. CI worker variation and compiler warmup can affect timings, so treat a single comparison as **indicative**, not a controlled performance guarantee. `tests/runtime/packer_regression.luau` tests 2,500 direct tiny-tuple cycles, 250 complex pooled cycles, malformed-input recovery, golden wire bytes, and exact max-size varint boundaries.

## Same-process A/B results (single sample)

On the pinned official Luau CLI in [CI run 44510402505](https://github.com/SillyDev2026/NetStreamV2/actions/runs/44510402505), old per-call Writer.new/Reader.new behavior and the optimized public Codec API ran in the **same process**. Best-of-four timed loops produced:

| Native Codec case | Original | Optimized | Measured change |
| --- | ---: | ---: | ---: |
| Small tuple encode | 1,930.8 ns/op | 1,140.5 ns/op | 40.9% faster |
| Small tuple decode | 1,458.0 ns/op | 841.3 ns/op | 42.3% faster |
| Structured tuple encode | 8,878.0 ns/op | 9,364.5 ns/op | 5.5% slower |
| Structured tuple decode | 7,420.1 ns/op | 7,624.1 ns/op | 2.7% slower |

The tiny fast path is the main CPU win. For structured payloads, the bounded
pool currently has a small measured CPU cost; its purpose is to reduce
temporary wrapper/backing-buffer allocation and GC churn. There is **no claim
of an overall throughput gain** for every application workload. Writer/reader
pool-hit counters demonstrate reuse but do not quantify Roblox heap savings.

## Codec input and output limits

The follow-up fix merged in PR #22 enforces `MaxTableEntries` for standalone argument counts, including tiny tuples, and `MaxOutgoingBatchBytes` for all native writer paths even when the backing buffer has spare capacity. These are correctness protections, not new packet encodings.

## Production limitations

- Pool hits are evidence of reuse, not a direct measurement of Lua heap or Roblox engine allocation counts.
- These optimizations do not reduce network ping or Roblox RemoteEvent overhead.
- Real Studio MicroProfiler, heap snapshots, and matched throughput tests against Zap/Blink/ByteNet remain needed to establish production efficiency.
- Large persistent application payloads still dominate memory; app code must respect configured size limits and avoid constructing unnecessary temporary tables.

## Related documentation

- [Memory retention and pool sizing](MEMORY_EFFICIENCY.md)
- [Performance methodology](BENCHMARKING.md)
- [Main README](../README.md)
