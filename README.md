# NetStreamV2

**A binary networking framework for Roblox Luau.** NetStreamV2 provides typed routes, reliable and unreliable delivery, batching, request/response calls, state updates, traffic limits, and server-side security controls.

![Roblox](https://img.shields.io/badge/platform-Roblox-00a2ff) ![Luau](https://img.shields.io/badge/language-Luau-6366f1) ![Version](https://img.shields.io/badge/version-v4.3.1-2563eb) ![Wire](https://img.shields.io/badge/wire-BitFrame%20v1-475569)

**Current source line:** NetStream **v4.3.1**, bundled Compression **v2.4.2**, codec **230**, with **BitFrame v1** as the default wire format. The latest `main` branch includes compatible fixes and optimizations beyond the initial v4.3.1 tag; these do not constitute a new numbered release.

> **Validation status:** Source audits, executable standalone Luau regressions, and simulated-server stress tests run in GitHub Actions. Authored Roblox Studio test scripts are available, but live multiplayer behavior, true server heap usage, network latency, and comparative throughput have **not** been independently established by those CI tests.

## Contents

- [Capabilities](#capabilities)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Routes and schemas](#routes-and-schemas)
- [Server-side security](#server-side-security)
- [Transport and packet format](#transport-and-packet-format)
- [Performance and memory](#performance-and-memory)
- [Testing and verification](#testing-and-verification)
- [Documentation](#documentation)
- [Scope and limitations](#scope-and-limitations)

## Capabilities

| Area | Included |
| --- | --- |
| Messaging | Reliable `RemoteEvent` transport and disposable `UnreliableRemoteEvent` traffic |
| Serialization | BitFrame v1, typed schemas, dynamic values, small-tuple packing, bundled compression |
| Scheduling | Batching, coalescing, priorities, outbound rate and bandwidth budgets |
| API | Events, unreliable events, RPC functions, and state routes |
| Replication | Optional revisioned field-delta codec and server-managed interest groups |
| Server protection | Request validation and authorization policies, bounded RPC concurrency, rate limits, single-use action tickets and in-memory idempotency |
| Observability | Packet-size audits, pool statistics, queue and RPC diagnostics, optional p50/p95/p99 samples |
| Validation | Source audits, official Luau CLI regressions, deterministic simulated-peer stress and paired Studio scripts |

NetStream handles message delivery and encoding; **your server gameplay code remains responsible for authoritative purchases, permissions, inventory, damage, persistent transactions, and data ownership**.

## Installation

Copy the two source files into Roblox Studio as ModuleScripts:

```text
ReplicatedStorage
└── Netstream                    ModuleScript: Netstream.lua
    └── Compression              ModuleScript: Compression.lua

ServerScriptService
└── NetworkServer                Script

StarterPlayer
└── StarterPlayerScripts
    └── NetworkClient            LocalScript
```

1. Place `Netstream.lua` inside `ReplicatedStorage` as `Netstream`.
2. Place `Compression.lua` as its child named `Compression`.
3. Declare matching route names, numeric IDs, and schemas on the server and client.
4. Run the [paired Studio regressions](docs/BENCHMARKING.md) in isolated Play sessions before using the framework in a live experience.

The default runtime namespace creates `ReplicatedStorage.__NetStream_NetStream` with reliable (`R`), unreliable (`U`), and control (`H`) remotes.

## Quick start

This example sends a typed request from a client and returns a server-owned response. It is **not** a complete commerce implementation.

**Server — `ServerScriptService/NetworkServer`**

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

local BuyUpgrade = NetStream.Event("BuyUpgrade", {
    Id = 1001,
    Schema = {T.U16},
    Compression = false,
    MaxPerSecond = 10,
    Burst = 5,
})
local PurchaseResult = NetStream.Event("PurchaseResult", {
    Id = 1002,
    Schema = {T.Bool},
    Compression = false,
})

NetStream.SetServerPolicy(BuyUpgrade, {
    Validate = function(player, upgradeId)
        return upgradeId >= 1 and upgradeId <= 100
    end,
    Authorize = function(player)
        return player.Parent ~= nil
    end,
})

BuyUpgrade:Connect(function(player, upgradeId)
    -- Replace this illustrative check with a server-owned, atomic purchase.
    local approved = upgradeId == 7
    PurchaseResult:FireClient(player, approved)
end)
```

**Client — `StarterPlayerScripts/NetworkClient`**

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

local BuyUpgrade = NetStream.Event("BuyUpgrade", {
    Id = 1001,
    Schema = {T.U16},
    Compression = false,
})
local PurchaseResult = NetStream.Event("PurchaseResult", {
    Id = 1002,
    Schema = {T.Bool},
    Compression = false,
})

PurchaseResult:Connect(function(approved)
    print("Server approved:", approved)
end)

BuyUpgrade:FireServer(7)
```

**Important:** A successfully transmitted message is not an approved action. Never accept client-reported balances, prices, permissions, damage, or rewards. Use authoritative server state and validate immediately before committing a gameplay change.

## Routes and schemas

| API | Purpose |
| --- | --- |
| `NetStream.Event(name, options)` | Reliable one-way event |
| `NetStream.Unreliable(name, options)` | Disposable update where loss or reordering is acceptable |
| `NetStream.Function(name, options)` | Request/response RPC with timeout and concurrency controls |
| `NetStream.State(name, options)` | Latest-value state delivery and coalescing |

Typed schemas describe field order and representation:

```luau
local T = NetStream.Types
local Snapshot = NetStream.Event("PlayerSnapshot", {
    Id = 2001,
    Schema = {T.U16, T.U8, T.Bool},
    Compression = false,
})
```

In BitFrame payloads, `U16` uses 16 bits, `U8` uses eight, and `Bool` uses one, before per-message framing and byte padding. Client and server must use matching schemas and IDs. Numeric route IDs are preferable when you need explicit, stable identifiers.

For RPC callbacks, use `NetStream.Function(...):SetCallback(...)` on the server and `InvokeServer(...)` on the client. For stateful applications, use the revisioned delta helpers with **application-managed baselines and resynchronization**. Coalescing is not automatic authoritative state replication.

## Server-side security

The security APIs are present on `main` and are **opt-in**:

- `NetStream.SetServerPolicy(route, {Validate = ..., Authorize = ...})` gates incoming server Event/Function callbacks.
- `NetStream.RequireServerPolicies(true)` denies incoming Event/Function callbacks without a policy; enable it only after protecting every applicable route.
- `NetStream.RejectClientStateRoutes(true)` separately rejects client-origin State messages before server peer-state mutation.
- `NetStream.CreateActionGate({...})` issues bounded, expiring, one-use, player-bound action tickets.
- `NetStream.CreateIdempotencyGuard({...})` suppresses duplicate request IDs **within a single server session**.

Policies must return exactly `true`, be non-yielding, and recheck mutable gameplay conditions inside the authoritative handler. Tickets are **not client secrets** and do not establish client integrity. In-memory deduplication cannot ensure cross-server or restart-safe, exactly-once transactions.

Read [server policy guidance](docs/SECURITY.md) and the [action-ticket walkthrough](docs/ACTION_GATE_SECURITY.md) before enabling strict mode.

## Transport and packet format

NetStream batches logical routes over Roblox remotes. BitFrame v1 uses a one-bit message-presence marker, a two-bit message kind, adaptive route/request identifiers where needed, and typed or dynamic payloads, ending with a zero marker and up to seven padding bits.

The bundled compressor is selected only when eligible and byte-efficient. Small native values and typed packets generally avoid compression. The current source includes direct small-tuple encoding, bounded writer/reader/argument pools, and exact varint-length reservations; these changes preserve the wire format.

The HELLO/WELCOME/CONFIRM/READY control handshake checks session/protocol metadata. **It does not authenticate an untrusted Roblox client, encrypt traffic, or prevent cheating.**

See [architecture and packet flows](docs/ARCHITECTURE.md) and [packet-size accounting](docs/PACKET_SIZE_AUDIT.md).

## Performance and memory

| Topic | What is supported | Important qualification |
| --- | --- | --- |
| Tiny native codec tuples | Direct encoding/decoding of up to four small primitive arguments | Only eligible payloads take this path |
| Complex codec values | Reusable bounded writers, readers, and temporary argument tables | May trade some CPU time for less allocation churn |
| Writer memory | Capped idle pools, dictionary trimming, and `TrimPools()` | Broad Luau heap measurements include unrelated game allocations |
| Throughput | Reliable/unreliable queues, budgets, and optional batching | Does not reduce geographic ping |
| Telemetry | Optional timing samples, queue counters, and packet-size audits | Sampling can add overhead; RTT needs an application ping/pong |

A matched in-process Luau CLI benchmark observed **40.9% faster tiny encoding** and **42.3% faster tiny decoding** for a specific workload. Structured payloads in that same sample were approximately **5.5% slower to encode** and **2.7% slower to decode**. These are *not* Studio multiplayer benchmarks or general performance guarantees.

For methodology and sample results, see [packer memory optimization](docs/PACKER_MEMORY_OPTIMIZATION.md), [memory diagnostics](docs/MEMORY_EFFICIENCY.md), and [benchmark procedures](docs/BENCHMARKING.md).

## Testing and verification

The repository ships automated source checks and executable Luau test suites:

```sh
node scripts/source-audit.mjs
LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs
LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs --stress-only
LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs --profile-only
LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs --compare-only
```

The runtime harness executes the production Luau module bodies with minimal Roblox service doubles. The stress profile includes **96 simulated peers**, BitFrame and legacy decode paths, 512 in-flight RPC callbacks, tickets, deltas, and malformed-packet fuzzing.

These results **do not** prove capacity for 96 real players, Studio transport behavior, packet loss resilience, persistent transaction correctness, or comparative performance against competing libraries. Run the paired `tests/*.server.lua` and `tests/*.client.lua` files in dedicated Roblox Studio sessions.

Details: [runtime validation](docs/RUNTIME_VALIDATION.md) · [simulated stress matrix](docs/SERVER_STRESS_VALIDATION.md) · [benchmark checklist](docs/BENCHMARKING.md).

## Documentation

| Guide | Subject |
| --- | --- |
| [Documentation index](docs/README.md) | Start here for the complete guide catalog |
| [Architecture](docs/ARCHITECTURE.md) | Subsystems, message lifecycle, and packet format |
| [Security policies](docs/SECURITY.md) | Trust boundaries, authorization, and in-memory deduplication |
| [Action gates](docs/ACTION_GATE_SECURITY.md) | Single-use tickets and server-authoritative request flow |
| [Benchmarking](docs/BENCHMARKING.md) | Repeatable Studio procedures and measurement caveats |
| [RPC concurrency](docs/RPC_CONCURRENCY.md) | In-flight limits, overload behavior, and diagnostics |
| [Memory efficiency](docs/MEMORY_EFFICIENCY.md) | Pool retention and heap measurement |
| [Packer optimization](docs/PACKER_MEMORY_OPTIMIZATION.md) | Codec changes and measured trade-offs |
| [Server stress validation](docs/SERVER_STRESS_VALIDATION.md) | Simulated stress workloads and limitations |
| [Changelog](docs/CHANGELOG.md) | Current source maintenance and version history |
| [Upgrade roadmap](docs/NEXT_OPTIONS.md) | Prioritized remaining work |
| [Historical v2.3.22 README](docs/README_LEGACY_v2.3.22.md) | Archived behavior; **not** current setup instructions |

## Scope and limitations

NetStream is application-level networking built on Roblox remotes. It is **not** a DataStore, a cryptographic transport, a replacement for Roblox's networking infrastructure, or a guarantee that every hostile client will be detected. Security relies on server-owned state and sound game-specific validation.

This repository provides source, tests, and benchmark tooling. A production release should pass isolated Studio multiplayer tests, real-server heap and CPU profiling, reconnect and packet-loss scenarios, and persistence-integrity checks appropriate to the game.

---

**Documentation convention:** `v4.3.1` identifies the current source version; changes merged afterward are described as *post-v4.3.1 maintenance* until a new release is formally numbered. Historical version guides are retained for reference only.
