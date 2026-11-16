# NetStreamV2 Benchmarks and Release Verification

**Baseline:** v2.3.28. **Candidate:** v2.3.34. No benchmark values are pre-filled: results must be measured in Roblox Studio.

## Test environment

Place the repository's `Netstream.lua` ModuleScript in `ReplicatedStorage` with `Compression.lua` as its `Compression` child. Place one `tests/*.server.lua` file in `ServerScriptService` and its matching `*.client.lua` in `StarterPlayerScripts`. Keep separate Play sessions for each pair.

| Test pair | Purpose |
|---|---|
| `MemoryBinaryRegression` | Packed U8 96-message runs, 16/32/63-byte string binary round-trips and idle pool trim |
| `LegacyFixedFiniteGuard` | Reject three malformed legacy fixed-schema composite F64 payloads and accept subsequent valid traffic |
| `HandshakeRecovery` | Validates HELLO/WELCOME/CONFIRM/READY retry after server is READY |
| `U8FastPath` | 4/32-U8 tuples, bounds 0/128/255, FIFO, counters |
| `CompressionEligibility` | 64 ineligible short arguments, 32 repeated strings, lossless decode |
| `BitFrameHardening` | Invalid physical tail, pooled-writer recovery |
| `BooleanQueueRegression` | Packed Boolean path, split batches and FIFO |
| `PerformanceP95` | 128 real client-observed application-level ping/pong cycles |
| `PerformancePercentiles` | Deterministic nearest-rank and ring-buffer arithmetic |
| `CpuMemoryRegression` | Bounded pools, compressed packet workload |
| `HandshakeReplayRegression` | Stale nonce replay handling |
| `BatchLaneRegression` | Reliable/unreliable lane and packet splitting |
| `BitFramePerfProbe` | 300 mixed-size events and counters |

**Important:** Tests listed here are authored source, not tests that have been executed by GitHub or this README. Confirm both server and client scripts run and fail the Play session on assertions. Some older suites depend on specific Studio placement or configured remotes; read their header before running.

## P50/P95/P99 definitions

`NetStream.GetLatencyStats()` returns per-metric sample objects with `Count`, `Observed`, `TotalSamples`, `Min`, `Max`, `Mean`, `P50`, `P95`, `P99`.

- **P50:** observed latency at or below which at least 50% of retained samples lie
- **P95:** at least 95% of retained samples
- **P99:** at least 99% of retained samples

The code uses nearest-rank indexing (`ceil(count * percentile)`). A missing sample returns `nil`; do not substitute 0 ms. Since measurements are sampled and retained in a bounded ring, results only reflect **retained observations**, not all lifetime traffic.

`RoundTripMs` must be explicitly recorded by a client-side ping/pong benchmark using `RecordRoundTripSample`. Handshake RTT is a different metric. `JitterMs` represents the absolute difference between sequential recorded RTTs (not network packet-delay variation per RFC 3550).

## Suggested performance matrix

| Workload | Players | Message size/shape | Send pattern |
|---|---:|---|---|
| Short integers | 1, 10, 25 | U8/U16/fixed schema | 30, 60, 120 updates/s |
| Boolean flags | 1, 10, 25 | 2–32 Bool schema | Normal/realtime |
| Large repeated strings | 1, 10, 25 | 2–8 repeated dynamic arguments | Normal |
| State churn | 1, 10, 25 | Replaceable state events | Latest/coalescing on/off |
| Mixed batches | 1, 10, 25, 50 | Realistic 30–900-byte payloads | Reliable/unreliable |
| Malformed/oversized | 1, 10 | Structurally invalid test buffers | Defensive only |

Start with a warm-up phase, then run equal-duration steady-state trials at identical player count, server settings, route declarations, payload values and machine/network conditions. Prefer at least three repeated runs and report variability. Run with telemetry enabled **and** disabled to estimate instrumentation overhead.

### Baseline comparison sheet

| Version | Workload | Messages/s | Enc. P95 (ms) | Dec. P95 (ms) | RTT P95 (ms) | RTT P99 (ms) | Avg packet bytes | Luau heap KB |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| v2.3.22 | Fill in after Studio test | — | — | — | — | — | — | — |
| v2.3.25 | Same workload and environment | — | — | — | — | — | — | — |

Don't infer a speedup from a source-level refactor, number of performance counters, or a single small simulation.

## Useful console diagnostics

```luau
NetStream.Configure({
    PerformanceTelemetryEnabled = true,
    PerformanceTelemetryCapacity = 512,
    PerformanceTelemetrySampleEvery = 1,
})
NetStream.Start()

local sample = NetStream.GetLatencyStats()
local net = NetStream.GetStats()
local compression = NetStream.GetCompressionStats()
local memory = NetStream.GetMemoryDiagnostics()

print("Encode P50/P95/P99:", sample.EncodeMs.P50, sample.EncodeMs.P95, sample.EncodeMs.P99)
print("Decode P50/P95/P99:", sample.DecodeMs.P50, sample.DecodeMs.P95, sample.DecodeMs.P99)
print("Round trip P95/P99:", sample.RoundTripMs.P95, sample.RoundTripMs.P99)
print("Sample count:", sample.RoundTripMs.Count)
print("Sent / received bytes:", net.SentBytes, net.ReceivedBytes)
print("Decode errors:", net.DecodeErrors)
print("U8 fast writes / reads:", net.U8SchemaFastWrites, net.U8SchemaFastReads)
print("Handshake recovered HELLOs:", net.HandshakeRecoveredHellos)
print("Compression fast skips:", compression.EligibilityShortSkips)
print("Retained writer capacity (bytes):", memory.PooledWriterBytes)
print("Overall Luau heap (KiB):", memory.LuaHeapKB)
```

## Release checklist

- [ ] Client and server use NetStream v2.3.25 and bundled Compression v2.3.5
- [ ] Both sides agree on BitFrame setting, route IDs and schemas
- [ ] At least one reliable and one unreliable lane scenario tested
- [ ] HandshakeRecovery and HandshakeReplayRegression pass
- [ ] U8FastPath and BooleanQueueRegression pass
- [ ] CompressionEligibility and BundledCompressionRegression pass
- [ ] BitFrameHardening and malformed packet checks pass
- [ ] RPC timeout, server authorization and reconnect scenarios pass
- [ ] No unintended `FallbackReliable` growth
- [ ] Zero unexpected decode errors in valid-traffic tests
- [ ] Compared p50/p95/p99, CPU, memory and GC against v2.3.22
- [ ] Confirmed no regression in gameplay, data integrity or stable server performance

## What the metrics cannot prove

Reported `PacketBytes` excludes engine, IP/UDP and transport header overhead. `PooledWriterBytes` is retained buffer capacity, not the total module memory. `LuaHeapKB` is broad Luau heap usage. CPU measurements are local encoding/decoding/dispatch wall-clock sample durations, not whole-device CPU utilization. The physical network RTT depends on Roblox server location, transport, device and internet conditions.

Do not publish performance rankings or claimed speedups against Blink, Zap, Jolt, ByteNet or other modules without running the same workload and environment.

Back to [README](../README.md) · [Architecture](ARCHITECTURE.md) · [Future options](NEXT_OPTIONS.md).
## Memory comparison protocol

Measure v2.3.31 and v2.3.34 with the **same** settings, payloads and player counts. Run an initial warm-up; capture `GetMemoryDiagnostics()` and `gcinfo()` before and after at least 10,000 packets and an idle stabilization period. Note that `gcinfo()` is whole-VM heap usage and garbage collection timing affects snapshots. Compare `BitFrameWriterPooledBytes`, `PackedValuePoolOversizeDrops`, writer pool sizes, packet p95, encode/decode p95, RTT p95/p99 and jitter. Use `TrimPools()` only in an explicitly separate post-load measurement, never mid-benchmark. Static CI cannot prove Roblox runtime heap reduction.
