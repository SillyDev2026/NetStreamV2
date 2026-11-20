# Standalone Luau Server Stress and Security Validation

> **Scope:** Deterministic execution of the production Luau networking code with mock Roblox services. These are correctness and regression tests, **not** live-server load measurements.

The harness runs `Netstream.lua` and bundled `Compression.lua` in the pinned official Luau interpreter through GitHub Actions. Minimal service doubles replace Roblox service objects; packets never leave the Luau process.

[← Documentation index](README.md) · [Runtime suites](RUNTIME_VALIDATION.md) · [Studio methodology](BENCHMARKING.md)

## Test interpretation

The simulated load intentionally exercises code-path correctness, resource bounds, and rejection behavior. It is **not** a throughput contract or a certified Roblox player capacity. The benchmark does not include real engine remotes, replication scheduling, network transit, physical devices or real DataStore operations.

| Observation | Interpretation |
| --- | --- |
| All simulated messages processed without assertion failure | Those exact invariants held in the test harness |
| A rate-limited message did not reach gameplay | The exercised admission path rejected it |
| An ACK/resync simulation converged | The tested deterministic loss sequence recovered |
| A run completed quickly | The local Luau workload was fast on that runner, not necessarily in Studio |
| A simulated player has a mock `Player` object | It is not a real connected Roblox player |

## Run the suite

```bash
node scripts/runtime-tests.mjs --stress-only
```

The standard runner without `--stress-only` runs codec, delta, RPC, policy, ticket, and packer regressions. Set `LUAU_BIN` to the official Luau interpreter if it is not on your `PATH`.

## Stress matrix

| Scenario | Workload | Invariants |
| --- | --- | --- |
| Command policies | 96 peers x 800 = 76,800 | Unauthorized scalar and tuple messages cannot reach gameplay |
| Default-deny | 96 x 40 = 3,840 | Unprotected event callbacks never execute |
| BitFrame receive | 96 x 24 = 2,304 packets | Real production encoded packets pass through decoder and callback queue; guarded actions only |
| Atomic packet rejection | Corrupted two-event packet | No decoded action is applied on bad trailing bytes |
| RPC admission | 512 simultaneously yielded callbacks | Concurrency limit holds; all in-flight capacity reclaimed |
| RPC error privacy | Deliberately thrown server error and invalid result | Error details and server stack traces must not reach the client; counters increment |
| Server-issued tickets | 96 x 240 = 23,040 issues | Player binding, single execution, 23,040 replay attempts rejected |
| Idempotency | 96 x 120 = 11,520 transactions | Duplicate request IDs cannot execute twice |
| Delta replication | 96 x 180 = 17,280 transitions | Revisions increase and stale frames are rejected |
| Codec round trips | 3,000 structured payloads | False, interior nil, buffers, tables round-trip |
| Malformed fuzz | 3,000 deterministic raw buffers | TryDecode cannot throw to callers; invalid input generally rejected |
| Inbound BitFrame fuzz | 2,400 random raw wire buffers | Decoder rejects malformed payloads and never dispatches gameplay |
| Legacy fallback | 64 peers x 24 = 1,536 legacy packets | Actual fallback encoder/decoder respects authorization policy |

These are simulated Luau server operations, **not 96 real Roblox clients**. Reported durations are Luau interpreter CPU timings on CI hardware, not ping, network throughput or engine frame times. There are no arbitrary latency assertions.

The test uses production BitFrame encode/receive/dispatch and server security logic. It does **not** simulate full Roblox networking, reliable/unreliable RemoteEvents, heartbeat scheduling, network congestion, live packet loss, physics, server restart recovery, DataStore persistence, or cross-server transactions.

## Live Roblox Studio handoff

Before describing production performance, run paired server/client regression scripts on the target Roblox Studio version. Record connected player count, run duration, p50/p95/p99, heap after GC, packet volumes, disconnect/rejoin recovery, strict policy rejection and any packet-loss simulation assumptions. Test the experimental replica controller separately with owner isolation and malformed command attempts.

## Limitations and next validation

Live Roblox Studio multiplayer stress, network loss/reordering, and adversarial traffic must still be tested. Neither a ticket nor any client handshake can make a compromised client trustworthy.

See [Runtime validation](RUNTIME_VALIDATION.md), [Benchmarking](BENCHMARKING.md), and the [project overview](../README.md).