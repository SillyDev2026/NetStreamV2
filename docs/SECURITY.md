# Server-Side Security

**Applies to:** NetStreamV2 v4.3.1 and compatible source changes on `main`.

[← Documentation index](README.md) · [Action tickets](ACTION_GATE_SECURITY.md) · [Server stress tests](SERVER_STRESS_VALIDATION.md)

## Security model

**Assume every Roblox client is controlled by its player.** An exploiter can modify LocalScripts, inspect packet contents, and submit arbitrary remote requests. NetStream can validate packet structure, bound traffic, and authorize server callbacks, but it cannot make client data trustworthy or eliminate the need for game-specific server validation.

| Layer | Purpose | Limitation |
| --- | --- | --- |
| Schema and payload validation | Reject malformed messages and out-of-range inputs | Validly encoded data can still be malicious |
| Per-route limits and global budgets | Bound frequency and resource consumption | Rate-compliant requests may still be unauthorized |
| Server policies | Admit only requests that pass trusted predicates | Policies must correctly express game permissions |
| Action tickets | Restrict an issued offer to a player, action and expiry | Tickets are visible identifiers, not secret client credentials |
| Idempotency guard | Suppress a repeated request key within one server | Not durable across restarts or servers |
| Authoritative transactions | Protect currency, inventory and entitlement invariants | Must be implemented by your game/data layer |

## Authorize an incoming Event

Declare the same route ID and schema on the server and client. On the **server**, attach an authorization policy before enabling strict mode.

```luau
-- ServerScriptService
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

local Buy = NetStream.Event("BuyUpgrade", {
    Id = 42001,
    Schema = {T.U16, T.U32},
    MaxPerSecond = 5,
    Burst = 2,
    Compression = false,
})
local Prices = {[1] = 100, [2] = 300}
local Profiles = {} -- Populate only from the server's trusted data layer.
local Dedup = NetStream.CreateIdempotencyGuard({
    TTLSeconds = 120,
    MaxEntriesPerPlayer = 128,
})

NetStream.SetServerPolicy(Buy, {
    Validate = function(player, upgradeId, requestKey)
        return Prices[upgradeId] ~= nil and requestKey > 0
    end,
    Authorize = function(player)
        return Profiles[player] ~= nil
    end,
})

Buy:Connect(function(player, upgradeId, requestKey)
    local executed, approved = Dedup:Execute(player, requestKey, function()
        local profile = Profiles[player]
        local price = Prices[upgradeId]
        if not profile or not price or profile.Coins < price then return false end

        -- Perform any read/check/write atomically for this player's state.
        -- Replace this illustration with durable transactions where needed.
        profile.Coins -= price
        profile.Upgrades[upgradeId] = (profile.Upgrades[upgradeId] or 0) + 1
        return true
    end)

    if executed and approved then
        -- Emit a server-owned result/state acknowledgement as needed.
    end
end)

-- Enable only after adding policies to all applicable incoming routes.
-- NetStream.RequireServerPolicies(true)
```

On the client, `Buy:FireServer(upgradeId, requestKey)` is a **request**, not authorization. The client chooses its request key; an attacker can always choose another. Preventing duplicate keys is not sufficient protection against fabricated transactions.

## Policy API and behavior

```luau
NetStream.SetServerPolicy(route, {
    Validate = function(player, ...)
        return true
    end,
    Authorize = function(player, ...)
        return true
    end,
})

NetStream.RequireServerPolicies(true)
NetStream.RejectClientStateRoutes(true)
```

- `SetServerPolicy` is server-only and applies to registered `Event` and `Function` routes. Include at least one predicate.
- Predicates run in `Validate`, then `Authorize` order; each defined predicate must return **exactly `true`**. Errors, yields and non-true values reject the request.
- Event listeners on a route share the same admission policy. RPC rejection uses a generic response rather than exposing server internals.
- `RequireServerPolicies(true)` turns on **default-deny admission** for incoming Event/Function gameplay callbacks. Routes without policies are otherwise allowed under the normal transport limits.
- `RejectClientStateRoutes(true)` separately blocks client-origin `State` updates before they can change the server peer-state cache. This switch does not make allowed client State authoritative.
- Keep predicates synchronous and side-effect free. Validate mutable facts again inside the gameplay handler before changing trusted state.
- Strict mode may break existing client→server routes until their policies are configured. Migrate and test routes first.

## Single-session idempotency

`NetStream.CreateIdempotencyGuard({TTLSeconds = 60, MaxEntriesPerPlayer = 128})` creates a server-only, per-player bounded key registry.

| Operation | Behavior |
| --- | --- |
| `guard:Execute(player, key, handler)` | Reserves the key before invoking the handler |
| Repeated key | Returns `false, "Duplicate"` |
| Entry cap reached | Returns `false, "Capacity"` |
| Handler exception | Returns `false, "HandlerError"`; reservation is retained |
| `guard:ClearPlayer(player)` | Releases the player's in-memory entries |

Keys are nonempty strings up to 64 bytes or positive safe integers. A reservation's TTL begins after its handler completes; pending actions are not expired mid-flight.

**Do not use this guard as a durable purchase ledger.** Server restarts and cross-server transfers require persistent transaction identifiers, atomic state updates, and recovery policies in the game's data system.

For pre-authorized UI interactions, see [Server-issued action tickets](ACTION_GATE_SECURITY.md).

## RPC error privacy

Server RPC exceptions and value-validation diagnostics can reveal implementation details. The client receives generic failures such as `Remote callback failed`, `Remote callback unavailable`, or `Remote callback returned invalid data`. Detailed diagnostics remain server-side.

Inspect `NetStream.GetRPCStats()` and `NetStream.GetStats()` for callback errors, invalid results, active calls, concurrency drops, and policy rejection counters. Do not design client logic around raw server stack traces.

## Peer state and snapshots

When `RejectClientStateRoutes(true)` is enabled, previously accepted client-origin peer-state values are cleared. `NetStream.GetStateSnapshot(player)` also detaches nested tables and buffers from the live cache, and `StateRoute:Get(player)` preserves meaningful `false` values.

**A detached snapshot is still untrusted if its source is a client.** Do not derive server-owned balance, XP, or item ownership from it.

## Validation and deployment checklist

The production-code Luau suites test policy admission, yielding/error paths, RPC behavior, idempotency, replayed tickets and malformed packets. The [simulated-server stress guide](SERVER_STRESS_VALIDATION.md) describes the workloads.

Before live deployment:

1. Inventory every incoming Event/Function route and set explicit validation and authorization where needed.
2. Run the [paired Studio tests](BENCHMARKING.md), including malicious messages and concurrent requests, with more than one real player.
3. Confirm that every purchase, trade or reward is atomic in the server's trusted data layer.
4. Stress reconnects, dropped packets, stale tickets, rate limits, player departures and cleanup.
5. Monitor rejection counters and false positives; make enforcement decisions in game-specific server logic.

**Guarantee boundary:** NetStream is defense in depth, not a universal anti-cheat system or a cryptographic trust layer.
