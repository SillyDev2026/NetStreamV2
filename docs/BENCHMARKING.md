# Benchmarking and Release Verification

> **Current branch:** v4.3.1-compatible `main`, BitFrame v1, Compression v2.4.2 (codec 230). The historical v4.2.3 → v4.3.0 comparison procedures below remain as references; they are **not** current measured release results.

This guide distinguishes **standalone Luau microbenchmarks**, which measure code-path CPU time, from **Roblox Studio measurements**, which are required to evaluate real networking, memory, and frame-time behavior. Do not compare libraries using different payloads, player counts, protocol options, or hardware.

## Recommended verification sequence

1. Run `node scripts/source-audit.mjs` and `node scripts/runtime-tests.mjs` in the repository root.
2. Run `node scripts/runtime-tests.mjs --stress-only` to exercise the deterministic simulated-server workload.
3. Run `node scripts/runtime-tests.mjs --compare-only` for a same-process native Codec A/B CPU sample, and `--profile-only` for the packer microbenchmarks.
4. Run the paired `tests/*.server.lua` and `tests/*.client.lua` suites in separate Roblox Studio Play sessions.
5. Record engine CPU p50/p95/p99, allocation and post-GC heap, encoded bytes, delivery loss, queue pressure, and callback outcomes under equal loads.

Standalone runs can establish **functional regressions and sample CPU costs**, but **not** real Roblox network latency or a production memory reduction. See [Runtime validation](RUNTIME_VALIDATION.md), [Server stress](SERVER_STRESS_VALIDATION.md), and [Packer profiling](PACKER_MEMORY_OPTIMIZATION.md).



## Roblox Studio test environment

Place the repository's `Netstream.lua` ModuleScript in `ReplicatedStorage` with `Compression.lua` as its `Compression` child. Place one `tests/*.server.lua` file in `ServerScriptService` and its matching `*.client.lua` in `StarterPlayerScripts`. Keep separate Play sessions for each pair.

| Test pair | Purpose |
|---|---|
| `RPCConcurrencyRegression` | 16 simultaneous RPC calls, two-in-flight player cap, application-error and recovery validation |
| `MemoryRetentionRegression` | 1,200 ordered U16 packets + 128 unique strings; verify sparse queue compaction, dictionary trim, drain and FIFO |
| `TypedTupleABBenchmark` | Two-sided A/B probe, 512 U16 + 512 U32 12-field events; encoded bytes and encode/decode p95 |
| `HomogeneousIntegerRunRegression` | 12-field U16/U32 packed runs, boundary values, FIFO, paired echoes, fast path counters |
| `DispatchFairnessRegression` | 160-message client burst; validates per-player queue cap and dropped work stats |
| `BroadcastBudgetRegression` | Competing broadcast and per-player traffic; validates budget slicing and send path |
| `DeltaCodecRegression` | Paired full-to-delta apply, field deletion, wrong base and malformed mask rejection |
| `InterestGroupRegression` | Paired interest membership filtering, state fanout and no excluded events |
| `MixedFixedSchemaRegression` | 40 mixed 12-field Bool/U8/U16/I16/U32/I32 round trips, boundary/FIFO checks and fast-path counters |
| `PackedScalarRunRegression` | Single-field U16 and Bool runs, FIFO, signed group continuation rate-limit semantics |
| `PackedHighWaterRegression` | Correct packed-run FIFO and discarding oversized backing tables despite later small run slices |
| `ScalarThrottleHeapRegression` | Scalar route-level rejection, no argument-table cleanup error, accepted value preserved |
| `DynamicDiscardHeapRegression` | Globally rejected dynamic args are validated without acquiring an args table |
| `BoundedPoolRegression` | Idle pool caps set to zero, correct FIFO, no retained batch/args/message tables |
| `FixedDiscardRegression` | Mixed fixed-width rate-limited schema skipping, float fallback, no unwanted event dispatch |
| `ExtendedScalarStringRegression` | Numeric U16/I16/U32/I32/F32/F64 scalar events, F64 state, short binary strings |
| `HeapDiscardRegression` | Prove rejected U8/packed-boolean schema messages validate without args-table materialization |
| `StagePoolMemoryRegression` | Validate stage pool cap zero and 16 scalar packets without retaining idle stages |
| `AtomicPacketRegression` | Stage a valid state frame with corrupt padding; confirm no dispatch/state mutation; then recover |
| `AtomicScalarRegression` | Test tiny scalars including nil, schema U8/Bool, scalar states and response |
| `StateThrottleRegression` | Schema and dynamic state rate-limits reject state mutation |
| `PackedBudgetRegression` | FIFO and batch packet splits under a 48-byte byte-budget |
| `BinaryPrecisionRegression` | F64 values and hybrid short-string binary round-trips |
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

## RPC concurrency and argument-copy performance

Run `RPCConcurrencyRegression.server.lua` and `RPCConcurrencyRegression.client.lua` in isolation. It tests a two-callback-per-player cap under a 16-call burst and a post-exception recovery. For benchmarks compare capped and uncapped configurations at 1/10/25 players with identical yielding callback duration, call rates and hardware. Record live/peak active callbacks, rejected/timed-out calls, `GetHealth().RPCUtilization`, server heap after GC, CPU scheduling, and callback turnaround p95/p99. This cap protects outstanding tasks, not per-second CPU work; use both controls together.

Compare the 4–8 and 12-field direct vararg copier against the earlier v4.3.0 commit under identical payloads and message rates. Encoding/decoding p95, allocations and GC must be measured in Roblox Studio; the code change alone does not prove speed. See [RPC concurrency](RPC_CONCURRENCY.md).

## v4.3.0 idle-memory and sparse queue measurements

Run `MemoryRetentionRegression.server.lua` and `MemoryRetentionRegression.client.lua` in an isolated Studio session. Use the intentionally tight dictionary/queue retention caps from the scripts only for testing, and observe `QueueCompactions`, `QueueStorageRebuilds`, `DictionaryPoolRebuilds` and `PooledWriterResets` through `GetMemoryDiagnostics()`. Then compare old and new commit under identical sustained traffic and post-burst idle periods. Record stabilized Luau heap (via `gcinfo()` / Studio memory profiler), allocation spikes, GC duration, encode/decode/flush p95 and throughput. Trimming capacity lowers expected idle retention but can increase allocation churn. Source audit and parser compilation are not equivalent to a measured memory reduction. See [memory retention audit](MEMORY_EFFICIENCY.md).

## Running the built-in typed tuple A/B probe

Place `tests/TypedTupleABBenchmark.server.lua` in `ServerScriptService` and its paired client script in `StarterPlayerScripts`. Create a `BoolValue` named `NSTypedTupleFastPath` under `ReplicatedStorage` with `Value=false`. Run the session, capture the printed `fast=false` server/client lines, then change the value to `true` and start a **fresh** session with the exact same player count and conditions. Repeat each profile multiple times with a warmup. The probe enqueues 512 contiguous U16 and 512 contiguous U32 12-field events, prints encoded bytes per message and p95 encode/decode samples, and asserts correct receipt. This is a traffic/CPU probe, **not** a normalized cross-library leaderboard; the elapsed wall clock includes scheduling, startup and remote latency.

## v4.3.0 controlled serializer A/B protocol

Use identical Studio server/client settings for separate trials with `NetStream.Configure({TypedTupleFastPathEnabled=false})` (previous codec) and `NetStream.Configure({TypedTupleFastPathEnabled=true})` (new codec). Keep schema (2, 12, 32 U16 or U32 fields), identical values, players (1/10/25), 30/60/120 messages per second, batching, compression, and test duration fixed. Warm up first and repeat each trial at least three times. Record encoded buffer bytes/message, encoded packets/sec, encode/decode p50/p95/p99 CPU, Luau heap/GC, dropped/queued messages, and client-observed RTT. Check that homogeneous fast-path counters stay at zero with the toggle false and rise with it true.

Compare BlinkBlox, Zap, Satset and ByteNet only with the *same schemas, validation settings, reliability, message rate, batching, player count, hardware and runtime*. Use a shared place file and retain the actual benchmark scripts/results. Raw buffer lengths are not equivalent to Roblox transport bytes. No best-in-class performance claim before matched results.

## v4.3.0 server processing comparison

Compare v4.2.3 and v4.3.0 under identical 1/10/25-player Studio sessions. Mix a noisy sender (160–5,000 queued messages) with quiet players and high broadcast volume. Record per-player callback delivery, global/per-player dispatch drops, queue peak, p95/p99 dispatch CPU and queue time, GC pauses, RTT and Roblox-reported bandwidth. Repeat with `DispatchPerPlayerBacklogLimit=0` and `BroadcastFlushBudgetFraction=1` to isolate scheduling effects. Verify surviving reliable FIFO and disconnect cleanup. Callback queue admission can drop work under pressure; critical gameplay requests need application-level acknowledgment/retry if this behavior is unacceptable.

## v4.2.1–v4.2.3 acceptance benchmarks

Execute each new server/client regression in a separate Roblox Studio Play session. Compare 12-field mixed schema packet bytes, encode/decode p95/p99 and Luau heap on v4.2.0 vs v4.2.3; compare total wire bytes for full snapshots and 1/2-field deltas vs complete state sends, including reconnect and out-of-order rejection. For interest groups, compare 1/10/25-player fanouts with different active subscriptions, ensuring zero excluded-client deliveries. Record actual CPU, queue, RT and byte metrics before claiming improvements; source CI alone is not a Roblox Studio benchmark.

## v4.2.0 mixed-schema performance checks

Compare v4.1.1 against v4.2.0 using the same 12-field mixed Bool/U8/U16/I16/U32/I32 event route with 1/10/25 clients. Repeat with `PackedSchemaRunMaxFields` at 8 and 16. Measure encoded bytes per logical message, packet counts, encode/decode p95/p99, Luau heap after GC, packet deferrals/drops and application RTT. A higher packed-field limit can reduce repeated headers but increase temporary allocations. Run the paired Studio `MixedFixedSchemaRegression` before production use; static source-audit does not execute Roblox networking.

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

- [ ] Client and server use NetStream v4.0.0 and bundled Compression v2.4.0 (codec 230)
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

## v2.3.35–v2.3.37 performance comparison

Run each paired Studio regression in a **separate Play session**, then execute `PerformanceP95` and `CpuMemoryRegression` at identical settings on v2.3.34 and v2.3.37. Report 128, 1,024 and 10,000 probe runs where practical. Compare binary writer retained bytes, Luau VM heap after GC stabilization, encode/decode p95, dispatch p95, queue p95, packet bytes p95 and RTT p50/p95/p99. Do not infer total VM heap savings or lower transport ping solely from source-level checks. CI parsing does not execute Roblox multiplayer scripts.

## Release-line performance matrix

| Dimension | v2.3.37 baseline | v2.4.0 | v2.5.0 | v2.6.0 |
|---|---|---|---|---|
| Corrupt BitFrame tail side effects | Possible | Transactional decode | Retained | Retained |
| Staging memory bound | N/A | Pooled scratch | MaxPooledBitFrameActions=64 | Same |
| One-byte uint fast-path read/write | Generic | Generic | Read | Read + write |
| Direct staged tiny scalar | No | No | No | Yes |
| Studio RTT p95/p99 and Luau heap | Measure | Measure | Measure | Measure |

Run paired Studio scripts **separately**, checking server and client Output for PASS and unexpected warnings. For performance claims use controlled identical workloads, garbage-collection stabilization, and a minimum of several trials per release; CI source checks alone do not quantify a speed-up.

## 2.6.0 → 2.9.0 memory and CPU comparison

Run `AtomicPacketRegression`, `AtomicScalarRegression`, `HeapDiscardRegression`, and `StagePoolMemoryRegression` as separate Play sessions; compare the two versions under identical packet payloads and settings. Verify `BitFrameDiscardedSchemaArgs` for rejected traffic. Record idle `BitFrameStagePoolSize`, `BitFrameWriterPooledBytes`, `gcinfo()` after garbage-collection stabilization, decoded messages, CPU encode/decode p95, queue p95, packet p95 bytes, and RTT p95/p99.

Static checks confirm structural changes and binary layouts, not actual runtime memory reductions or ping improvements.

## v3.2.0 comparison protocol

Use separate identical server/client sessions for each paired Studio script. Measure v2.9.0 and v3.2.0 with matching players, event rates, schemas, packets, compression configuration and telemetry sampling. Report server and client Luau heap KB (with stabilized garbage collection), encoded packet bytes p95, encode and decode CPU p95, dispatch/queue p95, RTT p50/p95/p99 and jitter. Source-level CI checks prove syntax and invariants only; they **do not** prove lower network ping, fewer GC cycles, or speed improvements.

## v3.5.0 CPU/heap/GC comparison

Run identical v3.2.0 and v3.5.0 Studio sessions with the same player count, numeric/event schemas, event rate, payload distribution, traffic throttles and compression settings. Include a sustained 10,000-message small-scalar workload, a batched 32–256 message workload, a rejected schema-run workload, and an idle-after-burst period. Collect `GetStats()`, `GetMemoryDiagnostics()`, `GetLatencyStats()`, Lua heap KB (`gcinfo()`), MicroProfiler network decode/dispatch CPU and observed GC pauses. Report p50/p95/p99 and allocation/GC measures as *observations*, not a 1–10 speed rating. Smaller pool caps may raise churn under constant saturation; compare stable throughput before selecting a lower cap.

## v3.8.0 CPU / heap / GC comparison

Compare v3.5.0 and v3.8.0 under identical Play Solo and multi-client Studio sessions. Run (a) 10,000 single-, two- and three-value messages; (b) sustained one-field U16 and Bool packed runs; and (c) bursty 96-event U8×8 traffic under a small outbound byte cap. Record per-path CPU p50/p95/p99 with the MicroProfiler, `GetStats().BitFramePackedScalarRunItems`, `GetMemoryDiagnostics().PackedValueHighWaterDrops`, `gcinfo()` before/during/after stable loads, packet bytes and observed garbage collector pauses. Validate callback order, no decoding errors, and rejected packet accounting. No observed results have been prefilled.


## v3.9.0 burst throughput validation — run before performance claims

Place `BurstSaturationBenchmark.server.lua` in ServerScriptService and `BurstSaturationBenchmark.client.lua` in StarterPlayerScripts for a clean Play session. Do not simultaneously run other test pairs. Both disable the handshake, compression, fast flushing and bandwidth governor **only for the isolated benchmark**, and enable telemetry. They send 10,000 single U16 messages, 10,000 alternating Bool messages and 10,000 eight-field U8 messages, paced 128 per Heartbeat. On the server, all values and per-route FIFO indices must match exactly; on completion the server acknowledges 30,000 logical messages. Any assertion or timeout is a failed run, not a successful measurement.

1. Run the paired test at v3.8.0 (edit only benchmark version assertions to that baseline if copying these new scripts there); record sender enqueue seconds, encode p50/p95/p99, send bytes, receive decode p50/p95/p99, dispatch p50/p95/p99, queue latency, server/client Luau heap KB and garbage collector pauses from MicroProfiler.
2. Replace only Netstream.lua with v3.9.0; rerun same settings, hardware, sample rate, Roblox Studio build, network/region and player count. Repeat at least five times, including a cold-start and warmed-pool run, report median and spread.
3. Repeat with 10 and 25 simulated clients and with governor enabled using real production limits (these paired benchmark defaults intentionally do not validate throughput with the governor on). Keep a separate reliable-versus-unreliable loss test.
4. Run `PackedScalarRunRegression`, `PackedHighWaterRegression`, `PackedBudgetRegression`, `AtomicPacketRegression` and `BoundedPoolRegression` individually. Confirm atomic decode, rate limits, FIFO, packet splitting and retained memory.

**Interpreting metrics:** `BitFramePackedScalarRunWrites` and `BitFramePackedScalarRunItems` are path counters, not percentages. Client enqueue duration includes deliberately paced Heartbeats and is not true wire throughput. Server receive duration, packet rates, CPU times and MicroProfiler GC pauses must be observed separately. Values are deliberately **not filled in until Studio executes**.

| Metric | v3.8.0 baseline | v3.9.0 candidate |
|---|---:|---:|
| Sent + delivered logical messages | — | — |
| Encode p95/p99 (ms) | — | — |
| Decode p95/p99 (ms) | — | — |
| Dispatch p95/p99 (ms) | — | — |
| Effective receiver messages/sec | — | — |
| Client + server heap after GC (KiB) | — | — |
| GC pause p95/p99 (MicroProfiler) | — | — |
| Malformed packets / drops | — | — |


## v4.0.0 / Compression v2.4.0 verification

Run `CompressionV24Regression.server.lua` standalone first, then `PackedScalarRunRegression` and `BurstSaturationBenchmark` with each server/client pair in its own Play session. Confirm no unexpected decode errors, preserved packed Bool/U8/U16 values, FIFO order and rate-limit behavior. `BitFramePackedScalarFastReads` should increase when a packed run of more than one matching field is received.

For a measured comparison, run the same 30,000-message benchmark on NetStream v3.9.0 + Compression v2.3.5 and v4.0.0 + Compression v2.4.0 under otherwise matched conditions. Compare send encode p50/p95/p99, receive decode p50/p95/p99, dispatch p50/p95/p99, effective delivered messages/second, heap/GC pauses and packet bytes. Run at least five trials per configuration. A Compression-specific microbenchmark should run many small numeric and dictionary-heavy payload round-trips and record wall-clock times, peak buffers and output byte parity; do not infer compression ratio improvements from the varuint CPU changes.

The reference codec ID **230** deliberately does not change. No observed Roblox Studio metrics have been committed; source audits and static Luau compilation alone cannot establish performance gains.


## v4.0.1 / Compression v2.4.1 verification checklist

Start with `CompressionV241Regression.server.lua` for codec parity, mixed map keys, false-valued duplicate-key rejection, malformed nil map value, dictionary-heavy nested-map roundtrips, and small scalar packets. Run `DispatchCompactionRegression.server.lua` with its paired `.client.lua` in a fresh Play session to build a sustained dispatch backlog. Confirm that received callbacks remain increasing, `GetStats().DispatchQueueCompactions > 0`, and there are no unexpected decode failures. This deliberate saturation may drop some dispatch events; it is not a reliable-delivery throughput benchmark.

Compare v4.0.0/Compression 2.4.0 with v4.0.1/Compression 2.4.1 in matched Studio sessions using the existing `BurstSaturationBenchmark`, `PackedScalarRunRegression` and Compression round-trips. Report CPU p50/p95/p99, Luau heap after stable GC, event backlog, queue compaction count, encoded byte parity, and payload integrity. Repeat at least five times. Neither the docs nor GitHub Actions supplies live measurements.


## v4.0.2 recovery and codec validation

Run `TransportRecoveryRegression.server.lua` with `TransportRecoveryRegression.client.lua` in a dedicated Studio Play session to exercise an intentionally invalid *trusted* schema event, isolated batch retry, one-packet-per-second throttling, and FIFO delivery of the three valid events. Run `CompressionV242Regression.server.lua` separately to check 600 no-dictionary scalar round-trips, dictionary-rich tables and malformed composite map-key tags.

Compare NetStream v4.0.1/Compression v2.4.1 with v4.0.2/v2.4.2 on identical Roblox Studio loads to measure CPU p95/p99, throughput and heap/GC changes. Do not treat static CI/source modeling as live benchmark results.


## v4.1.0 low-traffic bandwidth benchmark

Run `tests/LowTrafficRegression.server.lua` and `.client.lua` as a paired Studio Play session. It opts into `ConfigureLowTraffic` on both peers, sends a reliable coalesced U16 state once, attempts 64 identical values, changes the value, then repeats the new value and forces a resync using `SetClientNow`. Validate exactly three observed client deliveries and the corresponding suppression counter; running one file without the other cannot pass.

For real savings, run a matched 60-second Roblox Studio autoclick workload using (A) original per-click networking, (B) server-authoritative autoclick and coalesced State updates, and (C) B plus `ConfigureLowTraffic` and `SuppressUnchanged`. Keep player count, scene, click rate, server activity and instrumentation equal. Compare the Roblox overlay's Sent/Recv KB/s **and** `GetBandwidthStats()`/`GetStats()` logical packet counts, messages, bytes, CPU, GC and application RTT percentiles. Record median and p95 over several trials, not just a screenshot. Note that the Roblox overlay includes engine replication and cannot prove all bytes were produced by NetStream. Critical traffic bypasses the Normal-priority batching window.


## v4.1.1 packet-size audit verification

Enable `PacketSizeAuditEnabled = true` before creating routes on the client. Run `tests/PacketSizeAuditRegression.server.lua` and `.client.lua` as a matched Studio Play session. The client checks the precise encoded BitFrame bytes for one U32 route 1001 (7 B), one U16 route 1002 (5 B), one U16 route 1 (4 B), and eight packed U16 route 1002 values (20 B). The last packet's metadata bit categories must sum to UsefulBits, with padding summing to PhysicalBits. The total is 36 encoded bytes across 11 logical messages; this is not an estimate of total Roblox network traffic. Report `NetStream.GetPacketSizeAudit().Totals`, `LastPacket`, `NetStream.GetStats()`, Packet Profiler buffer and remote-call totals, and RTT. Enable auditing only during diagnosis; repeat with instrumentation disabled to characterize application performance.

Read [Packet Size Audit](PACKET_SIZE_AUDIT.md) for derivations and measurement limitations.

## Related documentation

- [Architecture](ARCHITECTURE.md)
- [Packet-size audit](PACKET_SIZE_AUDIT.md)
- [Project overview](../README.md)
