# Server-issued action tickets and fail-closed route security

This patch extends the v4.3.1 security framework without changing BitFrame v1,
codec 230, or any transport packet format. It is a defense-in-depth layer,
**not** a client anti-tamper system. Clients can forge or replay packets and
modify everything they receive. Only the server's state and rules are trusted.

## 1. Server-only action ticket gate

`NetStream.CreateActionGate({TTLSeconds = 10, MaxTicketsPerPlayer = 32})`
creates a local server-only ticket registry.

- `gate:Issue(player, actionName, serverPayload?) -> ticketId | nil, reason`
- `gate:Redeem(player, ticketId, actionName, handler) -> executed, resultOrReason, ...`
- `gate:Revoke(player, ticketId) -> boolean`
- `gate:ClearPlayer(player)`

The **server** issues a ticket for one connected player and a specific action,
storing a primitive payload under the server's control. IDs are opaque
identifiers for mapping, **not cryptographic secrets**. They can be inspected
by clients; security comes from matching the server's record, player, action,
expiration and one-use reservation—not from hiding the ID.

Tickets are positive U32 identifiers. When the per-gate U32 space is exhausted,
`Issue` fails closed instead of reusing an identifier. Keep separate gates for
unrelated features. Only primitive `nil`, boolean, finite number or bounded
string payloads are allowed: do not store mutable client objects.

`Redeem` marks a ticket *used before* invoking the handler, including if
the handler yields. The ticket cannot be redeemed twice, even if the handler
raises or a concurrent request arrives. It is deliberately not returned to
the pool on a handler error because partial side effects may have occurred.
The server must re-check changing facts—balance, ownership, stock and
entitlements—inside the handler. Tickets do **not** authorize a fresh client
request the server never approved.

Records are in process memory: no cross-server durability, inventory lock,
Ticket capacity counts **outstanding unused** tickets. Completed tickets retain
a bounded replay tombstone (up to the configured cap); old tombstones can be
evicted without allowing redemption, because numeric IDs are never reused.
`Revoke` returns false for expired or already consumed tickets, including
a redemption currently executing. It cannot undo a committed or in-flight
transaction. Recheck authoritative conditions immediately before committing.


or exactly-once persistence guarantee. The per-player cap and TTL bound memory.
`Revoke` does not cancel a handler already running.

## 2. Server-to-client-to-server example

Server:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

local Offer = NetStream.Event("OfferUpgrade", {Id = 45001, Schema = {T.U32}, Compression = false})
local Accept = NetStream.Event("AcceptUpgrade", {Id = 45002, Schema = {T.U32}, Compression = false, MaxPerSecond = 5, Burst = 2})
local Result = NetStream.Event("UpgradeResult", {Id = 45003, Schema = {T.Bool}, Compression = false})
local Tickets = NetStream.CreateActionGate({TTLSeconds = 10, MaxTicketsPerPlayer = 16})
local Data = {} -- server-owned profiles must be loaded separately

NetStream.SetServerPolicy(Accept, {
    Validate = function(player, ticket)
        return type(ticket) == "number" and ticket >= 1
    end,
    Authorize = function(player)
        return Data[player] ~= nil
    end,
})
-- Configure strict mode AFTER attaching policies to every inbound Event/Function route.
NetStream.RequireServerPolicies(true)

Accept:Connect(function(player, ticket)
    local accepted, approved = Tickets:Redeem(player, ticket, "Upgrade", function(owner, upgradeId)
        local data = Data[owner]
        local price = if upgradeId == 2 then 100 else nil
        if not data or not price or data.Coins < price then return false end
        -- The read/check/write must be serialized per player. This example
        -- does not yield; use durable transactional storage for persisted purchases.
        data.Coins -= price
        data.Upgrades[upgradeId] = (data.Upgrades[upgradeId] or 0) + 1
        return true
    end)
    Result:FireClient(player, accepted and approved == true)
end)

local function offerUpgrade(player)
    local data = Data[player]
    if not data then return end
    local ticket = Tickets:Issue(player, "Upgrade", 2)
    if ticket then Offer:FireClient(player, ticket) end
end
Players.PlayerRemoving:Connect(function(player)
    Tickets:ClearPlayer(player)
    Data[player] = nil
end)
-- Call offerUpgrade(player) from a validated server-side shop interaction.
```

Client:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types
local Offer = NetStream.Event("OfferUpgrade", {Id = 45001, Schema = {T.U32}, Compression = false})
local Accept = NetStream.Event("AcceptUpgrade", {Id = 45002, Schema = {T.U32}, Compression = false})
local Result = NetStream.Event("UpgradeResult", {Id = 45003, Schema = {T.Bool}, Compression = false})
Offer:Connect(function(ticket)
    -- In a real UI, present the offer and call this when Buy is clicked.
    Accept:FireServer(ticket)
end)
Result:Connect(function(ok) print("Purchase accepted:", ok) end)
```

Never let an untrusted client generate arbitrary purchase offers. The server
should only issue tickets for actions that make sense for the player's current
server-validated context.

## 3. Opt-in policy firewall

`NetStream.RequireServerPolicies(true)` enables default-deny mode for
**incoming Event and Function gameplay callbacks** on that server.

- Unknown/unprotected routes are rejected before gameplay callbacks.
- `NetStream.SetServerPolicy(route, {Validate=..., Authorize=...})` provides
  the allow conditions. Both callbacks (when present) must return exactly
  `true`; errors and **yields** are denied.
- `RequireServerPolicies(false)` explicitly restores the opt-in behavior.
- This deliberately does **not** cover inbound `State` routes, transport
  handshakes or peer-side replication. No client-reported `State` is
  authoritative. Do not write trusted game data from such routes.
- Turning it on can break old client-to-server Event/Function routes until
  policies are configured; migrate and test them before enabling.

This checks callback admission, not the atomicity of game data writes.
Authorization policies must remain pure and non-yielding; changing conditions
must also be verified in the protected handler.

## 4. Monitoring and testing

`GetStats()` adds:

`SecurityPolicyYieldRejects`, `SecurityUnprotectedDrops`,
`SecurityTicketsIssued`, `SecurityTicketsRedeemed`,
`SecurityTicketsRejected`, `SecurityTicketsReplayDrops`,
`SecurityTicketsCapacityDrops`, `SecurityTicketsHandlerErrors`.

`tests/runtime/tickets.luau` runs in the official Luau interpreter in CI.
Run the paired Studio scripts for actual server/client transport behavior.
CI service mocks do not simulate multiplayer, Heartbeat, network loss,
DataStores or cross-server persistence.

## Threat-model limitations

No key, hash, encrypted packet, client checksum or handshake can make client
data immutable once it reaches the player's machine. The server-to-client-
to-server round trip limits *which* actions may be attempted but is not a
substitute for authoritative game state and independent validation.
