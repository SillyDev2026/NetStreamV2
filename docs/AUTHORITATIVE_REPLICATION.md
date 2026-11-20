# Server-Authoritative Replication — v4.4 Feature Preview

> **Status:** Experimental, opt-in feature integrated into the v4.3.1-compatible source line. The installed NetStream module still reports **v4.3.1** until real Roblox Studio multiplayer validation supports a numbered v4.4 release.

[← Documentation index](README.md) · [Server security](SECURITY.md) · [Runtime validation](RUNTIME_VALIDATION.md)

`NetStream.CreateReplica` owns a separate server state for each attached player and replicates it only to that player. Clients submit commands; registered server validators and reducers decide whether to change state. The API is cheat-resistant infrastructure, not a guarantee that an entire game is uncheatable.

## Install

Keep `Compression` as a child ModuleScript of `Netstream`. Add `AuthoritativeState.lua` as another child ModuleScript named **AuthoritativeState**. It is loaded lazily by `CreateReplica`; existing networking code does not require the new child. Server and client must use matching current branch source, IDs and ordered field lists.

Four consecutive event IDs starting at `Id` are reserved for data, control, commands and results. Names/IDs cannot be reused in the same NetStream lifetime, even after a controller is destroyed. At most 128 controllers may be created per NetStream instance. Reserve ID blocks explicitly to avoid collisions with existing routes.

## Server and client

On both sides, create the same controller:

```luau
local Account = NetStream.CreateReplica("Account", {Id = 46000, Fields = {"Coins", "Level"}})
```

On the **server**, after the player's profile has loaded:

```luau
Account:Attach(player, {Coins = 100, Level = 0})
Account:HandleCommand("BuyUpgrade", {
    Rate = 3,
    Burst = 2,
    Validate = function(player, payload, state)
        for key in pairs(payload) do if key ~= "UpgradeId" then return false end end
        return payload.UpgradeId == 1 and state.Level < 10 and state.Coins >= 10
    end,
    Reduce = function(player, payload, draft)
        draft.Coins -= 10
        draft.Level += 1
        return draft
    end,
})
```

The starting balance above is for illustration. The server determines the price, limit and starting state. Real gameplay should also validate permissions, ownership, cooldowns, progression, proximity or other requirements appropriate to that command.

On the **client**:

```luau
Account:OnChanged(function(state, revision)
    if state then print(state.Coins, state.Level, revision) end
end)
Account:OnCommandResult(function(sequence, accepted, reason)
    print(sequence, accepted, reason)
end)
local queued, sequenceOrReason = Account:SendCommand("BuyUpgrade", {UpgradeId = 1})
```

Call `SendCommand` from a UI action only when `Account:Get()` is non-nil. A true return means queued locally, not approved by the server. An `Accepted` result means the server committed the new replica state; the corresponding state snapshot may arrive later. Queue/rate rejection or disconnect can prevent a result from arriving. There is no automatic command retry.

The complete [server shop example](../examples/AuthoritativeShop.server.lua) belongs in ServerScriptService. The [client example](../examples/AuthoritativeShop.client.lua) belongs in StarterPlayerScripts and uses **B** to request a purchase. Keep prices, validators, reducers and persistence logic in server-only scripts; shared replica declarations contain only metadata.

## API

| Method | Side | Behavior |
|---|---|---|
| `Attach(player, state)` | Server | Start a new per-player epoch with a copied, validated state; rejects an existing attachment |
| `Set(player, state)` | Server | Replace the state; omitted fields become nil; changes coalesce until replication can advance |
| `Update(player, transform)` | Server | Transform a draft synchronously; commit a validated result atomically |
| `Get(player)` / `Get()` | Server / client | Return the frozen server state for a player / the local client mirror, or nil |
| `HandleCommand(name, spec)` | Server | Register required `Validate` and `Reduce` callbacks with optional `Rate`/`Burst` |
| `SendCommand(name, payload)` | Client | Queue a named command; returns `(true, sequence)` or `(false, reason)` |
| `OnChanged(callback)` | Client | Receive `(frozenStateOrNil, revision)`; nil indicates revocation; returns disconnectable connection |
| `OnCommandResult(callback)` | Client | Receive `(sequence, accepted, reason)`; returns disconnectable connection |
| `RequestResync()` | Client | Request a rate-limited full snapshot for this client's attachment |
| `Detach(player)` | Server | Revoke membership, clear state/baselines and send a tombstone when connected |
| `GetStats(player?)` | Both | Inspect traffic/rejections; server includes tracked-player count and optional pending/acknowledged revisions |
| `Destroy()` | Both | Disconnect listeners and heartbeat, clear state and handlers; server attempts a revocation message |

`PlayerRemoving` clears server tracking. `NetStream.Destroy()` destroys all its controllers. A client can read anything replicated to it; never put secrets in the field list. Owner-only delivery is intentional: this version does not provide observer subscriptions, spatial interest management or shared entity replicas.

## Revision and resynchronization rules

- Each player has its own immutable authoritative state, acknowledged baseline and **at most one pending revision**. Updates made while awaiting an ACK replace the current state; intermediate state versions are coalesced.
- The first frame is full. Later frames contain changed fields only, based on the exact server snapshot acknowledged by that recipient. No delta is built from a client-supplied value.
- An ACK must match both the current attachment epoch and the pending revision. It only promotes the server's pending snapshot to its replication baseline. **ACKs never change authoritative gameplay state and are not proof of honest client execution.**
- Missing ACKs trigger a full snapshot of the same pending revision/state after `RetryInterval`. Repeated frames are acknowledged without applying twice. After acknowledgement, any accumulated changes can form the next delta.
- A missing/mismatched baseline triggers a rate-limited resync. Resync never resets command replay protection or imports a client's state. The ordered field signature must match before a frame can apply.
- Detach/reattach uses a new server-generated epoch. Old commands, ACKs and frames cannot act on the new attachment. A tombstone prevents a delayed old frame from restoring revoked state.
- Reliable, coalesced data events keep queued retry storage bounded. Existing NetStream packet, queue and bandwidth controls still apply. If the connection cannot carry the configured state within those limits, retries cannot make it deliverable.

## Command trust boundary

The player comes from Roblox's server event, never from a payload `Player`/`UserId`. Commands require a matching attachment epoch and a monotonically increasing safe-integer sequence. Duplicate/old sequences are rejected. Gaps are allowed because the transport may reject queued commands under pressure. Sequence numbers are replay bookkeeping, **not authentication**. A cheater can invent fresh numbers, so validation and rate limits remain mandatory.

An aggregate server token bucket and a per-command bucket bound handler entry. Unknown names never allocate handler-specific rate entries. At most 32 handlers may be registered. Invalid requests are rejected; no automatic kicks or bans occur. Some early/rate rejections are silent to avoid response amplification.

Payloads are flat plain tables: at most 16 named primitive fields, key lengths 1..64 bytes, string values at most 256 bytes, and a 2,048-byte semantic key/value budget. Nested tables, buffers, Instances, nonfinite numbers and metatables are rejected by the command layer. These are **post-decode** limits; NetStream's global envelope/byte/depth/node limits remain the first defense against oversized packets. Tighten those global limits to suit your game.

`Validate(player, frozenPayload, frozenState)` must return exactly true. `Reduce(player, frozenPayload, draft)` returns the entire next state. Both must be fast and **must not yield**. Errors, yields, invalid state or validation denial leave the replica state unchanged. Attempts to call `Set`, `Update` or `Detach` recursively from a handler are rejected. The draft is copied again on commit, so retaining it does not grant future mutation access.

Reducers must be pure state transformations. This API cannot roll back external effects already performed by a validator/reducer (DataStore writes, inventory changes in another service, HTTP requests, spawned tasks, etc.), and cannot preempt an infinite CPU loop. Use a separate server transaction design for such operations. Replay rejection applies to an attachment only; it is not durable exactly-once processing across reconnects/restarts. Do not automatically retry purchases with new sequences.

Client subscriptions also must not yield; callback failures increment `CallbackErrors`. `OnChanged` does not replay an existing state on subscription—call `Get()` when binding a UI late. At most 64 listeners of each kind may be registered.

## Options and data limits

| Option | Default | Bounds / meaning |
|---|---:|---|
| `Id` | Required | 1..2,147,483,644; reserves four event IDs |
| `Fields` | Required | Ordered list of 1..32 unique names, each 1..64 bytes |
| `SendRate` | 20 | Integer 1..60 scheduling checks per second; ACK gating may reduce effective update rate |
| `RetryInterval` | 2 | 0.25..60 seconds; full retry/client resync interval |
| `MaxStateBytes` | 8192 | 128..65536 semantic key/value bytes; actual packet size includes overhead |
| `CommandRate` | 10 | Aggregate commands per second per player, 1..60 |
| `CommandBurst` | 5 | Aggregate initial/refill capacity, 1..60 |

State values support finite numbers, booleans, strings and nil (field absence). No nested tables, buffers or Roblox userdata in this first version. `MaxStateBytes` is not a physical wire-byte guarantee. Keep states small and within your transport budgets. Revisions reflect acknowledged transmission, not the number of server `Set` calls. This API replicates current state, not a durable event log or DataStore.

## Validation and remaining scope

Standalone tests execute the production controller, codec and delta code with deterministic clocks and service doubles. They cover forged state/ACKs, owner isolation, replay/epoch rejection, denied/malformed commands, rate recovery, non-yielding atomic reducers, loss/resync, retries, schema mismatch, lifecycle cleanup and 2,000 update steps under loss. A further integration test uses the public factory and actual BitFrame encoding/decoding/dispatch between two module instances with fake remotes; handshake and bandwidth timing are disabled for that deterministic test.

Run `tests/AuthoritativeReplicaRegression.server.lua` and its matching client in a fresh **two-player Studio session**. The Studio pair is authored but not executed here. Real scheduler/RemoteEvent behavior, handshake recovery with replicas, long-run heap use, throughput and p95/p99 latency remain live validation gates. A one-pending-revision design intentionally trades maximum throughput for bounded memory and simple baseline correctness.

Roblox guidance: [secure the client/server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary) through validation and rate limiting; keep authoritative logic [server-side](https://create.roblox.com/docs/scripting/security/access-control). No networking library can prevent a user from altering their own client UI or compensate for permissive game handlers.

## Strict security mode compatibility

Replica control and command events are automatically registered with server-side input policies. They continue operating when `NetStream.RequireServerPolicies(true)` is enabled for the application. The replica's server-side data/result event routes explicitly reject incoming client submissions. Schema, epoch, sequence, rate and command-handler validation still apply; no client can set the authoritative state through this protocol.

Malformed received delta frames are converted into rejected-frame telemetry and a rate-limited resync request rather than escaping the client's receive callback. Run `tests/runtime/replica.luau` and the paired Studio regression before production use.

## Persistence boundary

This module **does not provide durable transactions**. A reducer must only compute a validated in-memory next replica state; moving currency or inventory across server sessions requires an application-owned persistent transaction layer with atomic writes, idempotency and reconciliation. Network ACKs never establish a durable purchase commit.
