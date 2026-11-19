# NetStreamV2 server security policies (v4.3.1 patch candidate)

NetStream's client is **untrusted**. This patch adds an opt-in, server-only policy
gateway for inbound `Event` and `Function` routes, with a bounded idempotency
helper. It does **not** prevent exploiters from sending remote packets, make
client scripts tamper-proof, or replace game-specific authorization.

## Event policy — all listeners are gated

```luau
-- ServerScriptService. NEVER accept client-reported balances or prices.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types
local Buy = NetStream.Event("BuyUpgrade", {
    Id = 42001, Schema = {T.U16, T.U32}, MaxPerSecond = 5, Burst = 2, Compression = false,
})
local Prices = {[1] = 100, [2] = 300}
local Data = {} -- Replace with your server-owned player profile system.
local Dedup = NetStream.CreateIdempotencyGuard({TTLSeconds = 120, MaxEntriesPerPlayer = 128})

NetStream.SetServerPolicy(Buy, {
    Validate = function(player, upgradeId, requestKey)
        return Prices[upgradeId] ~= nil and requestKey >= 1
    end,
    Authorize = function(player, upgradeId, requestKey)
        return Data[player] ~= nil
    end,
})

Buy:Connect(function(player, upgradeId, requestKey)
    local accepted, reason = Dedup:Execute(player, requestKey, function()
        -- Recheck authority *inside* the transaction. A guard does not lock state.
        local data = Data[player]
        local price = Prices[upgradeId]
        if not data or not price or data.Coins < price then return false end
        data.Coins -= price
        data.Upgrades[upgradeId] = (data.Upgrades[upgradeId] or 0) + 1
        return true
    end)
    -- Reply with a server-owned result/snapshot as needed.
end)
```

Client:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types
local Buy = NetStream.Event("BuyUpgrade", {Id = 42001, Schema = {T.U16, T.U32}, Compression = false})
Buy:FireServer(1, 123456) -- A request, NOT permission or authoritative state.
```

* Client-supplied request IDs are untrusted. A malicious client can always
  choose a different ID. This helper prevents accidental/replayed use of the
  **same** ID within one server session; the game must still validate
  entitlement, stock, currency, cooldowns, and gameplay invariants.
* The example uses in-memory data and is **not** a durable purchase system.
  For persistent rewards, use server-side datastore transaction semantics
  and durable idempotency records as appropriate.

## API and semantics

`NetStream.SetServerPolicy(route, {Validate = function(player, ...): boolean?,
Authorize = function(player, ...): boolean?})`

- Server-only. The route must be a registered `Event` or `Function` route;
  at least one predicate is required. Predicates must return exactly `true`.
- Predicates are evaluated in order: Validate, then Authorize.
- A `false`/non-true result or an exception rejects the request. Exceptions
  are counted in `SecurityPolicyErrors`, not propagated to gameplay callbacks.
- All listeners on a protected event route share the same policy. Scalar and
  packed event packet paths converge before callback dispatch.
- RPC callbacks are screened before invocation; a rejected RPC receives the
  generic error `Request rejected`. Event rejections are silently dropped.
- Existing routes without policies keep their prior behavior; this is an
  opt-in mechanism, **not** a global deny-by-default firewall.
- A policy is evaluated at callback dispatch time. Keep policy functions
  fast and **non-yielding**, do not mutate authoritative state in them, and
  recheck critical conditions in the transaction handler.
- `State` routes are intentionally not policy targets. Do not interpret
  client-reported `State` values as authoritative currency, damage, XP, etc.
- `NetStream.GetStats()` includes `SecurityPolicyChecks`,
  `SecurityPolicyAccepted`, `SecurityPolicyRejects`,
  `SecurityPolicyErrors` and idempotency counters.

`NetStream.CreateIdempotencyGuard({TTLSeconds = 60, MaxEntriesPerPlayer = 128})`

- Only callable on the server; `guard:Execute(player, requestKey, handler)`
  reserves a key *before* calling the server handler.
- Keys: nonempty strings up to 64 bytes or positive safe integers; each guard
  is an independent operation namespace. Entries are capped per connected player.
- Returns `true, ...` for first execution; `false, "Duplicate"` for reused
  keys, `false, "Capacity"` when full, and `false, "HandlerError"` if the
  handler raises. A failed handler key remains reserved for its TTL to avoid
  accidental second application after uncertain side effects.
- Pending actions are not expired while in flight. On completion, the TTL
  begins. `guard:ClearPlayer(player)` is available on player departure.
- Reservations are in-memory only and reset if the server restarts.
  No API can guarantee exactly-once purchases merely by receiving a client ID.
- Use the per-route `MaxPerSecond`/`Burst`, bounded message sizes and global
  ingress limits as additional layers. Event drops under rate/dispatch pressure
  still require app-level acknowledgement/retry decisions.

## Validation boundaries

`tests/runtime/security.luau` exercises actual event/scalar dispatch,
RPC callback admission, fail-closed error handling, disconnected senders,
per-player idempotency, capacity, handler exceptions and pending duplicates.
CI executes the official Luau interpreter with service mocks.

These tests are **not** real Roblox Studio multiplayer tests. Before production:
run paired Studio tests, observe heap/GC, validate all legacy/BitFrame transports,
test rapid join/leave and permission changes, and stress concurrent purchases.

Security code cannot protect replicated code and assets. Only server-exclusive
scripts and server-owned gameplay state should contain authority.
