# NetStream

![Version](https://img.shields.io/badge/version-v1.3.0-4c8bf5)
![Language](https://img.shields.io/badge/language-Luau-00A2FF)
![Platform](https://img.shields.io/badge/platform-Roblox-111111)
![Compression](https://img.shields.io/badge/Compression-v2.3.2-2ea44f)
![Protocol](https://img.shields.io/badge/protocol-0x18%20%7C%200x19%20%7C%200x1A-6f42c1)

**NetStream** is a compact, production-oriented networking layer for Roblox that sits on top of `RemoteEvent` and `UnreliableRemoteEvent`.

It provides typed routes, schema encoding, dynamic binary encoding, Compression v2.3.2 integration, adaptive batching, coalescing, RPC, replicated state, queue protection, inbound rate limiting, an outbound bandwidth governor, pooled encoders/decoders, and detailed transport/compression diagnostics through one API.

> **Current release:** `v1.3.0`
>
> **Required dependency:** `Compression v2.3.2`
>
> NetStream v1.3.0 requires a child ModuleScript named `Compression` under the NetStream ModuleScript.

---

## Table of Contents

- [What NetStream Does](#what-netstream-does)
- [v1.3.0 Highlights](#v130-highlights)
- [How the Pipeline Works](#how-the-pipeline-works)
- [Installation](#installation)
- [Recommended Project Structure](#recommended-project-structure)
- [Quick Start](#quick-start)
- [Routes](#routes)
- [DefineCompact](#definecompact)
- [Events](#events)
- [Unreliable Events](#unreliable-events)
- [States](#states)
- [Functions / RPC](#functions--rpc)
- [Schemas](#schemas)
- [Dynamic Encoding](#dynamic-encoding)
- [Compression v2.3.2 Integration](#compression-v232-integration)
- [Compact Single-Table Packets](#compact-single-table-packets)
- [Schema String and Buffer Compression](#schema-string-and-buffer-compression)
- [Batching and Transport Windows](#batching-and-transport-windows)
- [Schema Event Runs](#schema-event-runs)
- [Coalescing and Latest](#coalescing-and-latest)
- [Priorities](#priorities)
- [Bandwidth Governor](#bandwidth-governor)
- [Rate Limiting](#rate-limiting)
- [Immediate Sends](#immediate-sends)
- [Queue Cancellation](#queue-cancellation)
- [Connections and Listeners](#connections-and-listeners)
- [Manual Flushing](#manual-flushing)
- [Statistics](#statistics)
- [Compression Statistics](#compression-statistics)
- [Bandwidth Statistics](#bandwidth-statistics)
- [Transport Statistics](#transport-statistics)
- [Health Monitoring](#health-monitoring)
- [Codec API](#codec-api)
- [Configuration](#configuration)
- [Performance Guide](#performance-guide)
- [Clicker / Simulator Pattern](#clicker--simulator-pattern)
- [Movement Pattern](#movement-pattern)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)
- [Protocol and Compatibility](#protocol-and-compatibility)
- [Upgrade Notes](#upgrade-notes)

---

# What NetStream Does

Roblox remotes are intentionally simple.

That is often enough for small systems, but larger games commonly need additional behavior around networking:

- compact binary payloads;
- small route identifiers;
- schema-driven encoding;
- reliable and unreliable traffic;
- batching;
- state coalescing;
- request/response calls;
- bounded queues;
- inbound rate limits;
- outbound bandwidth control;
- compression;
- packet-size diagnostics;
- message-rate diagnostics;
- overload protection;
- reusable shared route definitions.

NetStream handles those concerns while keeping the public API close to normal Roblox networking.

Instead of sending arbitrary values directly through a remote, NetStream generally follows this pipeline:

```text
Gameplay data
    │
    ▼
Route validation
    │
    ▼
Schema or dynamic encoding
    │
    ├── optional Compression v2.3.2
    │
    ▼
Queue / Latest slot
    │
    ▼
Adaptive batching
    │
    ▼
Bandwidth governor
    │
    ▼
RemoteEvent / UnreliableRemoteEvent
    │
    ▼
Roblox network
```

The receiver performs the reverse operation and dispatches the decoded arguments to the registered route.

---

# v1.3.0 Highlights

NetStream v1.3.0 is a major step beyond the older v1.0.0 README.

## Compression v2.3.2 integration

NetStream now directly integrates **Compression v2.3.2** for:

- dynamic argument compression;
- compact table compression;
- mapped table keys;
- string compression;
- buffer compression;
- homogeneous arrays;
- delta arrays;
- run-length arrays;
- optional string dictionaries;
- compact map keys.

Compression is only accepted when the encoded result is actually beneficial under the configured minimum-savings threshold.

## Three packet protocols

v1.3.0 uses three packet forms:

```text
0x18  Normal multi-message batch
0x19  Single-message packet
0x1A  Compact single-table packet
```

The compact table protocol removes unnecessary framing when a single dynamic Event or State contains one compressible table.

## Adaptive batching

Messages can wait for a short transport window so multiple logical messages can share one packet.

Default windows:

```text
Normal   50 ms
Realtime 33 ms
Critical  0 ms
```

## Bandwidth governor

The outbound governor can:

- pace bytes;
- pace packet count;
- split oversized batches;
- defer flushes;
- drop disposable unreliable traffic under pressure;
- track estimated transport overhead;
- expose utilization and headroom.

## Better diagnostics

v1.3.0 exposes dedicated APIs for:

```lua
NetStream.GetCompressionStats()
NetStream.GetBandwidthStats()
NetStream.GetTransportStats()
NetStream.GetRateStats()
NetStream.GetHealth()
```

---

# How the Pipeline Works

Consider:

```lua
local PlayerData = NetStream.State("PlayerData", {
	Compression = true,
	Coalesce = true,
})
```

and:

```lua
PlayerData:SetLatestClient(player, {
	Clicks = 1000,
	Rebirths = 5,
	Gems = 250,
})
```

A simplified flow is:

```text
SetLatestClient
    │
    ▼
validate value
    │
    ▼
create KIND_STATE message
    │
    ▼
replace older unsent PlayerData state
    │
    ▼
wait for transport batching window
    │
    ▼
measure native NetStream encoding
    │
    ▼
try Compression v2.3.2
    │
    ├── compressed result smaller? use it
    │
    └── no gain? use native encoding
    │
    ▼
encode packet
    │
    ▼
bandwidth governor
    │
    ▼
RemoteEvent / UnreliableRemoteEvent
```

NetStream does **not** simply compress every payload.

It measures whether compression helps and rejects compression when it would waste bytes.

---

# Installation

## Required hierarchy

NetStream v1.3.0 requires Compression v2.3.2 as a child of the NetStream ModuleScript.

```text
ReplicatedStorage
└── NetStream
    └── Compression
```

Where:

```text
NetStream     = NetStream v1.3.0 ModuleScript
Compression   = Compression v2.3.2 ModuleScript
```

The dependency is checked when NetStream is required.

NetStream expects:

```lua
Compression.Version() == "2.3.2"
```

If the dependency is missing or the version is wrong, NetStream throws an error immediately.

## Start NetStream on the server

Create a normal Script in `ServerScriptService`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetStream = require(ReplicatedStorage.NetStream)

NetStream.Start()

print("NetStream", NetStream.GetVersion(), "started")
```

Starting NetStream on the server creates its internal remote folder.

By default:

```text
ReplicatedStorage
└── __NetStream_NetStream
    ├── R
    └── U
```

`R` is the reliable `RemoteEvent`.

`U` is an `UnreliableRemoteEvent` when available.

---

# Recommended Project Structure

```text
ReplicatedStorage
├── NetStream
│   └── Compression
└── NetworkRoutes

ServerScriptService
└── NetworkServer

StarterPlayer
└── StarterPlayerScripts
    └── NetworkClient
```

A shared `NetworkRoutes` ModuleScript is strongly recommended so the server and client register identical route IDs and schemas.

Example:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetStream = require(ReplicatedStorage.NetStream)
local T = NetStream.Types

return NetStream.DefineCompact({
	Click = {
		Type = "Event",
		Schema = {},
		MaxPerSecond = 20,
		Burst = 10,
	},

	Coins = {
		Type = "State",
		Schema = T.VarUInt,
		Coalesce = true,
	},

	PlayerData = {
		Type = "State",
		Compression = true,
		Coalesce = true,
	},

	GetCoins = {
		Type = "Function",
		Schema = {},
	},
})
```

---

# Quick Start

## Client -> Server Event

Shared:

```lua
local Ping = NetStream.Event("Ping", {
	Id = 1,
	Schema = {
		NetStream.Types.String,
	},
})
```

Client:

```lua
Ping:FireServer("Hello")
```

Server:

```lua
Ping:Connect(function(player, message)
	print(player.Name, message)
end)
```

Server listeners receive the `Player` first.

Client listeners receive only the route arguments.

---

# Routes

NetStream has three primary route types.

```lua
NetStream.Event(...)
NetStream.State(...)
NetStream.Function(...)
```

Internally the message kinds are:

```text
0  Event
1  Call
2  Return
3  State
```

Each route receives a numeric ID.

If no explicit ID is supplied, NetStream hashes the route name.

You can inspect a route:

```lua
print(Route:GetName())
print(Route:GetId())
print(Route:GetPriority())
```

---

# DefineCompact

For most shared route tables, prefer:

```lua
NetStream.DefineCompact(...)
```

Example:

```lua
local Routes = NetStream.DefineCompact({
	Damage = {
		Type = "Event",
		Schema = {
			NetStream.Types.U16,
			NetStream.Types.U16,
		},
	},

	Health = {
		Type = "State",
		Schema = NetStream.Types.U16,
		Coalesce = true,
	},

	GetProfile = {
		Type = "Function",
		Schema = {},
	},
})
```

`DefineCompact()` assigns deterministic small IDs within each route category.

Small IDs are useful because route IDs are encoded as VarUInt values.

The same shared definition must be required by the server and client.

## Important Priority note

The v1.3.0 direct route constructors support:

```lua
Priority = "Critical"
Priority = "Normal"
Priority = "Realtime"
```

However, the current `Define()` / `DefineCompact()` forwarding table does not forward the `Priority` field.

If you need a custom priority in this exact v1.3.0 build, create that route directly:

```lua
local Movement = NetStream.Event("Movement", {
	Id = 1,
	Priority = "Realtime",
	Schema = {
		NetStream.Types.Vector3Q(100),
	},
})
```

---

# Events

Events are one-way messages.

## Client -> Server

```lua
Routes.Click:FireServer()
```

Server:

```lua
Routes.Click:Connect(function(player)
	print(player.Name, "clicked")
end)
```

## Server -> Client

```lua
Routes.Notification:FireClient(player, "Welcome")
```

## Server -> All

```lua
Routes.RoundStarted:FireAll(roundNumber)
```

## Server -> Everyone Except One Player

```lua
Routes.Effect:FireAllExcept(exceptPlayer, effectId)
```

## Generic Fire

Client:

```lua
Route:Fire(...)
```

acts like:

```lua
Route:FireServer(...)
```

Server:

```lua
Route:Fire(player, ...)
```

targets one player when the first argument is a `Player`.

Otherwise:

```lua
Route:Fire(...)
```

broadcasts to all clients.

---

# Unreliable Events

Use unreliable traffic when a newer update makes an older update disposable.

Good candidates:

```text
movement
aim direction
camera direction
temporary effects
frequent snapshots
cursor position
non-critical interpolation targets
```

Create an unreliable route:

```lua
local Movement = NetStream.Unreliable("Movement", {
	Id = 1,
	Schema = {
		NetStream.Types.Vector3Q(100),
	},
	Coalesce = true,
})
```

or:

```lua
local Movement = NetStream.Event("Movement", {
	Id = 1,
	Unreliable = true,
	Schema = {
		NetStream.Types.Vector3Q(100),
	},
})
```

Manual unreliable methods:

```lua
Event:FireUnreliableServer(...)
Event:FireUnreliableClient(player, ...)
Event:FireUnreliableAll(...)
```

NetStream only uses the unreliable remote when the encoded packet is within:

```lua
UnreliableMaxBytes = 900
```

Otherwise it may fall back to reliable transport.

Check:

```lua
NetStream.GetStats().FallbackReliable
```

---

# States

A State route stores the most recently received value for that route.

State schemas must contain exactly one type.

```lua
local Health = NetStream.State("Health", {
	Id = 1,
	Schema = NetStream.Types.U16,
})
```

Server -> client:

```lua
Health:SetClient(player, 100)
```

Client:

```lua
Health:Connect(function(value)
	print("Health:", value)
end)
```

Read the most recently received value:

```lua
local health = Health:Get()
```

Client -> server:

```lua
Health:SetServer(95)
```

Server:

```lua
Health:Connect(function(player, value)
	print(player.Name, value)
end)
```

Server-side read:

```lua
local latest = Health:Get(player)
```

Broadcast:

```lua
Health:SetAll(100)
```

Latest/coalesced:

```lua
Health:SetLatestServer(value)
Health:SetLatestClient(player, value)
Health:SetLatestAll(value)
```

---

# Functions / RPC

Functions provide request/response behavior using NetStream messages.

Shared:

```lua
local GetCoins = NetStream.Function("GetCoins", {
	Id = 1,
	Schema = {},
})
```

Server:

```lua
GetCoins:SetCallback(function(player)
	return 1250
end)
```

Client:

```lua
local coins = GetCoins:InvokeServer()

print(coins)
```

RPC requests receive a request ID and wait for a matching return packet.

Default timeout:

```lua
CallTimeout = 8
```

Immediate RPC:

```lua
FunctionRoute:InvokeServerNow(...)
FunctionRoute:InvokeClientNow(player, ...)
```

Aliases:

```lua
FunctionRoute:InvokeServerImmediate(...)
FunctionRoute:InvokeClientImmediate(player, ...)
```

Do not use RPC every frame.

Use Events or States for high-frequency traffic.

---

# Schemas

Schemas tell NetStream exactly what a route contains.

This removes dynamic type metadata and lets NetStream write the values directly.

Example:

```lua
local Damage = NetStream.Event("Damage", {
	Id = 1,
	Schema = {
		NetStream.Types.U16,
		NetStream.Types.U16,
	},
})
```

Usage:

```lua
Damage:FireServer(targetId, damage)
```

## Available schema types

| Type | Description |
|---|---|
| `T.Bool` | Boolean |
| `T.U8` | Unsigned 8-bit integer |
| `T.U16` | Unsigned 16-bit integer |
| `T.I16` | Signed 16-bit integer |
| `T.U32` | Unsigned 32-bit integer |
| `T.I32` | Signed 32-bit integer |
| `T.VarUInt` | Variable-length unsigned integer |
| `T.VarInt` | Variable-length signed integer |
| `T.F32` | 32-bit float |
| `T.F64` | 64-bit float |
| `T.String` | String with optional Compression v2.3.2 |
| `T.Buffer` | Buffer with optional Compression v2.3.2 |
| `T.Vector2Q(precision)` | Quantized Vector2 |
| `T.Vector3Q(precision)` | Quantized Vector3 |
| `T.CFrameQ(precision)` | Quantized position + quaternion rotation |
| `T.Color3` | 3-byte RGB color |
| `T.UDim` | UDim |
| `T.UDim2` | UDim2 |
| `T.Rect` | Rect |
| `T.NumberRange` | NumberRange |
| `T.BrickColor` | BrickColor |
| `T.DateTime` | DateTime |

## VarUInt

For non-negative integer values that are usually small:

```lua
T.VarUInt
```

is often a strong choice.

Typical size:

```text
0 - 127        1 byte
128 - 16383    2 bytes
16384+         3+ bytes
```

## Quantized vectors

```lua
T.Vector3Q(100)
```

multiplies each component by `100`, rounds it, and writes the result using VarInt encoding.

That preserves approximately two decimal places while avoiding three full 64-bit numbers.

## Quantized CFrame

```lua
T.CFrameQ(100)
```

encodes:

- quantized X;
- quantized Y;
- quantized Z;
- quaternion X;
- quaternion Y;
- quaternion Z;
- quaternion W.

Quaternion values are stored as four signed 16-bit integers.

---

# Dynamic Encoding

Schemas are optional.

Without a schema, NetStream can dynamically encode:

```text
nil
boolean
number
string
buffer
table
Vector2
Vector3
Color3
CFrame
UDim
UDim2
Rect
NumberRange
BrickColor
DateTime
```

Dynamic values include compact type descriptors.

Small unsigned integers `0..14` can be stored directly inside the descriptor byte.

Repeated strings inside the same encoded packet can use string references instead of writing the same string repeatedly.

Example:

```lua
DebugRoute:FireServer({
	Action = "Equip",
	Item = "Sword",
	Rarity = "Legendary",
})
```

Dynamic encoding is convenient for flexible or infrequent data.

Schemas are usually better for hot paths.

---

# Compression v2.3.2 Integration

NetStream requires:

```text
Compression v2.3.2
```

and exposes it as:

```lua
NetStream.Compression
```

Check:

```lua
print(NetStream.CompressionVersion)
print(NetStream.RequiredCompressionVersion)
```

Both should report:

```text
2.3.2
```

## Compression is selective

NetStream does not assume compressed data is smaller.

For a candidate dynamic payload it measures:

```text
native NetStream cost
vs
Compression v2.3.2 cost
```

and accepts compression only when:

```text
compressed cost + CompressionMinSavingsBytes <= raw cost
```

Default:

```lua
CompressionMinSavingsBytes = 1
```

So compression must save at least one byte.

Tiny values frequently remain in native NetStream encoding because adding compression framing would be wasteful.

## Compression candidates

Automatic dynamic compression is considered when arguments contain:

- a table;
- a sufficiently long string;
- a sufficiently large buffer.

Default thresholds:

```lua
CompressionMinStringBytes = 8
CompressionMinBufferBytes = 6
```

## Compression options passed to v2.3.2

NetStream configures Compression with:

```lua
{
	Mode = "Binary",
	CompressStrings = true,
	StringMinLength = Config.CompressionMinStringBytes,
	StringStrategy = Config.CompressionStringStrategy,
	UseStringDictionary = Config.CompressionUseStringDictionary,

	TableCompression = Config.CompressionTableCompression,
	TableStrategy = Config.CompressionTableStrategy,
	HomogeneousArrays = Config.CompressionHomogeneousArrays,
	DeltaArrays = Config.CompressionDeltaArrays,
	RunLengthArrays = Config.CompressionRunLengthArrays,
	CompactMapKeys = Config.CompressionCompactMapKeys,
	TableKeyMapping = Config.CompressionTableKeyMapping,
	MappedKeyMinUses = Config.CompressionMappedKeyMinUses,
	MaxMappedKeys = Config.CompressionMaxMappedKeys,

	CompressBuffers = Config.CompressionCompressBuffers,
	BufferMinLength = Config.CompressionMinBufferBytes,
	BufferStrategy = Config.CompressionBufferStrategy,

	AllowExpansion = Config.CompressionAllowExpansion,
}
```

---

# Compact Single-Table Packets

One of v1.3.0's most aggressive framing optimizations is protocol `0x1A`.

A compact single-table packet can be used when:

- the packet contains one message;
- the route is an Event or State;
- the route is dynamic, not schema-based;
- the message has exactly one argument;
- that argument is a table;
- the route ID is `0..63`;
- compression is enabled for the route;
- Compression v2.3.2 produces a smaller total packet.

Conceptually:

```text
0x1A
packed route + kind
compressed table bytes...
```

Because the compressed data runs to the end of the packet, NetStream does not need to send a separate compressed-payload length.

This can save:

- normal batch count framing;
- normal message framing;
- dynamic compression control bytes;
- payload length bytes.

Related stats:

```text
CompressionCompactSingleSent
CompressionCompactSingleReceived
CompressionDirectTableUsed
CompressionTailLengthElisions
CompressionFramingBytesSaved
CompressionEstimatedNetBytesSaved
SingleMessageHeaderBytesSaved
```

Small compact route IDs are especially useful for this path.

---

# Schema String and Buffer Compression

Schema routes are already compact, so NetStream does not wrap every schema payload in general table compression.

Instead, v1.3.0 selectively compresses schema strings and buffers.

## Schema strings

For:

```lua
Schema = {
	T.String,
}
```

NetStream compares:

```text
raw string bytes
vs
Compression.CompressString(...)
```

It also supports string references inside the packet.

Related stats:

```text
CompressedSchemaStrings
SchemaStringBytesSaved
```

## Schema buffers

For:

```lua
Schema = {
	T.Buffer,
}
```

NetStream compares:

```text
raw buffer
vs
Compression.CompressBuffer(...)
```

Related stats:

```text
CompressedSchemaBuffers
SchemaBufferBytesSaved
```

This is useful because numeric schema fields are often already too compact to benefit from another compression layer.

---

# Batching and Transport Windows

Normal sends are queued instead of immediately calling a RemoteEvent.

This allows several logical messages to share one transport packet.

Default:

```lua
FlushRate = 30
```

so NetStream's scheduled flush loop checks approximately 30 times per second.

Adaptive batching adds a separate minimum hold window based on priority.

Defaults:

```lua
TransportAdaptiveBatching = true

TransportBatchWindowSeconds = 0.050
TransportRealtimeBatchWindowSeconds = 0.033
TransportTargetMessagesPerPacket = 8
```

Priority behavior:

```text
Critical  no batching hold
Realtime  ~33 ms batching window
Normal    ~50 ms batching window
```

A bucket may flush sooner when it reaches:

```lua
TransportTargetMessagesPerPacket
```

This can reduce the number of Roblox remote sends at the cost of a small amount of queue latency.

---

# Schema Event Runs

When consecutive schema Events use:

- the same route;
- the same schema;
- the same message kind;

NetStream can encode them as a schema run.

Instead of:

```text
route + payload
route + payload
route + payload
route + payload
```

the packet can resemble:

```text
route
run count
payload
payload
payload
payload
```

The route ID is written once.

## Boolean runs

A repeated schema Event containing one `Bool` field is bit-packed.

Eight boolean values can use one payload byte.

Example logical values:

```text
true
false
true
true
false
false
true
false
```

can be represented in one packed byte for the boolean run data.

---

# Coalescing and Latest

Compression makes a payload smaller.

Coalescing can avoid sending an obsolete payload at all.

For rapidly changing state:

```lua
Position:SetLatestClient(player, value1)
Position:SetLatestClient(player, value2)
Position:SetLatestClient(player, value3)
```

if none have been sent yet, only the newest value needs to remain queued.

Enable on a route:

```lua
Coalesce = true
```

Aliases:

```lua
Latest = true
Mode = "Latest"
Mode = "latest"
```

Explicit Event methods:

```lua
Event:LatestServer(...)
Event:LatestClient(player, ...)
Event:LatestAll(...)
```

Explicit State methods:

```lua
State:SetLatestServer(value)
State:SetLatestClient(player, value)
State:SetLatestAll(value)
```

Latest methods use unreliable + coalesced behavior.

Check:

```lua
NetStream.GetStats().CoalescedLatest
```

For movement, counters, aim, and current UI state, coalescing is often more valuable than compressing every intermediate update.

---

# Priorities

NetStream recognizes:

```text
Critical
Normal
Realtime
```

Default priorities:

```text
Function calls / Returns  Critical
Events                    Normal
States                    Normal
```

Direct route example:

```lua
local Aim = NetStream.Event("Aim", {
	Id = 1,
	Priority = "Realtime",
	Schema = {
		NetStream.Types.Vector3Q(100),
	},
	Unreliable = true,
	Coalesce = true,
})
```

Priority primarily controls adaptive batching delay.

Critical messages can force the bucket's wait deadline to the current time.

---

# Bandwidth Governor

The outbound bandwidth governor is enabled by default.

```lua
BandwidthGovernorEnabled = true
```

Default limits:

```lua
BandwidthLimitBytesPerSecond = 768
BandwidthMaxPacketBytes = 192
BandwidthMaxPacketsPerSecond = 6

BandwidthMaxReliableQueue = 384
BandwidthMaxUnreliableQueue = 96

BandwidthDropUnreliableOnPressure = true
BandwidthWarnAtUtilization = 0.85
```

## Estimated transport cost

NetStream does not know Roblox's exact final transport overhead.

Instead it uses a configurable estimate:

```lua
TransportEstimatedPacketOverheadBytes = 96
```

For governor accounting:

```text
charged bytes =
encoded NetStream packet bytes
+ estimated packet overhead
```

Example:

```text
Encoded packet        80 B
Estimated overhead    96 B
--------------------------
Governor charge      176 B
```

This estimate is also exposed through the transport statistics.

## What the governor can do

Under pressure NetStream can:

- defer a flush;
- defer a batch;
- split a multi-message batch;
- reject reliable queue growth;
- drop older unreliable queue entries;
- drop deferred unreliable messages;
- coalesce Latest updates;
- pace packet count;
- pace estimated byte rate.

## Important

`BandwidthMaxPacketBytes` is mainly a batching target.

Multi-message batches are split while possible.

A single reliable logical message that is itself larger may still be sent and counted as oversized.

Disposable unreliable traffic may be dropped under pressure depending on configuration.

## The default is intentionally strict

`768 B/s` and `6 packets/s` are conservative for a complete game networking layer.

Do not blindly raise the values, but do profile real gameplay and tune them for your game's traffic requirements.

Use:

```lua
NetStream.GetBandwidthStats()
NetStream.GetTransportStats()
NetStream.GetHealth()
```

while testing.

---

# Rate Limiting

NetStream has two different protection systems.

## Envelope / global limits

The server limits incoming:

- bytes;
- batches;
- messages;
- function calls.

Both per-player and global limits are available.

Defaults include:

```lua
MaxIncomingMessagesPerSecond = 30000
MaxIncomingBytesPerSecond = 2 * 1024 * 1024
MaxIncomingBatchesPerSecond = 240

MaxGlobalIncomingMessagesPerSecond = 120000
MaxGlobalIncomingBytesPerSecond = 8 * 1024 * 1024
MaxGlobalIncomingBatchesPerSecond = 8192

MaxIncomingCallsPerSecond = 240
MaxGlobalIncomingCallsPerSecond = 4096
```

## Per-route token bucket

Events and States can define:

```lua
MaxPerSecond = 20
Burst = 5
```

Example:

```lua
local Shoot = NetStream.Event("Shoot", {
	Id = 1,
	Schema = {
		NetStream.Types.U16,
	},
	MaxPerSecond = 20,
	Burst = 5,
})
```

This limits how many accepted route messages each player can consume per second.

Rate limiting does **not** replace gameplay validation.

---

# Immediate Sends

Normal sends benefit from batching.

Latency-sensitive actions can flush immediately.

Client:

```lua
Route:FireServerNow(...)
```

Server:

```lua
Route:FireClientNow(player, ...)
Route:FireAllNow(...)
Route:FireAllExceptNow(player, ...)
```

State:

```lua
State:SetServerNow(value)
State:SetClientNow(player, value)
State:SetAllNow(value)
```

RPC:

```lua
Function:InvokeServerNow(...)
Function:InvokeClientNow(player, ...)
```

Aliases ending in `Immediate` are also available.

A route can also be configured:

```lua
Immediate = true
```

Do not make every route Immediate.

Immediate traffic reduces batching opportunity and can increase packet count.

The bandwidth governor still applies to immediate flushes.

If an immediate flush cannot complete because of transport limits, NetStream records:

```text
TransportImmediateDeferred
```

---

# Queue Cancellation

Stopping the code that produces messages does not automatically remove messages already queued inside NetStream.

Events:

```lua
Event:CancelQueuedServer()
Event:CancelQueuedClient(player)
Event:CancelQueuedAll()
```

Latest only:

```lua
Event:CancelLatestServer()
Event:CancelLatestClient(player)
Event:CancelLatestAll()
```

States provide the same cancellation pattern.

Example:

```lua
connection:Disconnect()

Routes.Movement:CancelQueuedServer()
```

This removes unsent NetStream messages for the route.

Messages already passed into Roblox networking cannot be recalled.

---

# Connections and Listeners

Events and States use connection-style listeners.

## Connect

```lua
local connection = Route:Connect(function(...)
	print(...)
end)
```

## Once

```lua
Route:Once(function(...)
	print("one time")
end)
```

## Disconnect

```lua
connection:Disconnect()
```

## Connection status

```lua
print(connection:IsConnected())
```

## Wait

```lua
local value, err = Route:Wait(5)

if value == nil and err then
	warn(err)
end
```

## Disconnect all listeners

```lua
Route:DisconnectAll()
```

## Listener diagnostics

```lua
Route:ListenerCount()
Route:GetListenerCount()
Route:HasListeners()
```

---

# Manual Flushing

Most projects should let NetStream flush automatically.

For tests and special cases:

```lua
local bytes, batches, messages = NetStream.Flush()

print(bytes, batches, messages)
```

Alias:

```lua
NetStream.FlushNow()
```

Server target:

```lua
NetStream.FlushTarget(player)
```

Server broadcast bucket:

```lua
NetStream.FlushTarget()
```

Client:

```lua
NetStream.FlushTarget()
```

---

# Statistics

Basic statistics:

```lua
local stats = NetStream.GetStats()

print(stats.SentBytes)
print(stats.ReceivedBytes)
print(stats.SentMessages)
print(stats.ReceivedMessages)
print(stats.SentBatches)
print(stats.ReceivedBatches)
```

Useful fields include:

```text
SentBatches
SentBytes
ReceivedBatches
ReceivedBytes

SentMessages
ReceivedMessages

SchemaMessages
DynamicMessages

SingleMessagePackets
SingleMessageHeaderBytesSaved

CoalescedLatest

FallbackReliable
DroppedUnreliable
RejectedReliable

DecodeErrors
RejectedMessages
RejectedMalformedPackets
RejectedOversizedPackets

RateLimitedBatches
GlobalRateLimitedBatches
RateLimitedCalls
GlobalRateLimitedCalls
RouteRateLimited

CallsTimedOut
DroppedDispatch

ManualFlushes
ImmediateFlushes

CancelledLatest
CancelledQueued

MessagePoolHits
ArgsPoolHits
WriterPoolHits
ReaderPoolHits
BatchPoolHits

QueuedReliable
QueuedUnreliable
PendingCalls
DispatchBacklog
ActiveTargetBacklog

AverageBatchBytes
AverageMessagesPerBatch
```

Pool sizes are also added to `GetStats()`:

```text
MessagePoolSize
ArgsPoolSize
WriterPoolSize
ReaderPoolSize
BatchPoolSize
```

Live rate data:

```lua
local rates = NetStream.GetRateStats()
```

includes:

```text
SentBytesPerSecond
ReceivedBytesPerSecond
SentMessagesPerSecond
ReceivedMessagesPerSecond
SentBatchesPerSecond
ReceivedBatchesPerSecond

BandwidthLimitBytesPerSecond
BandwidthUtilization
BandwidthHeadroomBytesPerSecond

EstimatedTransportBytesPerSecond
EstimatedTransportUtilization
EstimatedTransportHeadroomBytesPerSecond
```

Reset:

```lua
NetStream.ResetStats()
```

Last encoded packet:

```lua
NetStream.GetLastPacketBytes()
```

---

# Compression Statistics

```lua
local compression = NetStream.GetCompressionStats()
```

Important fields:

```text
Version
Enabled

Attempts
Used
Rejected
Errors
NoGain
AcceptancePercent

Decoded

InputBytes
OutputBytes
SavedBytes
AverageSavedBytes
SavingsPercent
Ratio

StringStrategy
BufferStrategy
TableStrategy
TableKeyMapping
AllowExpansion

CompactTablesUsed
MappedTablesUsed
DynamicTablesUsed
DirectTablesUsed

TailLengthElisions
CompactSingleSent
CompactSingleReceived

FramingBytesSaved
EstimatedNetBytesSaved

SingleMessagePackets
SingleMessageHeaderBytesSaved

CompressedSchemaStrings
SchemaStringBytesSaved

CompressedSchemaBuffers
SchemaBufferBytesSaved
```

Example monitor:

```lua
local stats = NetStream.GetCompressionStats()

print("Compression", stats.Version)
print("Accepted:", stats.AcceptancePercent .. "%")
print("Saved:", NetStream.FormatBytes(stats.SavedBytes))
print("Estimated net saved:", NetStream.FormatBytes(stats.EstimatedNetBytesSaved))
```

---

# Bandwidth Statistics

```lua
local bandwidth = NetStream.GetBandwidthStats()
```

Fields:

```text
Enabled
LimitBytesPerSecond
MaxPacketBytes
MaxPacketsPerSecond

SentBytesPerSecond
ReceivedBytesPerSecond

EstimatedTransportBytesPerSecond
EstimatedPacketOverheadBytes

Utilization
HeadroomBytesPerSecond

DeferredFlushes
DeferredBatches
DeferredBytes

DroppedUnreliableMessages
QueuePressureDrops

OversizedPackets
BatchSplits
ThrottleEvents
```

---

# Transport Statistics

```lua
local transport = NetStream.GetTransportStats()
```

Fields include:

```text
AdaptiveBatching
BatchWindowSeconds
RealtimeBatchWindowSeconds
EstimatedPacketOverheadBytes
TargetMessagesPerPacket

LogicalMessagesQueued
LogicalMessagesSent
TransportPackets
MessagesPerTransportPacket

EncodedBytesPerSecond
EstimatedTransportBytesPerSecond
PacketRatePerSecond

EstimatedUtilization
EstimatedHeadroomBytesPerSecond

BatchHolds
TargetFlushes
ImmediateDeferred

CriticalQueued
NormalQueued
RealtimeQueued

EstimatedOverheadBytes
EstimatedTransportBytes

CoalescedMessages
DroppedUnreliableMessages
DeferredBatches
BatchSplits
```

This is useful for determining whether your game is reducing packet count or merely reducing encoded payload bytes.

---

# Health Monitoring

```lua
local health = NetStream.GetHealth()

print(health.Status)
```

Possible status values:

```text
Healthy
Busy
Congested
Overloaded
```

The health result includes:

```text
QueuedMessages
DispatchBacklog
ActiveTargetBacklog

SentBytesPerSecond
ReceivedBytesPerSecond
SentMessagesPerSecond
ReceivedMessagesPerSecond

BandwidthLimitBytesPerSecond
BandwidthUtilization
BandwidthHeadroomBytesPerSecond

EstimatedTransportBytesPerSecond
TransportPacketRatePerSecond
```

Example:

```lua
task.spawn(function()
	while true do
		task.wait(1)

		local health = NetStream.GetHealth()

		print(
			"Network:",
			health.Status,
			string.format("%.1f%%", health.BandwidthUtilization * 100),
			"queued:",
			health.QueuedMessages
		)
	end
end)
```

---

# Codec API

`NetStream.Codec` exposes a standalone Compression-backed argument codec.

## Encode

```lua
local data = NetStream.Codec.Encode(
	123,
	true,
	"Hello",
	{
		Coins = 500,
	}
)
```

Returns a Roblox `buffer`.

## Decode

```lua
local numberValue, boolValue, text, data =
	NetStream.Codec.Decode(bufferValue)
```

## TryEncode

```lua
local ok, data, err = NetStream.Codec.TryEncode(...)
```

## TryDecode

```lua
local ok, args, err = NetStream.Codec.TryDecode(data)

if ok then
	print(args.n)
end
```

`TryDecode` returns the packed argument table rather than automatically unpacking it.

## ByteLength

```lua
local bytes = NetStream.Codec.ByteLength(...)
```

## Analyze

```lua
local analysis = NetStream.Codec.Analyze(...)
```

## Direct Compression access

The actual Compression v2.3.2 module is exposed as:

```lua
NetStream.Compression
```

For example:

```lua
print(NetStream.Compression.Version())
```

NetStream also exposes:

```lua
NetStream.AnalyzeCompression(value)
NetStream.GetCompressionOptions()
```

---

# Configuration

Configuration must happen before:

- the first route is created;
- `NetStream.Start()` is called.

Example:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetStream = require(ReplicatedStorage.NetStream)

NetStream.Configure({
	FlushRate = 30,

	BandwidthLimitBytesPerSecond = 4096,
	BandwidthMaxPacketBytes = 512,
	BandwidthMaxPacketsPerSecond = 30,

	Debug = false,
})

NetStream.Start()
```

Read the active configuration:

```lua
local config = NetStream.GetConfig()
```

## Core defaults

| Setting | Default |
|---|---:|
| `Namespace` | `"NetStream"` |
| `RemoteWaitTimeout` | `10` |
| `FlushRate` | `30` |
| `MaxBatchMessages` | `256` |
| `MaxOutgoingBatchBytes` | `2 MiB` |
| `MaxIncomingPacketBytes` | `2 MiB` |
| `MaxBatchesPerFlush` | `4` |
| `MaxDispatchPerCycle` | `2048` |
| `MaxDispatchBacklog` | `16384` |
| `DispatchBudgetSeconds` | `0.0025` |
| `FlushBudgetSeconds` | `0.003` |
| `ImmediateFlushBudgetSeconds` | `0.004` |
| `TimeoutSweepInterval` | `0.25` |
| `MaxTargetsPerFlush` | `128` |
| `CallTimeout` | `8` |
| `VectorPrecision` | `100` |
| `MaxIncomingMessages` | `512` |
| `MaxStringBytes` | `1 MiB` |
| `MaxBufferBytes` | `1 MiB` |
| `MaxTableEntries` | `8192` |
| `MaxDepth` | `32` |

## Queue defaults

| Setting | Default |
|---|---:|
| `MaxReliableQueue` | `8192` |
| `MaxUnreliableQueue` | `2048` |
| `UnreliableMaxBytes` | `900` |
| `MaxPoolSize` | `2048` |
| `MaxPooledArgs` | `32` |
| `MaxPooledWriterBytes` | `128 KiB` |
| `MaxPooledStrings` | `2048` |
| `MaxBatchPoolSize` | `64` |

## Compression defaults

| Setting | Default |
|---|---|
| `CompressionEnabled` | `true` |
| `CompressionMinSavingsBytes` | `1` |
| `CompressionMinStringBytes` | `8` |
| `CompressionStringStrategy` | `"Auto"` |
| `CompressionUseStringDictionary` | `true` |
| `CompressionTableCompression` | `true` |
| `CompressionTableStrategy` | `"Auto"` |
| `CompressionHomogeneousArrays` | `true` |
| `CompressionDeltaArrays` | `true` |
| `CompressionRunLengthArrays` | `true` |
| `CompressionCompactMapKeys` | `true` |
| `CompressionTableKeyMapping` | `true` |
| `CompressionMappedKeyMinUses` | `2` |
| `CompressionMaxMappedKeys` | `255` |
| `CompressionCompressBuffers` | `true` |
| `CompressionMinBufferBytes` | `6` |
| `CompressionBufferStrategy` | `"Auto"` |
| `CompressionAllowExpansion` | `false` |

## Bandwidth defaults

| Setting | Default |
|---|---:|
| `BandwidthGovernorEnabled` | `true` |
| `BandwidthLimitBytesPerSecond` | `768` |
| `BandwidthMaxPacketBytes` | `192` |
| `BandwidthMaxPacketsPerSecond` | `6` |
| `BandwidthMaxReliableQueue` | `384` |
| `BandwidthMaxUnreliableQueue` | `96` |
| `BandwidthDropUnreliableOnPressure` | `true` |
| `BandwidthWarnAtUtilization` | `0.85` |

## Adaptive transport defaults

| Setting | Default |
|---|---:|
| `TransportAdaptiveBatching` | `true` |
| `TransportBatchWindowSeconds` | `0.050` |
| `TransportRealtimeBatchWindowSeconds` | `0.033` |
| `TransportEstimatedPacketOverheadBytes` | `96` |
| `TransportTargetMessagesPerPacket` | `8` |

## Compression strategies

String:

```text
Auto
Raw
LZ
ASCII7
Identifier6
Numeric4
```

Table:

```text
Auto
Compact
Dynamic
```

Buffer:

```text
Auto
Raw
LZ
Sparse
Nibble
```

---

# Performance Guide

## 1. Use schemas for hot scalar routes

Prefer:

```lua
Schema = {
	T.VarUInt,
}
```

for a frequently changing counter rather than:

```lua
{
	Clicks = value
}
```

on every update.

Schemas remove dynamic field/type metadata.

## 2. Use Compression for structured snapshots

A larger table such as:

```lua
{
	Clicks = 100000,
	Rebirths = 25,
	Gems = 7500,
	Tokens = 40,
	Prestiges = 2,
}
```

is a good candidate for a dynamic State with Compression enabled.

## 3. Coalesce current-state traffic

If intermediate values are useless:

```lua
Coalesce = true
```

or use a Latest method.

Sending one final value is better than compressing ten obsolete values.

## 4. Prefer compact IDs

Use `DefineCompact()` when both peers share the same route definition.

Small IDs reduce VarUInt route overhead and can unlock the compact `0x1A` single-table path for route IDs below `64`.

## 5. Use unreliable traffic only when loss is acceptable

Good:

```text
movement
aim
camera
interpolation targets
frequent non-critical snapshots
```

Not good:

```text
purchase
inventory mutation
reward
save confirmation
critical match result
```

## 6. Keep Immediate rare

Immediate sends reduce latency but also reduce batching opportunity.

## 7. Do not RPC every frame

RPC yields and requires a return packet.

## 8. Tune the bandwidth governor with real data

Watch:

```lua
NetStream.GetBandwidthStats()
NetStream.GetTransportStats()
NetStream.GetHealth()
```

The default governor is strict.

Increase limits only after measuring a realistic player session.

## 9. Measure more than payload bytes

`SentBytes` is the size of the encoded NetStream buffers.

`EstimatedTransportBytes` adds NetStream's configured transport-overhead estimate.

Neither is guaranteed to exactly match Roblox's internal final wire cost.

Use Roblox's networking/profiling tools as well.

## 10. Watch compression acceptance

If:

```text
CompressionAttempts is high
CompressionUsed is low
CompressionNoGain is high
```

your routes may already be compact enough without Compression.

That is not necessarily a problem.

NetStream is correctly rejecting expansion.

---

# Clicker / Simulator Pattern

For a clicker or simulator, do not automatically send the entire profile every time one stat changes.

Use compact scalar States for hot counters and a compressed table for occasional full snapshots.

## Shared routes

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetStream = require(ReplicatedStorage.NetStream)
local T = NetStream.Types

return NetStream.DefineCompact({
	Click = {
		Type = "Event",
		Schema = {},
		MaxPerSecond = 25,
		Burst = 10,
	},

	Clicks = {
		Type = "State",
		Schema = T.VarUInt,
		Coalesce = true,
	},

	Rebirths = {
		Type = "State",
		Schema = T.VarUInt,
		Coalesce = true,
	},

	Gems = {
		Type = "State",
		Schema = T.VarUInt,
		Coalesce = true,
	},

	ProfileSnapshot = {
		Type = "State",
		Compression = true,
		Coalesce = true,
	},
})
```

## Hot stat update

Server:

```lua
Routes.Clicks:SetLatestClient(player, data.Clicks)
```

If the value changes several times before transmission, older unsent values are replaced.

## Full snapshot

```lua
Routes.ProfileSnapshot:SetLatestClient(player, {
	Clicks = data.Clicks,
	Rebirths = data.Rebirths,
	Gems = data.Gems,
	Tokens = data.Tokens,
	SuperRebirths = data.SuperRebirths,
	Ascensions = data.Ascensions,
	Prestiges = data.Prestiges,
	EggsOpened = data.EggsOpened,
	PetsDiscovered = data.PetsDiscovered,
})
```

Compression v2.3.2 can then evaluate compact/mapped table encoding for the full profile.

This gives two different optimizations:

```text
Schemas + VarUInt
    -> make frequent scalar values cheap

Compression + table mapping
    -> make larger snapshots smaller

Coalescing
    -> avoid transmitting obsolete values entirely
```

---

# Movement Pattern

Shared:

```lua
local Movement = NetStream.Event("Movement", {
	Id = 1,
	Schema = {
		NetStream.Types.Vector3Q(100),
	},
	Unreliable = true,
	Coalesce = true,
	Priority = "Realtime",
	MaxPerSecond = 120,
	Burst = 30,
})
```

Client:

```lua
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local connection = RunService.Heartbeat:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if root then
		Movement:FireServer(root.Position)
	end
end)
```

Server:

```lua
Movement:Connect(function(player, position)
	-- Validate client-controlled movement before using it
	-- for authoritative gameplay.
end)
```

Stop:

```lua
connection:Disconnect()
Movement:CancelQueuedServer()
```

---

# Security

NetStream protects the networking layer.

It does not replace server-authoritative game logic.

A schema can prove:

```text
this argument is a U16
```

It cannot prove:

```text
this player is allowed to deal 500 damage
```

Always validate server-side:

- ownership;
- permissions;
- currency;
- inventory;
- target existence;
- cooldowns;
- distances;
- state transitions;
- item IDs;
- damage;
- movement;
- purchase eligibility;
- any client-provided value that affects authoritative gameplay.

## Trusted

```lua
Trusted = true
```

skips outgoing schema validation for that route.

It is a performance option for controlled producers.

It does **not** mean incoming client data is trustworthy.

---

# Troubleshooting

## `NetStream v1.3.0 requires a child ModuleScript named Compression`

Your hierarchy is wrong.

Use:

```text
NetStream
└── Compression
```

The Compression child must be v2.3.2.

---

## `NetStream v1.3.0 requires Compression v2.3.2`

The dependency exists, but:

```lua
Compression.Version()
```

does not equal:

```text
2.3.2
```

Update the Compression child.

---

## Client times out waiting for `__NetStream_NetStream`

Make sure the server requires NetStream and starts it before the client needs routes.

```lua
local NetStream = require(ReplicatedStorage.NetStream)

NetStream.Start()
```

Recommended server location:

```text
ServerScriptService
```

---

## Server and client disagree on routes

The peers must agree on:

- route type;
- route ID;
- schema;
- protocol-compatible NetStream version.

Use one shared route ModuleScript.

---

## `DefineCompact` routes do not match

Both peers must define the same route names and route kinds.

IDs are assigned deterministically from the definition set.

If one peer removes or changes an entry, IDs can differ.

---

## Compression is constantly rejected

Check:

```lua
local stats = NetStream.GetCompressionStats()

print(stats.NoGain)
print(stats.Errors)
```

A high `NoGain` count usually means native NetStream encoding was already smaller.

That is expected for tiny scalar payloads.

---

## Bandwidth is constantly throttled

Check:

```lua
local bandwidth = NetStream.GetBandwidthStats()

print(bandwidth.Utilization)
print(bandwidth.DeferredBatches)
print(bandwidth.ThrottleEvents)
```

The default:

```text
768 B/s
6 packets/s
```

is intentionally conservative.

Profile your real game and tune deliberately.

---

## Reliable queue is full

NetStream rejects new reliable messages rather than allowing unbounded growth.

Solutions:

- reduce send frequency;
- use `Coalesce = true` for current-state traffic;
- use unreliable traffic when appropriate;
- batch more;
- raise bandwidth limits only after profiling;
- investigate a blocked/overloaded receiver.

---

## RTT is higher than a raw RemoteEvent

Normal NetStream messages can intentionally wait for batching.

For a latency-sensitive route use:

```lua
Route:FireServerNow(...)
```

or a Critical/Immediate route.

Do not confuse scheduled batching delay with serializer CPU time.

---

## `SentBytes` does not match Roblox Studio's network numbers

Expected.

`SentBytes` measures NetStream's encoded buffer.

Roblox can add its own transport/protocol overhead after NetStream calls the remote.

`EstimatedTransportBytes` is still only an estimate.

---

## Unreliable traffic falls back to reliable

Possible causes:

- `UnreliableRemoteEvent` unavailable;
- packet larger than `UnreliableMaxBytes`;
- unreliable send failed and reliable fallback succeeded.

Inspect:

```lua
NetStream.GetStats().FallbackReliable
```

---

# API Reference

## NetStream

```lua
NetStream.Configure(options)
NetStream.Start()

NetStream.Event(nameOrId, options?)
NetStream.Unreliable(nameOrId, options?)
NetStream.State(nameOrId, options?)
NetStream.Function(nameOrId, options?)

NetStream.Define(routes)
NetStream.DefineCompact(routes)

NetStream.Id(name, kind?)

NetStream.Flush()
NetStream.FlushNow()
NetStream.FlushTarget(player?)

NetStream.GetVersion()
NetStream.GetConfig()

NetStream.IsStarted()
NetStream.IsDestroyed()

NetStream.GetState(player?)
NetStream.GetStateSnapshot(player?)

NetStream.GetStats()
NetStream.GetRateStats()
NetStream.GetBandwidthStats()
NetStream.GetTransportStats()
NetStream.GetCompressionStats()
NetStream.GetHealth()

NetStream.GetCompressionOptions()
NetStream.AnalyzeCompression(value, options?)

NetStream.GetSupportedTypes()
NetStream.GetCompatibilityInfo()

NetStream.GetLastPacketBytes()
NetStream.ResetStats()
NetStream.FormatBytes(bytes)

NetStream.Float32(value)
NetStream.RawString(value)

NetStream.Destroy()
```

Static fields:

```lua
NetStream.Types

NetStream.Version
NetStream.Protocol
NetStream.ProtocolSingle
NetStream.ProtocolCompactTable

NetStream.RequiredCompressionVersion
NetStream.CompressionVersion
NetStream.Compression

NetStream.Codec
```

---

## EventRoute

Listeners:

```lua
Event:Connect(callback)
Event:Once(callback)
Event:Wait(timeout?)
Event:DisconnectAll()

Event:ListenerCount()
Event:GetListenerCount()
Event:HasListeners()

Event:GetName()
Event:GetId()
Event:GetPriority()
Event:IsCoalescing()
```

Client:

```lua
Event:FireServer(...)
Event:FireServerNow(...)
Event:FireServerImmediate(...)

Event:FireUnreliableServer(...)

Event:LatestServer(...)

Event:CancelLatestServer()
Event:CancelQueuedServer()
```

Server:

```lua
Event:FireClient(player, ...)
Event:FireClientNow(player, ...)
Event:FireClientImmediate(player, ...)

Event:FireAll(...)
Event:FireAllNow(...)
Event:FireAllImmediate(...)

Event:FireAllExcept(player, ...)
Event:FireAllExceptNow(player, ...)

Event:FireUnreliableClient(player, ...)
Event:FireUnreliableAll(...)

Event:LatestClient(player, ...)
Event:LatestAll(...)

Event:CancelLatestClient(player)
Event:CancelLatestAll()

Event:CancelQueuedClient(player)
Event:CancelQueuedAll()
```

Generic:

```lua
Event:Fire(...)
Event:Send(...)
```

---

## StateRoute

Listeners use the same API as Event routes.

Client:

```lua
State:SetServer(value, unreliable?)
State:SetServerNow(value, unreliable?)
State:SetServerImmediate(value, unreliable?)

State:SetLatestServer(value)

State:CancelLatestServer()
State:CancelQueuedServer()

State:Get()
```

Server:

```lua
State:SetClient(player, value, unreliable?)
State:SetClientNow(player, value, unreliable?)
State:SetClientImmediate(player, value, unreliable?)

State:SetAll(value, unreliable?)
State:SetAllNow(value, unreliable?)
State:SetAllImmediate(value, unreliable?)

State:SetLatestClient(player, value)
State:SetLatestAll(value)

State:CancelLatestClient(player)
State:CancelLatestAll()

State:CancelQueuedClient(player)
State:CancelQueuedAll()

State:Get(player)
```

Generic:

```lua
State:Set(...)
```

---

## FunctionRoute

```lua
Function:SetCallback(callback)
Function:OnInvoke(callback)
Function:Bind(callback)

Function:GetPriority()

Function:InvokeServer(...)
Function:InvokeServerNow(...)
Function:InvokeServerImmediate(...)

Function:InvokeClient(player, ...)
Function:InvokeClientNow(player, ...)
Function:InvokeClientImmediate(player, ...)

Function:Invoke(...)
```

Server callbacks receive the player first.

Client callbacks receive only the function arguments.

---

## Codec

```lua
NetStream.Codec.Encode(...)
NetStream.Codec.Decode(buffer)

NetStream.Codec.TryEncode(...)
NetStream.Codec.TryDecode(buffer)

NetStream.Codec.ByteLength(...)
NetStream.Codec.Analyze(...)
```

---

## Legacy compatibility helpers

v1.3.0 still exposes compatibility helpers such as:

```lua
NetStream.Connect(id, callback)
NetStream.Once(id, callback)
NetStream.Fire(id, ...)
NetStream.FireAll(id, ...)
NetStream.FireToPlayer(player, id, ...)

NetStream.Call(id, ...)
NetStream.CallToPlayer(player, id, ...)
NetStream.OnCall(callback)

NetStream.StateUpdate(...)
NetStream.SetLatest(...)

NetStream.Move(...)
NetStream.GetPlayerState(player)

NetStream.ReliableEvent()
NetStream.ReliableFunction()
```

New code should generally prefer typed Route objects.

---

# Protocol and Compatibility

NetStream v1.3.0 exposes:

```text
Normal batch protocol         0x18
Single-message protocol       0x19
Compact single-table protocol 0x1A
```

You can inspect:

```lua
local info = NetStream.GetCompatibilityInfo()

print(info.Version)
print(info.CompressionVersion)
print(info.Protocol)
print(info.ProtocolSingle)
print(info.ProtocolCompactTable)
```

For production, run the same NetStream version on server and client.

NetStream v1.3.0 also requires exactly:

```text
Compression v2.3.2
```

Do not mix the v1.3.0 encoder with an older peer or a different Compression wire format.

---

# Upgrade Notes

When moving from the old v1.0.0 build to v1.3.0:

1. Replace the old NetStream ModuleScript.
2. Add `Compression v2.3.2` as a child named exactly `Compression`.
3. Confirm both server and client require the same NetStream v1.3.0 module.
4. Start NetStream early on the server.
5. Keep shared route definitions identical.
6. Re-test all schema routes.
7. Re-test dynamic table routes.
8. Re-test RPC.
9. Re-test unreliable traffic.
10. Re-test high-frequency movement/state routes.
11. Inspect compression acceptance and savings.
12. Inspect bandwidth utilization.
13. Inspect transport packet rate.
14. Tune the governor for your actual game instead of copying arbitrary high limits.
15. Use coalescing for values where only the newest state matters.
16. Keep Immediate traffic limited to latency-sensitive actions.
17. Prefer small route IDs when packet size matters.
18. Remember that `NetStream.Compression` now refers to Compression v2.3.2 itself, not the Codec wrapper.

---

# Design Summary

A healthy NetStream v1.3.0 setup usually follows this rule:

```text
Small frequent scalar
    -> Schema + compact numeric type

Current rapidly changing value
    -> State or Event + Coalesce / Latest

Disposable realtime update
    -> Unreliable + Coalesce

Large structured snapshot
    -> Dynamic table + Compression

Need a response
    -> Function / RPC

Latency-sensitive action
    -> Critical / Immediate / Now

High-frequency client route
    -> MaxPerSecond + Burst

Network pressure
    -> Let the governor defer, split, coalesce,
       or drop disposable unreliable work
```

The goal is not simply:

> make every single value as compressed as possible.

The goal is to minimize **total useful networking work**:

- fewer stale updates;
- fewer transport packets;
- smaller encoded payloads;
- bounded queues;
- bounded inbound work;
- controlled outbound bandwidth;
- explicit latency tradeoffs;
- measurable compression;
- measurable transport behavior.

That is where NetStream v1.3.0 is designed to be most useful.
