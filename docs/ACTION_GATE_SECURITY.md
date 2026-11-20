# Server-Issued Action Tickets and Fail-Closed Route Security

> **Status:** Available in the current v4.3.1-compatible `main` branch. These controls are opt-in and do not alter BitFrame v1 or codec 230.

The action gate extends the v4.3.1 security framework without changing the BitFrame v1 or codec 230 wire formats. It is a **defense-in-depth control**, not client anti-tamper: a modified client can submit arbitrary requests and inspect every ticket it receives. Server-owned state and independent validation remain the trust boundary.

[← Documentation index](README.md) · [Security policies](SECURITY.md) · [Authoritative replication](AUTHORITATIVE_REPLICATION.md)

## Security guarantees and limits

| Mechanism | Guarantees within one server process | Does not guarantee |
| --- | --- | --- |
| Player/action binding | An issued ticket is matched against the named player and action | The client cannot inspect or forward its identifier |
| Single-use redemption | A previously consumed ticket cannot execute again | A handler's side effects can be rolled back automatically |
| Expiry and bounded storage | Unused offers expire and outstanding capacity is capped | Persistent state across server restart or teleport |
| Route policies | Defined Validate/Authorize checks gate incoming callbacks | Domain invariants are correct without server-owned checks |

## Server-only action ticket gate

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

Ticket records are **in-memory and server-local**. They do not provide cross-server durability, inventory locks, or exactly-once persistence. The TTL and per-player cap bound the registry's retained records.

Capacity counts **outstanding unused** tickets. Completed tickets retain a bounded replay tombstone; older tombstones can be evicted safely because IDs are never reused. A revoked, expired, or consumed ticket cannot be redeemed.

`Revoke` returns `false` for an expired or already-consumed ticket, including one whose handler is running. Revocation cannot undo a transaction in progress. Recheck server-owned prices, balances, entitlements, and cooldowns **inside the handler** immediately before committing.

## Server-to-client-to-server example

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

## Opt-in route policy enforcement

`NetStream.RequireServerPolicies(true)` enables default-deny mode for
**incoming Event and Function gameplay callbacks** on that server.

- Routes without an installed policy are rejected before gameplay callbacks.
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

## Deployment checklist

- [ ] Use server-only logic to decide whether a ticket should be issued.
- [ ] Ensure the ticket is bound to the intended player and action.
- [ ] Revalidate mutable prices, balance, ownership, cooldowns and permissions inside the redemption handler.
- [ ] Reserve and commit durable purchase identifiers outside NetStream when persistence is required.
- [ ] Run duplicate, expired, wrong-player, wrong-action, disconnect and handler-error regressions.

## Diagnostics and testing

`GetStats()` adds:

`SecurityPolicyYieldRejects`, `SecurityUnprotectedDrops`,
`SecurityTicketsIssued`, `SecurityTicketsRedeemed`,
`SecurityTicketsRejected`, `SecurityTicketsReplayDrops`,
`SecurityTicketsCapacityDrops`, `SecurityTicketsHandlerErrors`.

`tests/runtime/tickets.luau` runs in the official Luau interpreter in CI.
Run `tests/ActionTicketRegression.server.lua` and its matching client script in Roblox Studio to validate the actual server/client transport.
CI service mocks do not simulate multiplayer, Heartbeat, network loss,
DataStores or cross-server persistence.

## Threat model and limitations

No key, hash, encrypted packet, client checksum or handshake can make client
data immutable once it reaches the player's machine. The server-to-client-
to-server round trip limits *which* actions may be attempted but is not a
substitute for authoritative game state and independent validation.

## Related documentation

- [Security policies and idempotency](SECURITY.md)
- [Runtime validation](RUNTIME_VALIDATION.md)
- [NetStreamV2 overview](../README.md)
