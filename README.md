# NetStreamV2

**Typed binary networking, reliable and unreliable events, RPC, state updates, and traffic controls for Roblox Luau.**

![Version](https://img.shields.io/badge/version-v4.3.1-2563eb)
![Platform](https://img.shields.io/badge/platform-Roblox-00a2ff)
![Language](https://img.shields.io/badge/language-Luau-64748b)
![Wire](https://img.shields.io/badge/wire-BitFrame_v1-475569)
![Codec](https://img.shields.io/badge/compression-v2.4.2-0f766e)

NetStreamV2 provides an application-layer networking API built on Roblox's `RemoteEvent` and `UnreliableRemoteEvent` transports. It combines typed and dynamic serializers with message batching, bounded queues, server-side route policies, diagnostic counters, and optional performance telemetry.

> **Status:** The `main` branch identifies as **NetStream v4.3.1**, with **BitFrame v1** and bundled **Compression v2.4.2 (codec 230)**. The branch includes additional compatible maintenance patches that have not been assigned a new release number. GitHub Actions runs source checks, executable Luau regressions, and a deterministic simulated-server stress suite. **Real Roblox Studio multiplayer performance and heap usage are not yet independently verified.**

## Contents

- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [API overview](#api-overview)
- [Security and trust boundaries](#security-and-trust-boundaries)
- [Encoding and performance](#encoding-and-performance)
- [Testing and verification](#testing-and-verification)
- [Documentation](#documentation)
- [Compatibility and limitations](#compatibility-and-limitations)

## Features

| Area | Capability |
| --- | --- |
| **Transport** | Reliable and unreliable message routes over Roblox remotes |
| **Serialization** | Compact typed schemas, dynamic values, BitFrame v1, optional bundled compression |
| **Requests** | Function-style RPC with concurrency limits and lifecycle cleanup |
| **State** | Latest-value updates, change suppression, manual revisioned delta codec |
| **Queues** | Priority hints, batching, coalescing, bounded dispatch, per-player controls |
| **Security** | Server route policies, optional fail-closed mode, single-use action tickets, in-memory idempotency |
| **Diagnostics** | Packet, queue, RPC, security, compression, and memory/pool counters |
| **Tests** | Official Luau runtime regressions, fuzz inputs, simulated-server stress, and Studio test scripts |

**Important:** NetStreamV2 is a networking library, not a DataStore, game-specific anti-cheat, automatic entity-replication engine, or substitute for server-authoritative gameplay rules.

## Installation

Create the following hierarchy in Roblox Studio:

```text
ReplicatedStorage
└── Netstream                   ModuleScript: contents of Netstream.lua
    └── Compression             Child ModuleScript: contents of Compression.lua

ServerScriptService
└── NetworkServer               Script

StarterPlayer
└── StarterPlayerScripts
    └── NetworkClient           LocalScript
```

The `Compression` ModuleScript must be a child of `Netstream`. Server and client scripts must declare matching route IDs and schemas. Keep privileged validation, economy data, and persistence logic **server-side**.

## Quick start

### Server: define a protected command

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

local Request = NetStream.Event("RequestUpgrade", {
    Id = 1001,
    Schema = {T.U16},
    Compression = false,
    MaxPerSecond = 5,
    Burst = 2,
})
local Result = NetStream.Event("UpgradeResult", {
    Id = 1002,
    Schema = {T.Bool},
    Compression = false,
})

NetStream.SetServerPolicy(Request, {
    Validate = function(player, upgradeId)
        return upgradeId == 7
    end,
    Authorize = function(player)
        -- Replace with a check against server-owned player profiles.
        return player.Parent == game:GetService("Players")
    end,
})

Request:Connect(function(player, upgradeId)
    -- An actual purchase must recheck currency, ownership, and cooldown
    -- and perform the state change atomically using server-owned data.
    local approved = false
    Result:FireClient(player, approved)
end)

-- Optional migration mode: install policies on ALL incoming Event/Function
-- routes before enabling this default-deny switch.
-- NetStream.RequireServerPolicies(true)
```

This example deliberately declines purchases. It demonstrates the route, policy, and reply shape **without suggesting the sample implements a real economy transaction**.

### Client: send a request

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

local Request = NetStream.Event("RequestUpgrade", {Id = 1001, Schema = {T.U16}, Compression = false})
local Result = NetStream.Event("UpgradeResult", {Id = 1002, Schema = {T.Bool}, Compression = false})

Result:Connect(function(approved)
    print("Server approved:", approved)
end)

Request:FireServer(7)
```

`FireServer` queues a client request; it does **not** confirm delivery or authorize the action. Use an explicit reply, state revision, or RPC for application-level acknowledgement.

## API overview

### Routes and data

| API | Purpose |
| --- | --- |
| `NetStream.Event(name, options)` | Reliable one-way gameplay messages |
| `NetStream.Unreliable(name, options)` | Disposable updates that may be lost or reordered |
| `NetStream.Function(name, options)` | Request/response calls with timeouts and admission controls |
| `NetStream.State(name, options)` | Send state values or coalesce replaceable updates |
| `NetStream.Types` | Field descriptors such as `U8`, `U16`, `U32`, and `Bool` |
| `NetStream.Codec` | Standalone value encoding, decoding, and inspection |
| `NetStream.CreateDeltaCodec(fieldNames)` | Caller-managed revisioned field snapshots and deltas |
| `NetStream.CreateInterestGroup()` | Server-managed recipient groups; membership is application-defined |

Typed payload example:

```luau
local T = NetStream.Types
local Update = NetStream.Event("PlayerSnapshot", {
    Id = 2001,
    Schema = {T.U16, T.U8, T.Bool},
    Compression = false,
})
```

Both peers must agree on the route ID, field ordering, and schema. `U16`, `U8`, and `Bool` occupy 16, 8, and 1 payload bit respectively in the BitFrame typed path, excluding framing and padding.

### Operational controls

| API | Use |
| --- | --- |
| `NetStream.Configure(options)` | Change limits and transport/telemetry settings |
| `NetStream.GetStats()` | Inspect counters and packet processing |
| `NetStream.GetRPCStats(player?)` | Monitor concurrent server callbacks |
| `NetStream.GetMemoryDiagnostics()` | Inspect pool and queue retention |
| `NetStream.TrimPools()` | Release idle pooled objects after a burst |
| `NetStream.GetLatencyStats()` | Inspect opt-in timing samples; RPC RTT requires explicit recording |

Do not call `TrimPools()` every frame. Pool rebuilds can increase allocation pressure.

## Security and trust boundaries

**Clients are untrusted.** They can modify scripts, forge requests, reuse observed values, and submit arbitrary packet data. The server must determine whether every sensitive action is valid using server-owned state.

NetStreamV2 supports several complementary controls:

1. `NetStream.SetServerPolicy(route, {Validate = ..., Authorize = ...})` applies admission checks to inbound event and function routes.
2. `NetStream.RequireServerPolicies(true)` optionally rejects unprotected inbound event/function callbacks. Enable it only after auditing existing routes.
3. `NetStream.RejectClientStateRoutes(true)` optionally rejects client-origin State updates before they enter the server peer-state cache.
4. `NetStream.CreateActionGate(options)` issues short-lived, player-bound, one-use **server-recorded** action tickets.
5. `NetStream.CreateIdempotencyGuard(options)` rejects duplicate request keys within one server session, **not across server restarts**.

Policies are not a replacement for transaction-level validation. Tickets are identifiers, **not secrets**. A server handshake does not make the client trusted, encrypted, or tamper-proof.

See [security policies](docs/SECURITY.md) and [action tickets](docs/ACTION_GATE_SECURITY.md) for supported semantics and implementation examples.

## Encoding and performance

The default wire format is **BitFrame v1**. Its compact framing combines route/request metadata with typed or dynamic values and optional compression when beneficial.

The current `main` branch includes a **byte-compatible tiny Codec fast path** for up to four primitive values, bounded writer/reader/argument pools for larger payloads, and fixes for packet limits. A same-process Luau CPU microbenchmark measured approximately **41% faster tiny encoding and 42% faster tiny decoding** on one sample. More complex Codec payloads were modestly slower with pooling in that sample. No universal throughput, bandwidth, or Roblox memory percentage is claimed.

NetStreamV2 cannot reduce geographic network latency. It may affect **application-side** serialization time, allocation pressure, batching delay, and outgoing byte size, depending on the workload.

Reproduce the packer microbenchmarks and read their limitations in [Packer memory optimization](docs/PACKER_MEMORY_OPTIMIZATION.md). Use [Benchmarks](docs/BENCHMARKING.md) to plan controlled Roblox Studio comparisons.

## Testing and verification

Node.js and the official Luau command-line interpreter are required for standalone runtime tests. Run these commands from the repository root:

```bash
node scripts/source-audit.mjs
node scripts/docs-audit.mjs
node scripts/runtime-tests.mjs
node scripts/runtime-tests.mjs --stress-only
node scripts/runtime-tests.mjs --profile-only
node scripts/runtime-tests.mjs --compare-only
```

Set `LUAU_BIN` to your interpreter path if `luau` is not available on `PATH`. GitHub Actions builds a pinned Luau revision and runs these checks.

The stress suite uses **96 simulated peers**, packet fuzzing, 512 concurrent yielding RPC callbacks, replay attempts, and state-delta transitions. These execute production Luau code with minimal Roblox service mocks; **they are not equivalent to real connected Roblox players**.

For actual engine behavior, run the paired scripts in `tests/` under Roblox Studio: place `*.server.lua` in `ServerScriptService` and matching `*.client.lua` in `StarterPlayerScripts`, one pair per Play session. Real packet loss, frame-time impact, heap/GC behavior, cross-server persistence, and high-player-count performance remain separate validation requirements.

See [Runtime validation](docs/RUNTIME_VALIDATION.md) and [Server stress validation](docs/SERVER_STRESS_VALIDATION.md).

## Documentation

| Guide | Contents |
| --- | --- |
| [Architecture](docs/ARCHITECTURE.md) | Remote hierarchy, packet framing, queues, and message lifecycle |
| [Security policies](docs/SECURITY.md) | Validation, authorization, threat model, and idempotency |
| [Action-ticket security](docs/ACTION_GATE_SECURITY.md) | One-time server-issued tickets and strict route mode |
| [RPC concurrency](docs/RPC_CONCURRENCY.md) | Concurrent callback admission and cleanup |
| [Memory efficiency](docs/MEMORY_EFFICIENCY.md) | Retention controls and diagnostics |
| [Packer optimization](docs/PACKER_MEMORY_OPTIMIZATION.md) | Tiny packet fast path and reproducible CPU comparisons |
| [Packet-size audit](docs/PACKET_SIZE_AUDIT.md) | Encoded BitFrame overhead and measurement |
| [Benchmarking](docs/BENCHMARKING.md) | Studio performance methodology and release checks |
| [Runtime validation](docs/RUNTIME_VALIDATION.md) | Standalone Luau tests and remaining coverage |
| [Server stress validation](docs/SERVER_STRESS_VALIDATION.md) | Simulated load matrix and limitations |
| [Message processing review](docs/MESSAGE_PROCESSING_REVIEW.md) | Design decisions and comparison notes |
| [Upgrade roadmap](docs/NEXT_OPTIONS.md) | Historical iterations and future candidates |
| [Changelog](docs/CHANGELOG.md) | Versioned and compatible-branch changes |
| [Archived v2.3.22 manual](docs/README_LEGACY_v2.3.22.md) | Historical documentation; not current setup instructions |

## Compatibility and limitations

- **Wire compatibility:** Recent `main` maintenance patches preserve BitFrame v1 and codec 230 for valid encoded messages. Keep matching definitions and supported transport settings at both endpoints.
- **Roblox ownership:** Roblox controls RemoteEvent delivery and network replication. Unreliable traffic is not guaranteed to arrive.
- **Security:** Critical gameplay changes must be validated and committed by trusted server code. Neither a client-side secret nor a handshake is sufficient.
- **Persistence:** In-memory ticket and idempotency records are not durable cross-server transaction mechanisms.
- **Performance:** Published Luau CLI timings are reproducible microbenchmark evidence, not independently measured Studio RTT or heap savings.

For migration or regressions, review the [changelog](docs/CHANGELOG.md), run the relevant suites, and benchmark your actual experience before deploying.
