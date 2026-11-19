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
assert(gate:Revoke(player, id))
local removed, reason = gate:Redeem(player, id, "BuyUpgrade", function() error("Revoked ticket") end)
assert(not removed and reason == "Unknown")
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
