# Standalone Luau server stress and security regression harness

This harness runs production Netstream.lua and bundled Compression.lua in the pinned official Luau interpreter through GitHub Actions. Roblox services are replaced with minimal deterministic mocks; network packets do not leave this process.

## Run command

    node scripts/runtime-tests.mjs --stress-only

The standard runner without --stress-only still runs the existing codec, delta, RPC, security and ticket suites.

## Stress matrix

| Scenario | Workload | Invariants |
| --- | --- | --- |
| Command policies | 96 peers x 800 = 76,800 | Unauthorized scalar and tuple messages cannot reach gameplay |
| Default-deny | 96 x 40 = 3,840 | Unprotected event callbacks never execute |
| BitFrame receive | 96 x 24 = 2,304 packets | Real production encoded packets pass through decoder and callback queue; guarded actions only |
| Atomic packet rejection | Corrupted two-event packet | No decoded action is applied on bad trailing bytes |
| RPC admission | 512 simultaneously yielded callbacks | Concurrency limit holds; all in-flight capacity reclaimed |
| Server-issued tickets | 96 x 240 = 23,040 issues | Player binding, single execution, 23,040 replay attempts rejected |
| Idempotency | 96 x 120 = 11,520 transactions | Duplicate request IDs cannot execute twice |
| Delta replication | 96 x 180 = 17,280 transitions | Revisions increase and stale frames are rejected |
| Codec round trips | 3,000 structured payloads | False, interior nil, buffers, tables round-trip |
| Malformed fuzz | 3,000 deterministic raw buffers | TryDecode cannot throw to callers; invalid input generally rejected |
| Inbound BitFrame fuzz | 2,400 random raw wire buffers | Decoder rejects malformed payloads and never dispatches gameplay |
| Legacy fallback | 64 peers x 24 = 1,536 legacy packets | Actual fallback encoder/decoder respects authorization policy |

These are simulated Luau server operations, **not 96 real Roblox clients**. Reported durations are Luau interpreter CPU timings on CI hardware, not ping, network throughput or engine frame times. There are no arbitrary latency assertions.

The test uses production BitFrame encode/receive/dispatch and server security logic. It does **not** simulate full Roblox networking, reliable/unreliable RemoteEvents, heartbeat scheduling, network congestion, live packet loss, physics, server restart recovery, DataStore persistence, or cross-server transactions.

Live Roblox Studio multiplayer stress and adversarial network testing are still required. Neither a ticket nor any client handshake can make a compromised client trustworthy.