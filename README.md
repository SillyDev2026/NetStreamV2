# NetStream

![Version](https://img.shields.io/badge/version-v1.0.0-4c8bf5)
![Language](https://img.shields.io/badge/language-Luau-00A2FF)
![Platform](https://img.shields.io/badge/platform-Roblox-111111)
![Protocol](https://img.shields.io/badge/protocol-0x12-6f42c1)

**NetStream** is a compact, high-throughput networking library for Roblox designed for games that need more control than raw `RemoteEvent` / `RemoteFunction` usage.

It provides reliable and unreliable events, request/response calls, replicated state, schema-based encoding, batching, coalescing, queue protection, rate limiting, immediate sends, live traffic statistics, and network-health diagnostics through one ModuleScript.

> Current release: **v1.2.3**
>
> This README targets the **v1.2.3 fixed build**, which includes the client bootstrap timeout fix and the Luau local-register/compiler fix.

---

## Table of Contents

- [Why NetStream?](#why-netstream)
- [Core Features](#core-features)
- [Installation](#installation)
- [Recommended Project Structure](#recommended-project-structure)
- [Five-Minute Quick Start](#five-minute-quick-start)
- [Defining Routes](#defining-routes)
- [Events](#events)
- [Unreliable Events](#unreliable-events)
- [Immediate Sends](#immediate-sends)
- [Coalescing and Latest Updates](#coalescing-and-latest-updates)
- [States](#states)
- [Functions / RPC](#functions--rpc)
- [Schemas](#schemas)
- [Route Options](#route-options)
- [Connections and Listeners](#connections-and-listeners)
- [Rate Limiting](#rate-limiting)
- [Queue Cancellation](#queue-cancellation)
- [Manual Flushing](#manual-flushing)
- [Statistics and Network Health](#statistics-and-network-health)
- [Codec API](#codec-api)
- [Configuration](#configuration)
- [Performance Guide](#performance-guide)
- [Complete Examples](#complete-examples)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)
- [Protocol and Compatibility](#protocol-and-compatibility)
- [Upgrade Checklist](#upgrade-checklist)

---

## Why NetStream?

Roblox remotes are intentionally simple. That is useful, but larger games often need additional behavior around them:

- batching many logical messages into fewer transport sends;
- smaller schema-driven payloads;
- reliable and unreliable traffic in one API;
- "latest value wins" behavior for movement/state;
- queue limits and overload protection;
- RPC timeouts;
- per-route rate limits;
- immediate sends for latency-sensitive actions;
- live byte/message/batch statistics;
- a reusable route layer shared by server and client.

NetStream handles those concerns while keeping the public API close to familiar Roblox networking patterns.

### NetStream is not magic bandwidth removal

NetStream can reduce **application-level encoded bytes** and the number of logical updates that need to be sent, especially when schemas, batching, small route IDs, and coalescing are used correctly.

Roblox still adds its own networking and transport overhead after NetStream sends a buffer.

`NetStream.GetStats().SentBytes` measures the size of **NetStream's encoded buffers**, not the exact final value shown by every Roblox network profiler.

---

# Core Features

| Feature | What it does |
|---|---|
| Events | One-way client/server messages |
| Reliable transport | Uses `RemoteEvent` |
| Unreliable transport | Uses `UnreliableRemoteEvent` when available and appropriate |
| Functions / RPC | Request/response networking with timeouts |
| States | Store the most recently received value for a route |
| Schemas | Encode known data types with less runtime metadata |
| Batching | Combines multiple logical messages before transport |
| Schema runs | Compresses consecutive messages using the same schema route |
| Coalescing | Replaces stale queued values with the newest value |
| Immediate sends | Bypasses the normal wait for the next scheduled flush |
| Queue protection | Caps reliable/unreliable queue growth |
| Route rate limiting | Token-bucket style inbound protection |
| Global rate limiting | Protects the server from excessive aggregate traffic |
| Cancellation | Remove queued or latest updates before they are sent |
| Monitoring | Bytes/sec, messages/sec, batches/sec, queues, backlog and health |
| Dynamic codec | Standalone buffer encoder/decoder |
| No dependencies | One ModuleScript |

---

# Installation

## 1. Add the ModuleScript

Place the v1.2.3 fixed module in `ReplicatedStorage` and name it:

```text
ReplicatedStorage
└── NetStream
```

The module must be available to both the server and clients.

## 2. Start NetStream on the server

Create a normal **Script** in `ServerScriptService`.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetStream = require(ReplicatedStorage.NetStream)

NetStream.Start()

print("NetStream", NetStream.Version, "started")
```

Starting NetStream early on the server creates the internal remotes before clients attempt to connect.

## 3. Define the same routes on both sides

The server and client must agree on:

- route type;
- route ID;
- schema;
- important route behavior.

The easiest way to guarantee this is to put route definitions in one shared ModuleScript.

---

# Recommended Project Structure

```text
ReplicatedStorage
├── NetStream
└── NetworkRoutes

ServerScriptService
└── NetworkServer

StarterPlayer
└── StarterPlayerScripts
    └── NetworkClient
```

### `ReplicatedStorage/NetworkRoutes`

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetStream = require(ReplicatedStorage.NetStream)
local T = NetStream.Types

return NetStream.DefineCompact({
	Damage = {
		Type = "Event",
		Schema = { T.U16 },
	},

	Movement = {
		Type = "Event",
		Schema = { T.Vector3Q(100) },
		Unreliable = true,
		Coalesce = true,
		MaxPerSecond = 120,
		Burst = 30,
	},

	Health = {
		Type = "State",
		Schema = T.U16,
		Coalesce = true,
	},

	GetProfile = {
		Type = "Function",
		Schema = {},
	},
})
```

### Server bootstrap

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetStream = require(ReplicatedStorage.NetStream)

NetStream.Start()

local Routes = require(ReplicatedStorage.NetworkRoutes)

print("Network ready")
```

### Client bootstrap

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Routes = require(ReplicatedStorage.NetworkRoutes)

print("Client routes ready")
```

---

# Five-Minute Quick Start

## Client -> Server event

### Shared route

```lua
local Test = NetStream.Event("Test", {
	Id = 1,
	Schema = {
		NetStream.Types.String,
	},
})
```

### Client

```lua
Test:FireServer("Hello from the client")
```

### Server

```lua
Test:Connect(function(player, message)
	print(player.Name, message)
end)
```

Server event listeners receive the `Player` first.

Client event listeners do not.

---

# Defining Routes

There are three main route types:

```lua
NetStream.Event(...)
NetStream.State(...)
NetStream.Function(...)
```

You can create each route directly, or define a group.

## Direct definitions

```lua
local Message = NetStream.Event("Message", {
	Id = 1,
	Schema = {
		NetStream.Types.String,
	},
})

local Health = NetStream.State("Health", {
	Id = 1,
	Schema = NetStream.Types.U16,
})

local GetData = NetStream.Function("GetData", {
	Id = 1,
	Schema = {},
})
```

Event IDs, State IDs and Function IDs are stored in separate route groups, so each group can use compact IDs independently.

---

## `Define`

```lua
local Routes = NetStream.Define({
	Message = {
		Type = "Event",
		Id = 1,
		Schema = { NetStream.Types.String },
	},

	Health = {
		Type = "State",
		Id = 1,
		Schema = NetStream.Types.U16,
	},

	GetData = {
		Type = "Function",
		Id = 1,
		Schema = {},
	},
})
```

---

## `DefineCompact` — recommended

For most production projects, prefer:

```lua
local Routes = NetStream.DefineCompact({
	Message = {
		Type = "Event",
		Schema = { NetStream.Types.String },
	},

	Health = {
		Type = "State",
		Schema = NetStream.Types.U16,
	},

	GetData = {
		Type = "Function",
		Schema = {},
	},
})
```

`DefineCompact()` deterministically assigns small numeric IDs by sorting route names within each route type.

Small route IDs are useful because NetStream encodes IDs as varints. IDs in the small range generally require fewer bytes than large hashed IDs.

### Important

Use the **same shared definition table** on server and client.

If the server and client define different sets of compact routes, their automatically assigned IDs can differ.

---

# Events

Events are one-way messages.

## Client -> Server

```lua
local Shoot = Routes.Shoot

Shoot:FireServer(weaponId)
```

Server:

```lua
Shoot:Connect(function(player, weaponId)
	print(player.Name, "fired", weaponId)
end)
```

## Server -> One Client

```lua
Routes.Notification:FireClient(player, "Welcome!")
```

Client:

```lua
Routes.Notification:Connect(function(message)
	print(message)
end)
```

## Server -> All Clients

```lua
Routes.RoundStarted:FireAll(roundNumber)
```

## Server -> Everyone Except One Player

```lua
Routes.Effect:FireAllExcept(player, effectId)
```

---

# Unreliable Events

Use unreliable networking for information where a newer update makes an older update irrelevant.

Good examples:

- movement snapshots;
- aim direction;
- camera information;
- temporary visual effects;
- frequently refreshed world state.

Create an unreliable route:

```lua
local Movement = NetStream.Unreliable("Movement", {
	Id = 1,
	Schema = {
		NetStream.Types.Vector3Q(100),
	},
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

Then use the normal event API:

```lua
Movement:FireServer(position)
```

You can also force unreliable transport from a normal Event route:

```lua
Movement:FireUnreliableServer(position)
```

Server methods include:

```lua
Movement:FireUnreliableClient(player, position)
Movement:FireUnreliableAll(position)
```

### Oversized unreliable packets

NetStream uses `UnreliableRemoteEvent` only when the encoded packet is within the configured unreliable size limit.

The default is:

```lua
UnreliableMaxBytes = 900
```

If unreliable transport cannot safely be used, NetStream can fall back to the reliable remote and records that in `FallbackReliable`.

---

# Immediate Sends

Normal NetStream messages are queued and flushed by the scheduler so they can benefit from batching.

That is good for bandwidth and throughput.

Some actions care more about latency than batching:

- parry/block input;
- weapon fire;
- interaction requests;
- small urgent UI/gameplay messages;
- latency tests.

Use a `Now` method:

```lua
Parry:FireServerNow()
```

Aliases ending in `Immediate` are also available:

```lua
Parry:FireServerImmediate()
```

Server:

```lua
Event:FireClientNow(player, ...)
Event:FireAllNow(...)
Event:FireAllExceptNow(player, ...)
```

RPC:

```lua
FunctionRoute:InvokeServerNow(...)
FunctionRoute:InvokeClientNow(player, ...)
```

State:

```lua
StateRoute:SetServerNow(value)
StateRoute:SetClientNow(player, value)
StateRoute:SetAllNow(value)
```

You can also make a route immediate by default:

```lua
local Parry = NetStream.Event("Parry", {
	Id = 2,
	Schema = {},
	Immediate = true,
})
```

## Do not make everything Immediate

Immediate sends reduce the opportunity for NetStream to combine messages.

Use:

```text
Batched
```

for most traffic.

Use:

```text
Immediate
```

only for routes where latency matters more than packet count.

---

# Coalescing and Latest Updates

High-frequency state often does not need every intermediate value.

Imagine a movement system producing:

```text
Position A
Position B
Position C
Position D
```

before the next network flush.

If only `Position D` matters, sending all four is wasted work.

Enable coalescing:

```lua
local Movement = NetStream.Event("Movement", {
	Id = 1,
	Schema = {
		NetStream.Types.Vector3Q(100),
	},
	Unreliable = true,
	Coalesce = true,
})
```

Then normal sends:

```lua
Movement:FireServer(position)
```

replace an older unsent coalesced value with the newest one.

Aliases are accepted in definitions:

```lua
Coalesce = true
Latest = true
Mode = "Latest"
```

## Explicit Latest API

Events:

```lua
Movement:LatestServer(position)
Movement:LatestClient(player, position)
Movement:LatestAll(position)
```

States:

```lua
Position:SetLatestServer(position)
Position:SetLatestClient(player, position)
Position:SetLatestAll(position)
```

Latest sends use unreliable + coalesced behavior.

---

# States

A State route represents the most recently received value for that route.

State schemas contain **exactly one NetStream type**.

```lua
local Health = NetStream.State("Health", {
	Id = 1,
	Schema = NetStream.Types.U16,
})
```

## Server -> Client

Server:

```lua
Health:SetClient(player, 100)
```

Client:

```lua
Health:Connect(function(value)
	print("Health updated:", value)
end)
```

Read the latest received value:

```lua
local current = Health:Get()
```

## Server -> All Clients

```lua
Health:SetAll(100)
```

## Client -> Server

Client:

```lua
Health:SetServer(95)
```

Server:

```lua
Health:Connect(function(player, value)
	print(player.Name, value)
end)
```

Server can read the latest value received from a player:

```lua
local value = Health:Get(player)
```

## Latest state replication

For state that changes rapidly:

```lua
Position:SetLatestServer(position)
```

or define it once:

```lua
local Position = NetStream.State("Position", {
	Schema = NetStream.Types.Vector3Q(100),
	Coalesce = true,
})
```

---

# Functions / RPC

Functions provide request/response networking.

They are useful when the caller actually needs a result.

Avoid RPC for fire-and-forget messages.

## Client -> Server RPC

Shared definition:

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

## RPC with arguments

```lua
local BuyItem = NetStream.Function("BuyItem", {
	Id = 2,
	Schema = {
		NetStream.Types.U16,
	},
})
```

Server:

```lua
BuyItem:SetCallback(function(player, itemId)
	if itemId == 10 then
		return true, "Purchased"
	end

	return false, "Unknown item"
end)
```

Client:

```lua
local success, message = BuyItem:InvokeServer(10)

print(success, message)
```

## Server -> Client RPC

Client:

```lua
ConfirmAction:SetCallback(function(actionId)
	return true
end)
```

Server:

```lua
local confirmed = ConfirmAction:InvokeClient(player, actionId)
```

## RPC timeout

RPC requests automatically time out.

Default:

```lua
CallTimeout = 8
```

Do not use RPC every frame.

Prefer Events or States for high-frequency networking.

---

# Schemas

Schemas tell NetStream exactly what data a route carries.

That removes much of the dynamic type metadata that would otherwise be needed for each value.

```lua
local Damage = NetStream.Event("Damage", {
	Id = 1,
	Schema = {
		NetStream.Types.U16,
	},
})
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
| `T.F32` | 32-bit floating point |
| `T.F64` | 64-bit floating point |
| `T.String` | String |
| `T.Buffer` | Roblox buffer |
| `T.Color3` | RGB color |
| `T.Vector2Q(precision)` | Quantized Vector2 |
| `T.Vector3Q(precision)` | Quantized Vector3 |
| `T.CFrameQ(precision)` | Quantized CFrame position + quaternion rotation |

Example:

```lua
local T = NetStream.Types

local Hit = NetStream.Event("Hit", {
	Id = 1,
	Schema = {
		T.U16,
		T.Vector3Q(100),
		T.U16,
	},
})
```

Usage:

```lua
Hit:FireServer(
	targetId,
	hitPosition,
	damage
)
```

---

## Choosing integer types

If a value is always:

```text
0 - 255
```

use:

```lua
T.U8
```

If it is:

```text
0 - 65,535
```

use:

```lua
T.U16
```

For values with a large maximum but usually small values:

```lua
T.VarUInt
```

can be useful.

---

## Quantized vectors

```lua
T.Vector3Q(100)
```

means components are quantized at a precision of 100 units per stud.

Examples:

```text
1.00
1.01
1.02
```

can be represented using integer-style encoding internally.

Higher precision preserves more decimal detail but can produce larger varints for large coordinates.

Pick precision based on what the gameplay actually needs.

---

## CFrame schema

```lua
T.CFrameQ(100)
```

encodes:

- quantized X/Y/Z position;
- quaternion rotation using four signed 16-bit values.

This is significantly more purpose-built than sending a fully dynamic CFrame representation.

---

## Dynamic routes

Schemas are recommended for hot routes, but they are optional.

Without a schema, NetStream's dynamic codec supports values including:

- `nil`;
- booleans;
- numbers;
- strings;
- `Vector2`;
- `Vector3`;
- `CFrame`;
- `Color3`;
- buffers;
- arrays;
- maps/tables.

Example:

```lua
local DebugMessage = NetStream.Event("DebugMessage")

DebugMessage:FireServer({
	Action = "Test",
	Value = 123,
	Enabled = true,
})
```

Use dynamic routes for flexible or infrequent traffic.

Use schemas for hot paths.

---

# Route Options

## Event options

| Option | Purpose |
|---|---|
| `Id` | Explicit numeric route ID |
| `Schema` | Schema for event arguments |
| `Unreliable` | Prefer unreliable transport |
| `Trusted` | Skip normal outgoing schema value checks |
| `Immediate` | Flush after normal route sends |
| `Coalesce` | Keep only the newest unsent route value |
| `Latest` | Alias for coalescing |
| `Mode = "Latest"` | Alias for coalescing |
| `MaxPerSecond` | Server-side inbound per-player route rate |
| `Burst` | Burst capacity for route rate limiting |

## State options

States support:

```text
Id
Schema
Trusted
Immediate
Coalesce
Latest
Mode
MaxPerSecond
Burst
```

State schemas must contain exactly one type.

## Function options

Functions support:

```text
Id
Schema
Trusted
Immediate
```

---

## About `Trusted`

```lua
Trusted = true
```

skips normal schema value validation performed before sending.

It is intended for carefully controlled hot paths where the code producing values is already known to be correct.

Do **not** interpret `Trusted = true` as:

> trust data coming from a Roblox client.

The server must still validate gameplay rules, ownership, permissions, cooldowns and any value that could be exploited.

When in doubt, leave `Trusted` off.

---

# Connections and Listeners

Event and State routes use connection-style listeners.

## Connect

```lua
local connection = Route:Connect(function(...)
	print(...)
end)
```

## Disconnect

```lua
connection:Disconnect()
```

## Check connection

```lua
print(connection:IsConnected())
```

## Once

```lua
Route:Once(function(...)
	print("Runs once")
end)
```

## Wait

```lua
local value, err = Route:Wait(5)

if value == nil and err then
	warn(err)
end
```

## Disconnect every listener

```lua
Route:DisconnectAll()
```

## Listener diagnostics

```lua
print(Route:ListenerCount())
print(Route:GetListenerCount())
print(Route:HasListeners())
```

## Route information

```lua
print(Route:GetName())
print(Route:GetId())
print(Route:IsCoalescing())
```

---

# Rate Limiting

NetStream has global traffic protections in its configuration and also supports **per-route inbound limits**.

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

The server tracks the allowance per player for that route.

Conceptually:

```text
20 messages/sec sustained
5-message burst capacity
```

This is useful for client-originated hot routes.

Examples:

```text
Shoot          20/sec
Interaction    15/sec
Movement      120/sec
Input         120/sec
```

These numbers are examples, not universal recommendations. Set limits around your actual game design.

Check how many route messages were limited:

```lua
local stats = NetStream.GetStats()

print(stats.RouteRateLimited)
```

---

# Queue Cancellation

Stopping a loop does not automatically erase data that has already been queued.

v1.2.3 provides cancellation APIs for this.

## Cancel all unsent messages for an Event route

Client:

```lua
Movement:CancelQueuedServer()
```

Server:

```lua
Movement:CancelQueuedClient(player)
Movement:CancelQueuedAll()
```

## Cancel only the current Latest value

Client:

```lua
Movement:CancelLatestServer()
```

Server:

```lua
Movement:CancelLatestClient(player)
Movement:CancelLatestAll()
```

States provide equivalent cancellation APIs.

### Heartbeat example

```lua
local RunService = game:GetService("RunService")

local connection

connection = RunService.Heartbeat:Connect(function()
	Movement:FireServer(position)
end)

-- Later
connection:Disconnect()

Movement:CancelQueuedServer()
```

This stops creating new movement events and removes unsent Movement messages still inside NetStream's queue.

Messages that were already handed to Roblox networking may still arrive.

---

# Manual Flushing

Most games should let the scheduler flush automatically.

For testing or special cases:

```lua
local bytes, batches, messages = NetStream.Flush()

print(bytes, batches, messages)
```

Alias:

```lua
NetStream.FlushNow()
```

Flush one player's bucket on the server:

```lua
NetStream.FlushTarget(player)
```

Flush the broadcast bucket:

```lua
NetStream.FlushTarget()
```

On the client:

```lua
NetStream.FlushTarget()
```

flushes the client's outgoing bucket.

---

# Statistics and Network Health

NetStream exposes detailed internal statistics.

## Basic stats

```lua
local stats = NetStream.GetStats()

print("Sent bytes:", stats.SentBytes)
print("Received bytes:", stats.ReceivedBytes)

print("Sent messages:", stats.SentMessages)
print("Received messages:", stats.ReceivedMessages)

print("Sent batches:", stats.SentBatches)
print("Received batches:", stats.ReceivedBatches)
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

QueuedReliable
QueuedUnreliable
PendingCalls
DispatchBacklog
ActiveTargetBacklog

AverageBatchBytes
AverageMessagesPerBatch

MessagePoolSize
ArgsPoolSize
WriterPoolSize
ReaderPoolSize
BatchPoolSize
```

---

## Live rate statistics

```lua
local rates = NetStream.GetRateStats()

print(rates.SentBytesPerSecond)
print(rates.ReceivedBytesPerSecond)

print(rates.SentMessagesPerSecond)
print(rates.ReceivedMessagesPerSecond)

print(rates.SentBatchesPerSecond)
print(rates.ReceivedBatchesPerSecond)
```

Format bytes:

```lua
print(
	NetStream.FormatBytes(
		rates.SentBytesPerSecond
	)
)
```

Example:

```text
1.42 KB
```

---

## Health API

```lua
local health = NetStream.GetHealth()

print(health.Status)
print(health.QueuedMessages)
print(health.DispatchBacklog)
print(health.ActiveTargetBacklog)
```

Possible status values:

```text
Healthy
Busy
Congested
Overloaded
```

The health result also includes:

```text
SentBytesPerSecond
ReceivedBytesPerSecond
SentMessagesPerSecond
ReceivedMessagesPerSecond
```

This is intended as a quick operational signal, not a replacement for Roblox's own network profiler.

---

## Last encoded packet size

```lua
print(NetStream.GetLastPacketBytes())
```

This reports the last encoded packet sent by NetStream.

Again, it is **not the full Roblox transport cost**.

---

## Reset statistics

```lua
NetStream.ResetStats()
```

---

# Codec API

NetStream exposes its dynamic buffer codec separately.

```lua
local Codec = NetStream.Codec
```

Encode:

```lua
local data = Codec.Encode(
	123,
	true,
	"Hello",
	Vector3.new(1, 2, 3)
)
```

Decode:

```lua
local numberValue, boolValue, text, position =
	Codec.Decode(data)
```

Get encoded byte length:

```lua
local bytes = Codec.ByteLength(
	123,
	true,
	"Hello"
)

print(bytes)
```

`NetStream.Compression` is an alias of `NetStream.Codec`.

---

# Configuration

Configuration must happen **before** the first route is created and before `NetStream.Start()`.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetStream = require(ReplicatedStorage.NetStream)

NetStream.Configure({
	FlushRate = 60,
	Debug = false,
})

NetStream.Start()
```

Read the current configuration:

```lua
local config = NetStream.GetConfig()
```

---

## Important configuration defaults

| Setting | Default | Purpose |
|---|---:|---|
| `Namespace` | `"NetStream"` | Internal remote namespace |
| `RemoteWaitTimeout` | `10` | Client wait timeout for server remotes |
| `FlushRate` | `60` | Scheduled flush frequency |
| `MaxBatchMessages` | `256` | Maximum logical messages gathered per batch |
| `MaxOutgoingBatchBytes` | `2 MiB` | Maximum encoded outgoing batch target |
| `MaxIncomingPacketBytes` | `2 MiB` | Reject packets larger than this |
| `MaxBatchesPerFlush` | `4` | Batch work allowed per channel flush |
| `MaxDispatchPerCycle` | `2048` | Maximum callback dispatch count per cycle |
| `MaxDispatchBacklog` | `16384` | Maximum queued dispatch work |
| `DispatchBudgetSeconds` | `0.0025` | Dispatch CPU budget |
| `FlushBudgetSeconds` | `0.003` | Scheduled flush CPU budget |
| `ImmediateFlushBudgetSeconds` | `0.004` | Immediate flush CPU budget |
| `TimeoutSweepInterval` | `0.25` | RPC timeout scan interval |
| `MaxTargetsPerFlush` | `128` | Server target processing cap per flush |
| `MaxIncomingMessagesPerSecond` | `30000` | Per-player message envelope protection |
| `MaxIncomingBytesPerSecond` | `2 MiB` | Per-player byte protection |
| `MaxIncomingBatchesPerSecond` | `240` | Per-player batch protection |
| `MaxGlobalIncomingMessagesPerSecond` | `120000` | Global message protection |
| `MaxGlobalIncomingBytesPerSecond` | `8 MiB` | Global incoming byte protection |
| `MaxGlobalIncomingBatchesPerSecond` | `8192` | Global incoming batch protection |
| `MaxIncomingCallsPerSecond` | `240` | Per-player RPC protection |
| `MaxGlobalIncomingCallsPerSecond` | `4096` | Global RPC protection |
| `MaxReliableQueue` | `8192` | Maximum reliable queued messages |
| `MaxUnreliableQueue` | `2048` | Maximum unreliable queued messages |
| `UnreliableMaxBytes` | `900` | Maximum encoded size used for unreliable send |
| `CallTimeout` | `8` | RPC timeout in seconds |
| `VectorPrecision` | `100` | Dynamic Vector/CFrame quantization precision |
| `MaxIncomingMessages` | `512` | Maximum messages declared by one batch |
| `MaxStringBytes` | `1 MiB` | Maximum string size |
| `MaxBufferBytes` | `1 MiB` | Maximum buffer size |
| `MaxTableEntries` | `8192` | Maximum dynamic table entries |
| `MaxDepth` | `32` | Maximum dynamic table recursion depth |
| `Debug` | `false` | Extra NetStream warnings |

### Do not blindly increase limits

Higher limits are not always better.

Queue, packet and rate limits exist to keep one player or one burst from consuming unlimited memory/CPU/network work.

Change them only after profiling your game.

---

# Performance Guide

NetStream performs best when the route design matches the data.

## 1. Prefer `DefineCompact`

```lua
NetStream.DefineCompact(...)
```

Small IDs reduce route-ID encoding overhead.

---

## 2. Use schemas on hot routes

Prefer:

```lua
Schema = {
	T.U16,
	T.Vector3Q(100),
}
```

over sending a dynamic table every frame.

Dynamic values are useful, but they need type metadata.

---

## 3. Coalesce rapidly changing state

Bad for movement:

```lua
for _ = 1, 100 do
	Movement:FireServer(position)
end
```

if every intermediate update is useless.

Better:

```lua
Movement = {
	Type = "Event",
	Unreliable = true,
	Coalesce = true,
	Schema = {
		T.Vector3Q(100),
	},
}
```

Now stale unsent values can be replaced before serialization.

---

## 4. Use unreliable transport for disposable updates

Use unreliable networking when losing an old update is acceptable.

Good:

```text
movement
aim
temporary effects
frequent snapshots
```

Usually not good:

```text
purchase
inventory mutation
reward
save confirmation
critical match result
```

---

## 5. Keep Immediate routes rare

This:

```lua
FireServerNow(...)
```

reduces queue latency.

It also reduces batching opportunity.

If 50 players send many Immediate messages continuously, you can create more transport work than necessary.

---

## 6. Do not RPC every frame

RPC yields until a response or timeout.

For high-frequency data, use Events or States.

---

## 7. Rate-limit client hot paths

```lua
MaxPerSecond = 120,
Burst = 30,
```

is far safer than leaving a high-frequency route completely unbounded.

The rate limit should still be paired with gameplay validation.

---

## 8. Watch queues and dispatch backlog

```lua
local health = NetStream.GetHealth()

if health.Status ~= "Healthy" then
	warn(
		"Network:",
		health.Status,
		health.QueuedMessages,
		health.DispatchBacklog
	)
end
```

A growing queue means producers are generating work faster than NetStream can flush it under the configured budgets.

---

## 9. Measure the right number

For NetStream's own encoded buffers:

```lua
NetStream.GetStats().SentBytes
```

For total Roblox networking:

use Roblox's network/debug/profiler tools as well.

These numbers measure different layers.

---

# Complete Examples

## Example 1 — Clicker

### Shared routes

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

	GetCoins = {
		Type = "Function",
		Schema = {},
	},
})
```

### Server

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetStream = require(ReplicatedStorage.NetStream)

NetStream.Start()

local Routes = require(ReplicatedStorage.NetworkRoutes)

local coins = {}

Players.PlayerAdded:Connect(function(player)
	coins[player] = 0

	Routes.Coins:SetClient(
		player,
		coins[player]
	)
end)

Players.PlayerRemoving:Connect(function(player)
	coins[player] = nil
end)

Routes.Click:Connect(function(player)
	local current = coins[player]

	if current == nil then
		return
	end

	current += 1
	coins[player] = current

	Routes.Coins:SetClient(
		player,
		current
	)
end)

Routes.GetCoins:SetCallback(function(player)
	return coins[player] or 0
end)
```

### Client

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Routes = require(ReplicatedStorage.NetworkRoutes)

Routes.Coins:Connect(function(coins)
	print("Coins:", coins)
end)

script.Parent.Activated:Connect(function()
	Routes.Click:FireServer()
end)

local coins = Routes.GetCoins:InvokeServer()

print("Initial coins:", coins)
```

---

## Example 2 — Movement

### Shared route

```lua
Movement = {
	Type = "Event",

	Schema = {
		T.Vector3Q(100),
	},

	Unreliable = true,
	Coalesce = true,

	MaxPerSecond = 120,
	Burst = 30,
}
```

### Client

```lua
local RunService = game:GetService("RunService")

local connection

connection = RunService.Heartbeat:Connect(function()
	local character = game.Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if root then
		Routes.Movement:FireServer(root.Position)
	end
end)
```

### Server

```lua
Routes.Movement:Connect(function(player, position)
	-- Validate before using client-controlled movement data.
	print(player.Name, position)
end)
```

### Stop replication cleanly

```lua
connection:Disconnect()

Routes.Movement:CancelQueuedServer()
```

---

## Example 3 — Low-Latency Action

```lua
local Parry = NetStream.Event("Parry", {
	Id = 3,
	Schema = {},
	Immediate = true,
	MaxPerSecond = 15,
	Burst = 4,
})
```

Client:

```lua
Parry:FireServer()
```

Because the route is `Immediate`, the normal send triggers an immediate target flush.

You can also leave the route batched and call:

```lua
Parry:FireServerNow()
```

only when needed.

---

## Example 4 — Damage Event

```lua
local Damage = NetStream.Event("Damage", {
	Id = 4,

	Schema = {
		NetStream.Types.U16,
		NetStream.Types.U16,
	},
})
```

Client:

```lua
Damage:FireServer(
	targetId,
	requestedDamage
)
```

Server:

```lua
Damage:Connect(function(player, targetId, requestedDamage)
	-- Do not trust requestedDamage just because it matched U16.
	-- Validate the weapon, target, distance, cooldown and real damage server-side.
end)
```

---

## Example 5 — Network Monitor

```lua
task.spawn(function()
	while true do
		task.wait(1)

		local rates = NetStream.GetRateStats()
		local health = NetStream.GetHealth()
		local stats = NetStream.GetStats()

		print("------ NetStream ------")
		print("Health:", health.Status)

		print(
			"TX:",
			NetStream.FormatBytes(
				rates.SentBytesPerSecond
			) .. "/s"
		)

		print(
			"RX:",
			NetStream.FormatBytes(
				rates.ReceivedBytesPerSecond
			) .. "/s"
		)

		print(
			"Queued:",
			health.QueuedMessages
		)

		print(
			"Dispatch backlog:",
			health.DispatchBacklog
		)

		print(
			"Route limited:",
			stats.RouteRateLimited
		)
	end
end)
```

---

# Security

NetStream protects the networking layer.

It does **not** replace server-authoritative game logic.

A schema can prove:

```text
"this value is a U16"
```

It cannot prove:

```text
"this player is allowed to deal 500 damage"
```

Always validate important actions on the server.

## Validate

- ownership;
- permissions;
- cooldowns;
- distance;
- inventory;
- currency;
- item IDs;
- state transitions;
- damage;
- target existence;
- request frequency;
- any client-provided position used for authoritative gameplay.

## Do not use `Trusted = true` on arbitrary client data

`Trusted` is a performance option for controlled values, not a security flag.

---

# Troubleshooting

## Client waits for `__NetStream_NetStream`

Make sure a normal server Script requires NetStream and starts it:

```lua
local NetStream = require(ReplicatedStorage.NetStream)

NetStream.Start()
```

Recommended location:

```text
ServerScriptService
```

The fixed v1.2.3 build uses a client remote wait timeout instead of waiting forever.

---

## `Out of local registers ... exceeded limit 200`

Use the **v1.2.3 fixed build**.

Earlier v1.2.3 builds grew beyond Luau's module-scope local-register limit.

The fixed build restructures cold internal helpers so the module loads below that compiler limit while keeping the public API intact.

---

## Server and client report schema mismatch

Make sure both sides define exactly the same route schema.

Best practice:

```text
ReplicatedStorage
└── NetworkRoutes
```

and require the same route module from both server and client.

---

## `DefineCompact` routes do not match

Both sides must use the same set of route names/types.

Do not independently remove one compact route from only the client or only the server.

---

## Event callback is not firing

Check:

1. server NetStream started;
2. both sides use the same route;
3. route IDs match;
4. schemas match;
5. the server listener includes `player` as the first callback parameter;
6. the message was not rate limited;
7. the route was not cancelled before flush.

Inspect:

```lua
print(NetStream.GetStats())
```

and:

```lua
print(NetStream.GetHealth())
```

---

## RTT is higher than raw RemoteEvent

Normal NetStream sends are batched.

That can intentionally add queue time in exchange for fewer sends and better throughput.

For a latency-sensitive route, test:

```lua
Route:FireServerNow(...)
```

and on the server:

```lua
Route:FireClientNow(player, ...)
```

Do not judge batching CPU cost purely from an RTT number. Waiting for a scheduled flush is not the same thing as the serializer consuming that entire time on the CPU.

---

## `SentBytes` does not match Studio Data Send

Expected.

NetStream reports its **encoded buffer bytes**.

Roblox networking adds additional transport/protocol overhead after that.

Use both sets of measurements when profiling.

---

## Unreliable traffic appears reliable

NetStream can fall back to the reliable remote when:

- `UnreliableRemoteEvent` is unavailable;
- the encoded packet is larger than `UnreliableMaxBytes`;
- an unreliable send fails and fallback succeeds.

Check:

```lua
NetStream.GetStats().FallbackReliable
```

---

## A message arrives after a Heartbeat loop was stopped

Disconnecting `RunService.Heartbeat` prevents new sends.

It does not pull packets back out of Roblox's networking layer after they have already been sent.

To remove messages still queued inside NetStream:

```lua
Route:CancelQueuedServer()
```

A small number of already-in-flight responses can still arrive.

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
NetStream.GetHealth()

NetStream.GetLastPacketBytes()
NetStream.ResetStats()
NetStream.FormatBytes(bytes)

NetStream.Float32(value)
NetStream.RawString(value)

NetStream.Destroy()
```

---

## EventRoute

### Listeners

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
Event:IsCoalescing()
```

### Client sends

```lua
Event:FireServer(...)
Event:FireServerNow(...)
Event:FireServerImmediate(...)

Event:FireUnreliableServer(...)

Event:LatestServer(...)

Event:CancelLatestServer()
Event:CancelQueuedServer()
```

### Server sends

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

---

## StateRoute

### Listeners

State routes use the same listener API as Events.

### Client

```lua
State:SetServer(value, unreliable?)
State:SetServerNow(value, unreliable?)
State:SetServerImmediate(value, unreliable?)

State:SetLatestServer(value)

State:CancelLatestServer()
State:CancelQueuedServer()

State:Get()
```

### Server

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

---

## FunctionRoute

```lua
Function:SetCallback(callback)
Function:OnInvoke(callback)
Function:Bind(callback)

Function:InvokeServer(...)
Function:InvokeServerNow(...)
Function:InvokeServerImmediate(...)

Function:InvokeClient(player, ...)
Function:InvokeClientNow(player, ...)
Function:InvokeClientImmediate(player, ...)
```

Server callbacks receive the player first:

```lua
Function:SetCallback(function(player, ...)
	return ...
end)
```

Client callbacks receive only the declared arguments:

```lua
Function:SetCallback(function(...)
	return ...
end)
```

---

## Codec

```lua
NetStream.Codec.Encode(...)
NetStream.Codec.Decode(buffer)
NetStream.Codec.ByteLength(...)
```

Alias:

```lua
NetStream.Compression
```

---

# Protocol and Compatibility

v1.2.3 uses:

```text
Protocol: 0x12
```

For normal production use, run the **same NetStream version** on the server and client.

Even when two releases share a protocol number, keeping both sides on the same module version avoids differences in validation, route behavior, bug fixes and diagnostics.

---

# Upgrade Checklist

When replacing an older NetStream build:

1. Replace the `ReplicatedStorage.NetStream` ModuleScript.
2. Confirm the server calls `NetStream.Start()` early.
3. Keep server/client route definitions identical.
4. Prefer a shared `NetworkRoutes` ModuleScript.
5. If using `DefineCompact`, make sure both sides define the same route set.
6. Re-test schema routes.
7. Re-test unreliable traffic.
8. Re-test RPC callbacks.
9. Re-test Heartbeat/high-frequency routes.
10. Check `GetHealth()` while stress testing.
11. Check `GetRateStats()` for sustained bandwidth.
12. Check Roblox's own network profiler as well.
13. Use `CancelQueued...()` when stopping hot replication loops.
14. Keep `Immediate` limited to genuinely latency-sensitive routes.

---

# Design Summary

A healthy NetStream setup normally looks like this:

```text
Gameplay Code
     │
     ▼
  NetStream Route
     │
     ├── Validation / Schema
     │
     ├── Optional Rate Limit
     │
     ├── Optional Coalescing
     │
     ▼
 Queue / Latest Slot
     │
     ├── Immediate ──────────────┐
     │                           │
     └── Scheduled Batching      │
                 │               │
                 ▼               ▼
          Schema / Dynamic Encoding
                 │
                 ▼
        Reliable / Unreliable Remote
                 │
                 ▼
             Roblox Network
```

The goal is not simply to make every individual send as immediate as possible.

The goal is to keep networking **predictable under real game load**:

- small data where practical;
- fewer stale updates;
- bounded queues;
- bounded server work;
- explicit latency tradeoffs;
- observable traffic;
- reusable route definitions.

---

## Recommended Production Pattern

If you only remember one setup from this README, use this:

```lua
local Routes = NetStream.DefineCompact({
	Movement = {
		Type = "Event",
		Schema = {
			T.Vector3Q(100),
		},
		Unreliable = true,
		Coalesce = true,
		MaxPerSecond = 120,
		Burst = 30,
	},

	Damage = {
		Type = "Event",
		Schema = {
			T.U16,
			T.U16,
		},
	},

	Health = {
		Type = "State",
		Schema = T.U16,
		Coalesce = true,
	},

	GetProfile = {
		Type = "Function",
		Schema = {},
	},
})
```

Then choose behavior based on the data:

```text
Critical discrete event     -> Reliable Event
Disposable frequent update  -> Unreliable + Coalesce
Current replicated value    -> State
Need an actual response      -> Function
Latency-sensitive action     -> Immediate / Now
High-frequency client route  -> MaxPerSecond + Burst
```

That combination is where NetStream is intended to be most useful.
