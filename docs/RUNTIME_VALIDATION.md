# Executable Runtime Validation

> **Scope:** Standalone Luau correctness checks and deterministic service mocks. This is not a Roblox Studio multiplayer or network benchmark.

Run `node scripts/source-audit.mjs`, then `LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs` from the repository. Node 22+ and the official Luau CLI are required. CI builds Luau revision `c87565b8b0db5d5d5bfd2b8b00ad6573e5d06d9f`, compiles the sources, and runs both gates.

## Test commands

Run these from the repository root with Node.js and the official Luau CLI available:

```bash
node scripts/source-audit.mjs
node scripts/runtime-tests.mjs
node scripts/runtime-tests.mjs --stress-only
node scripts/runtime-tests.mjs --profile-only
node scripts/runtime-tests.mjs --compare-only
```

Set `LUAU_BIN` to the official Luau interpreter path when necessary. The `--profile-only` and `--compare-only` commands provide CPU microbenchmarks, **not** live Roblox RTT. GitHub Actions executes the source audit, runtime regressions, stress suite and packer tests.

## Harness design

The runner embeds the complete Compression module and Netstream and Netstream module bodies inside temporary Luau functions. It supplies minimal service/Random/task doubles and inserts private test access immediately before Netstream's final return. The published ModuleScript exposes no test hooks. Temporary files are removed after execution. Unimplemented scheduler calls fail explicitly; deferred flush scheduling is suppressed. Tests do not start the remote transport.

| Suite | Executed behavior |
|---|---|
| Codec | 1,000 argument tuples including interior/trailing nils, false, buffers, nested tables and numeric values; every truncated prefix and a trailing byte of a representative native packet |
| Compression | 500 structural round-trips and checksum-corruption rejections using the bundled codec |
| Delta | 2,000 deterministic transitions over all 32 fields, nil removals, false values, high bit, replays, invalid masks, extra/sparse/keyed arrays and unchanged input on rejection |
| RPC | Actual admission/runner functions with coroutine suspension; global/per-player caps, accounting after errors, peak reset, disconnect/destroy while suspended, and suppression of late response queues |

## Historical regression findings

Against the v4.3.0 parent, the new tests accepted a `NilMask` of 2^32 and extra string/zero/sparse numeric keys in `Values`. Bitwise conversion truncated the oversized mask; Lua's length operator did not validate the entire table. v4.3.1 range-checks the nil mask and validates dense value keys/counts in bounded time before allocating the result state.

The old RPC completion path also queued a response for a departed player, recreating a bucket after cleanup. The same path could recreate queues after `Destroy()`. v4.3.1 checks lifecycle/recipient eligibility before acquiring response arguments. It does not cancel user callbacks, and their concurrency slots are released normally.

## Additional regression coverage

The current suite also exercises server route authorization, one-time tickets, replay protection, peer State snapshots, Boolean `false` values, RPC error privacy, malformed BitFrame packets, and codec buffer-size limits. The stress suite uses 96 **simulated** peers, not 96 networked Roblox clients. For the load matrix, see [Server stress validation](SERVER_STRESS_VALIDATION.md).

## Remaining verification requirements

Standalone Luau tests are functional regression evidence, not Roblox benchmarks. The service doubles do not reproduce RemoteEvent serialization, packet delivery, Heartbeat/task scheduling, Instances, Vector/CFrame types, replication, or multiplayer behavior. Run the existing paired Studio regressions, including handshake recovery, atomic packets, RPC concurrency, memory retention and p95/p99 benchmarks, before production rollout.

Remaining major gaps include generated schema serializers, acknowledged per-peer delta baselines/resync, automatic spatial interest management, and controlled comparisons against other networking modules. Current delta helpers require the caller to manage baselines and resync. No competitive speed ranking or percentage improvement is justified by these tests.

## Related documentation

- [Benchmarking and Studio release checklist](BENCHMARKING.md)
- [Packer profiling](PACKER_MEMORY_OPTIMIZATION.md)
- [Project overview](../README.md)
