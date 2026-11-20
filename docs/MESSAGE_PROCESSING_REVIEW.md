# Message Processing: Design Review

> **Historical scope:** v4.3.0 message-processing decisions. This document records design references and engineering rationale; it is **not** an independently verified ranking of networking libraries or an assertion that all competing implementations behave identically today.

The current branch also contains v4.3.1-compatible security and packer improvements. See the [changelog](CHANGELOG.md) for subsequent changes.

[← Documentation index](README.md) · [Current architecture](ARCHITECTURE.md) · [Upgrade roadmap](NEXT_OPTIONS.md)

## Decision status

This is a historical decision record, **not the authoritative list of current missing features**. Some recommendations from the original review have since been implemented, including server-side policy controls, codec memory pooling and experimental owner-only revision ACK/resync through `CreateReplica`. The remaining comparison ideas require independently repeatable Roblox Studio benchmarks.

| Workstream | Current status |
| --- | --- |
| Server command policy and admission checks | Implemented on `main` |
| Compact native codec tuples and pooled serializers | Implemented; measure real game workloads before ranking |
| Owner-only revision ACK and resync | Experimental implementation; Studio validation pending |
| Automatic spatial observers and arbitrary shared-entity replication | Not part of the owner-only replica preview |
| Matched third-party benchmark results | Not established in this document |

## Other Roblox networking projects reviewed

The following are **publicly documented design references**, not code copied into NetStreamV2. Verify current upstream behavior before relying on comparative claims:

| Library | Useful published design | NetStream existing implementation | v4.3.0 decision |
|---|---|---|---|
| [BlinkBlox](https://github.com/XopoIII/BlinkBlox) | Per-player and per-event budgets, packet/message caps, prioritized outbound work | Per-player/route inbound rate limits and global bounded callback queue | Add a **per-player callback backlog quota**, separate from packet size/rate limits |
| [Zap](https://github.com/red-blox/zap) | Schema-generated compact serialization and batch-oriented buffers | Runtime typed schemas, BitFrame v1 and batching | No copy of generated code; keep wire compatible. Generated code is a future, separately versioned project |
| [Satset](https://github.com/bookek/satset) | Buffer-backed batching, grouped reliable messages, rate limiting, state sync | Packed schema runs, two outbound reliability lanes and manual revisioned delta codec | Preserve batching; add fair scheduling when broadcast and individual traffic compete |
| [ByteNet](https://github.com/ffrostfall/ByteNet) | Typed buffer serialization, processing/queue refinements | Fixed schemas and existing pooled tables | Keep stable encoding; reduce callback starvation with smaller configurable dispatch time-check intervals |

## New v4.3.0 serializer specialization

BlinkBlox and Zap illustrate what a generated schema-specific encoder can achieve, but NetStream does not yet have a full code generator. This patch instead selects homogeneous U16/U32 encoding/decoding fast paths at schema registration, including entire packed runs. `TypedTupleFastPathEnabled=false` provides a packet-identical generic fallback for reliable performance A/B comparisons. There is no copying of competitor code and no measured speed ranking. See [the benchmark protocol](BENCHMARKING.md).

## Concrete v4.2.3 findings

1. **Global dispatch slot monopoly.** `enqueueDispatch` and `enqueueDispatchScalar` checked only `MaxDispatchBacklog`. A client allowed by upstream packet/rate controls could fill most queued callback slots. Other clients could then be rejected without their own queue sharing. The v4.3.0 fix adds `DispatchPerPlayerBacklogLimit`, pending counters and drop diagnostics. It does not reorder callbacks and it is not a substitute for validating game actions.
2. **Callbacks after disconnect.** `runDispatch` previously processed queued callbacks without rechecking membership in `Players`. v4.3.0 discards callbacks from departed players and releases argument arrays.
3. **Broadcast scheduling monopoly.** `flushAll` processed the broadcast bucket first using the full `FlushBudgetSeconds` deadline, potentially leaving no time for queued individual recipients. v4.3.0 reserves a fraction for individual recipients when both queues exist, without creating a new packet wire format.
4. **Coarse CPU budget checks.** `runDispatch` measured the time budget only once every 32 callbacks. v4.3.0 checks every 8 by default, with configuration for profiling trade-offs.

## Safety and compatibility

- Keep BitFrame v1 and Compression codec 230 intact. No generated serializer or unacknowledged delta semantics are silently introduced.
- Per-player dispatch caps **discard queued event callbacks under pressure**. Use application-level acknowledgments/retries or domain-specific queue reservations for critical gameplay commands.
- `DispatchPerPlayerBacklogLimit=0` disables the new per-player cap, and `BroadcastFlushBudgetFraction=1` restores prior broadcast scheduling. Defaults target safer busy-server behavior and must be load-tested for each experience.
- Timing checks cannot interrupt a yielding or expensive callback. Do not equate less queue unfairness with reduced Internet RTT.
- Test `DispatchFairnessRegression` and `BroadcastBudgetRegression` in separate paired Roblox Studio sessions, plus the existing 82 test scripts. Run equal-workload CPU, heap, queue-latency and actual network bytes benchmarks before claims against competitor libraries.

## Still worthwhile, not implemented here

- Code-generated static serializers and route manifests (build tooling, compatibility/ID allocation)
- Per-route callback fairness and prioritized processing with reliable gameplay guarantees
- Multi-client automated Roblox Studio integration harness
- Production-verified acknowledged replication for live Roblox Studio clients (the owner-only preview is implemented, but its Studio release gate remains open)

This is a targeted performance/safety patch rather than a rewrite or a claim of world-leading speed.

## Related documentation

- [Architecture](ARCHITECTURE.md)
- [Roadmap](NEXT_OPTIONS.md)
- [Benchmark methodology](BENCHMARKING.md)
