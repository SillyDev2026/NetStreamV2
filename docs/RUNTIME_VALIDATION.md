# Executable runtime validation

Run `node scripts/source-audit.mjs`, then `LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs` from the repository. Node 22+ and the official Luau CLI are required. CI builds Luau revision `c87565b8b0db5d5d5bfd2b8b00ad6573e5d06d9f`, compiles the sources, and runs both gates.

The runner places the complete, unchanged Compression module and Netstream module body inside temporary Luau functions. It supplies minimal service/Random/task doubles and inserts private test access immediately before Netstream's final return. The published ModuleScript exposes no testing API. Temporary files are removed after execution. Unimplemented scheduler calls fail explicitly; deferred flush scheduling is suppressed. Tests do not start the remote transport.

| Suite | Executed behavior |
|---|---|
| Codec | 1,000 argument tuples including interior/trailing nils, false, buffers, nested tables and numeric values; every truncated prefix and a trailing byte of a representative native packet |
| Compression | 500 structural round-trips and checksum-corruption rejections using the bundled codec |
| Delta | 2,000 deterministic transitions over all 32 fields, nil removals, false values, high bit, replays, invalid masks, extra/sparse/keyed arrays and unchanged input on rejection |
| Replication | 13 scenarios: owner isolation, immutable state, command validation/replay/rates, yielding and erroneous reducers, missing ACKs, full resync, epochs, schema mismatch, lifecycle cleanup, 2,000 lossy updates and public API integration through real BitFrame encoding/decoding/dispatch |
| RPC | Actual admission/runner functions with coroutine suspension; global/per-player caps, accounting after errors, peak reset, disconnect/destroy while suspended, and suppression of late response queues |

## Reproduced defects

Against the v4.3.0 parent, the new tests accepted a `NilMask` of 2^32 and extra string/zero/sparse numeric keys in `Values`. Bitwise conversion truncated the oversized mask; Lua's length operator did not validate the entire table. v4.3.1 range-checks the nil mask and validates dense value keys/counts in bounded time before allocating the result state.

The old RPC completion path also queued a response for a departed player, recreating a bucket after cleanup. The same path could recreate queues after `Destroy()`. v4.3.1 checks lifecycle/recipient eligibility before acquiring response arguments. It does not cancel user callbacks, and their concurrency slots are released normally.

## Remaining gates

Standalone Luau tests are functional regression evidence, not Roblox benchmarks. The service doubles do not reproduce RemoteEvent serialization, packet delivery, Heartbeat/task scheduling, Instances, Vector/CFrame types, replication, or multiplayer behavior. Run the existing paired Studio regressions, including handshake recovery, atomic packets, RPC concurrency, memory retention and p95/p99 benchmarks, before production rollout.

Remaining major gaps include generated schema serializers, automatic spatial interest management, and controlled comparisons against other networking modules. CreateReplica now manages acknowledged baselines/resync for owner-only primitive state; the lower-level delta codec still leaves those responsibilities to its caller. No competitive speed ranking or percentage improvement is justified by these tests.

The replica suite additionally supplies deterministic clocks and in-memory event transport with production codec round-trips. Its public-factory integration uses two production NetStream instances and actual BitFrame encode/decode/dispatch, replacing only remotes/service startup. Handshake and bandwidth timing are disabled in that integration case; the tests do not establish behavior under the Roblox scheduler.
