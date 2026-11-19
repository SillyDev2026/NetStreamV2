local net = loadNetStream()
local hooks = net.__test
local player = {Parent = hooks.players, __player = true, IsA = function(_, kind) return kind == "Player" end}
local other = {Parent = hooks.players, __player = true, IsA = function(_, kind) return kind == "Player" end}
local events = 0
local route = {Id = 9931, _listenerCount = 1}
route._head = {connected = true, once = false, callback = function(_, value) assert(value == 7); events += 1 end}
hooks.registerEvent(route.Id, route)

assert(net.RequireServerPolicies(true), "Strict policies not enabled")
hooks.dispatch(route, player, table.pack(7))
hooks.dispatchScalar(route, player, 7)
assert(events == 0 and net.GetStats().SecurityUnprotectedDrops == 2, "Unprotected event got through strict mode")
net.SetServerPolicy(route, {Authorize = function(_, value) return value == 7 end})
hooks.dispatch(route, player, table.pack(7))
hooks.dispatchScalar(route, player, 7)
assert(events == 2, "Guarded event did not execute")
net.SetServerPolicy(route, {Validate = function() coroutine.yield(); return true end})
hooks.dispatch(route, player, table.pack(7))
assert(events == 2 and net.GetStats().SecurityPolicyYieldRejects == 1, "Yielding policy bypassed validation")
net.SetServerPolicy(route, {Validate = function() return true end})
other.Parent = nil
hooks.dispatch(route, other, table.pack(7))
assert(events == 2, "Disconnected player got through policy")
other.Parent = hooks.players

local rpcRuns = 0
hooks.registerFunction(9932, {Id = 9932, _callback = function() rpcRuns += 1; return 9 end})
assert(hooks.charge(player))
hooks.run(player, 9932, 123, table.pack())
assert(rpcRuns == 0 and net.GetRPCStats().Active == 0, "Unprotected RPC bypassed strict mode")
local rpc = {Id = 9933, _callback = function() rpcRuns += 1; return 9 end}
hooks.registerFunction(9933, rpc)
net.SetServerPolicy(rpc, {Authorize = function() return true end})
assert(hooks.charge(player))
hooks.run(player, 9933, 124, table.pack())
assert(rpcRuns == 1 and net.GetRPCStats().Active == 0, "Guarded RPC failed")
assert(net.RequireServerPolicies(false) == false)
print("PASS TICKETS: fail-closed opt-in policies, yield rejection, RPC and disconnect")

local stateRoute = {Id = 9944}
hooks.registerState(stateRoute.Id, stateRoute)
local staleState = net.GetState(player)
staleState[stateRoute.Id] = "forged-old-client-state"
assert(net.RejectClientStateRoutes(true))
assert(net.GetState(player)[stateRoute.Id] == nil, "Strict State mode retained previously accepted untrusted state")
assert(net.GetState(player) ~= staleState, "Strict mode left stale peer table live")
assert(hooks.allowance(stateRoute, player, 1) == 0)
assert(hooks.allowance(stateRoute, player, 3) == 0)
assert(net.GetStats().SecurityClientStateDrops == 4, "Blocked client State updates were not counted")
assert(net.RejectClientStateRoutes(false) == false)
assert(hooks.allowance(stateRoute, player, 1) == 1, "State compatibility mode broken")
print("PASS TICKETS: State ingress rejection before peer-state mutation")

local nested = {Payload = {Score = 8, Encoded = buffer.fromstring("abc")}}
local internalState = net.GetState(player)
internalState[9945] = nested
local firstSnapshot = net.GetStateSnapshot(player)
local secondSnapshot = net.GetStateSnapshot(player)
assert(firstSnapshot ~= internalState and firstSnapshot[9945] ~= nested, "Snapshot returned live state")
assert(firstSnapshot[9945].Payload ~= nested.Payload, "Snapshot retained nested table alias")
assert(firstSnapshot[9945].Payload.Encoded ~= nested.Payload.Encoded, "Snapshot retained mutable buffer alias")
firstSnapshot[9945].Payload.Score = 123
buffer.writeu8(firstSnapshot[9945].Payload.Encoded, 0, 122)
assert(nested.Payload.Score == 8 and buffer.readu8(nested.Payload.Encoded, 0) == 97, "Editing snapshot mutated trusted cached state")
assert(secondSnapshot[9945].Payload.Score == 8, "Separate snapshots aliased each other")
local cyclic = {}
cyclic.Self = cyclic
internalState[9946] = cyclic
local cyclicSnapshot = net.GetStateSnapshot(player)
assert(cyclicSnapshot[9946] ~= cyclic and cyclicSnapshot[9946].Self == cyclicSnapshot[9946], "Snapshot failed to clone cycles safely")
print("PASS STATE: nested tables, mutable buffers and cyclic snapshots are detached")

local gate = net.CreateActionGate({TTLSeconds = 20, MaxTicketsPerPlayer = 2})
assert(not pcall(function() gate:Issue(player, "Buy", {}) end), "Mutable server payload allowed")
assert(not pcall(function() gate:Issue(player, "", 1) end), "Empty action allowed")
local id = gate:Issue(player, "BuyUpgrade", 5)
assert(type(id) == "number" and id >= 1)
local wrong, why = gate:Redeem(player, id, "Equip", function() error("Wrong action handler ran") end)
assert(not wrong and why == "WrongAction")
local foreign, foreignReason = gate:Redeem(other, id, "BuyUpgrade", function() error("Other player handler ran") end)
assert(not foreign and foreignReason == "Unknown")
local count = 0
local second = gate:Issue(player, "BuyUpgrade", 2)
assert(second)
local full, fullReason = gate:Issue(player, "BuyUpgrade", 9)
assert(not full and fullReason == "Capacity")
local ok, value = gate:Redeem(player, id, "BuyUpgrade", function(recipient, upgradeId)
    assert(recipient == player and upgradeId == 5)
    count += 1
    local again, whyAgain = gate:Redeem(player, id, "BuyUpgrade", function() error("Reentry bypass") end)
    assert(not again and whyAgain == "Duplicate")
    return 55
end)
assert(ok and value == 55 and count == 1)
local duplicate, duplicateReason = gate:Redeem(player, id, "BuyUpgrade", function() error("Duplicate executed") end)
assert(not duplicate and duplicateReason == "Duplicate")
local failed, failReason = gate:Redeem(player, second, "BuyUpgrade", function() error("Uncertain outcome") end)
assert(not failed and failReason == "HandlerError")
local again = gate:Redeem(player, second, "BuyUpgrade", function() error("Failed ticket replay") end)
assert(not again, "Failed execution ticket became reusable")
assert(not gate:Revoke(player, id), "Revoke must not claim an executing/used ticket was canceled")
local removed, reason = gate:Redeem(player, id, "BuyUpgrade", function() error("Used ticket executed") end)
assert(not removed and reason == "Duplicate")
gate:ClearPlayer(player)
local newId = gate:Issue(player, "Equip", "Sword")
assert(newId)
player.Parent = nil
local disconnected = gate:Redeem(player, newId, "Equip", function() error("Disconnected handler") end)
assert(not disconnected)
assert(net.GetStats().SecurityTicketsIssued == 3)
assert(net.GetStats().SecurityTicketsRedeemed == 1)
assert(net.GetStats().SecurityTicketsReplayDrops >= 2)
assert(net.GetStats().SecurityTicketsHandlerErrors == 1)
print("PASS TICKETS: binding, action matching, one use, reentrancy, limits, revocation, errors, disconnected players")


local rollover = net.CreateActionGate({TTLSeconds = 20, MaxTicketsPerPlayer = 1})
player.Parent = hooks.players
local first = rollover:Issue(player, "Repeat", 1)
assert(first ~= nil, "Initial ticket could not be issued")
assert(rollover:Redeem(player, first, "Repeat", function(_, value) assert(value == 1); return true end))
local secondTicket = rollover:Issue(player, "Repeat", 2)
assert(secondTicket and secondTicket ~= first, "Consumed ticket blocked a new offer")
local deniedCap, capReason = rollover:Issue(player, "Repeat", 3)
assert(not deniedCap and capReason == "Capacity", "Outstanding ticket cap not enforced")
assert(rollover:Revoke(player, secondTicket), "Unused ticket could not be revoked")
assert(not rollover:Redeem(player, secondTicket, "Repeat", function() error("Revoked ticket executed") end))
assert(not rollover:Revoke(player, first), "Used/expired ticket revoke incorrectly succeeded")
local third = rollover:Issue(player, "Repeat", 3)
assert(third and third > secondTicket, "Revoked ticket slot was not recovered")
assert(rollover:Redeem(player, third, "Repeat", function() return true end))
assert(not rollover:Redeem(player, third, "Repeat", function() error("Replay executed") end))
print("PASS TICKETS: consumed offers free admission, tombstones bounded and revocation accurate")
