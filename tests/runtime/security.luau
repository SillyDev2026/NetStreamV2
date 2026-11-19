local net = loadNetStream()
local hooks = net.__test
local player = {Parent = hooks.players, __player = true, IsA = function(_, kind) return kind == "Player" end}
local other = {Parent = hooks.players, __player = true, IsA = function(_, kind) return kind == "Player" end}
local eventCalls = 0
local event = {Id = 9101, _listenerCount = 1}
event._head = {connected = true, once = false, callback = function(_, amount) assert(amount == 7); eventCalls += 1 end}
hooks.registerEvent(event.Id, event)
assert(not pcall(net.SetServerPolicy, event, {}), "Empty policy was accepted")
net.SetServerPolicy(event, {
    Validate = function(_, amount) return type(amount) == "number" and amount >= 1 and amount <= 10 end,
    Authorize = function(_, amount) return amount == 7 end,
})
hooks.dispatch(event, player, table.pack(7))
assert(eventCalls == 1, "Valid event rejected")
hooks.dispatch(event, player, table.pack(8))
hooks.dispatch(event, player, table.pack("7"))
assert(eventCalls == 1, "Unauthorized or malformed event reached gameplay listener")
hooks.dispatchScalar(event, player, 7)
assert(eventCalls == 2, "Scalar event was not authorized")
hooks.dispatchScalar(event, player, 9)
assert(eventCalls == 2, "Scalar event bypassed security")
player.Parent = nil
hooks.dispatch(event, player, table.pack(7))
assert(eventCalls == 2, "Disconnected event bypassed security")
player.Parent = hooks.players
net.SetServerPolicy(event, {Authorize = function() error("guard failure") end})
hooks.dispatch(event, player, table.pack(7))
assert(eventCalls == 2, "Throwing guard bypassed fail-closed policy")
assert(net.GetStats().SecurityPolicyChecks == 7)
assert(net.GetStats().SecurityPolicyAccepted == 2)
assert(net.GetStats().SecurityPolicyRejects == 5)
assert(net.GetStats().SecurityPolicyErrors == 1)
print("PASS SECURITY: event and scalar dispatch, checks, authorization, guard errors, disconnected player")

local rpcCalls = 0
local rpc = {Id = 9102, _callback = function(_, value) rpcCalls += 1; return value end}
hooks.registerFunction(rpc.Id, rpc)
net.SetServerPolicy(rpc, {Validate = function(_, value) return value == 42 end})
assert(hooks.charge(player))
hooks.run(player, rpc.Id, 1, table.pack(13))
assert(rpcCalls == 0, "Rejected RPC reached gameplay callback")
assert(net.GetRPCStats().Active == 0, "Rejected RPC failed to return its concurrency slot")
assert(hooks.charge(player))
hooks.run(player, rpc.Id, 2, table.pack(42))
assert(rpcCalls == 1, "Authorized RPC did not execute")
assert(net.GetRPCStats().Active == 0)
assert(not pcall(net.SetServerPolicy, {}, {Validate = function() return true end}), "Unregistered route accepted")
print("PASS SECURITY: RPC policy applied before callback and concurrency reclaimed")

local guard = net.CreateIdempotencyGuard({TTLSeconds = 30, MaxEntriesPerPlayer = 2})
local performed = 0
local ok, result = guard:Execute(player, "buy-1", function() performed += 1; return 55 end)
assert(ok and result == 55 and performed == 1)
local dup, reason = guard:Execute(player, "buy-1", function() performed += 1 end)
assert(not dup and reason == "Duplicate" and performed == 1)
assert(guard:Execute(player, "buy-2", function() performed += 1 end))
local full, capacityReason = guard:Execute(player, "buy-3", function() performed += 1 end)
assert(not full and capacityReason == "Capacity" and performed == 2)
assert(not pcall(function() guard:Execute(player, {}, function() end) end), "Invalid request key accepted")
local otherOk = guard:Execute(other, "buy-1", function() return true end)
assert(otherOk, "Player transaction namespaces overlapped")
guard:ClearPlayer(player)
assert(guard:Execute(player, "buy-1", function() performed += 1 end))
assert(performed == 3)
local failure, failReason = guard:Execute(player, "bad", function() performed += 1; error("uncertain side effect") end)
assert(not failure and failReason == "HandlerError")
assert(not guard:Execute(player, "bad", function() performed += 1 end), "Failed callback was retried with same key")
assert(performed == 4)
print("PASS SECURITY: per-player replay keys, bounds, server-only reservations, failure retention")

local inflight = net.CreateIdempotencyGuard({MaxEntriesPerPlayer = 1})
local thread = coroutine.create(function()
    local allowed = inflight:Execute(player, "pending", function()
        coroutine.yield()
        return true
    end)
    assert(allowed)
end)
assert(coroutine.resume(thread))
local pending, pendingReason = inflight:Execute(player, "pending", function() error("duplicate executed") end)
assert(not pending and pendingReason == "Duplicate", "Pending request was not reserved before yielding")
assert(coroutine.resume(thread))
assert(coroutine.status(thread) == "dead")
print("PASS SECURITY: in-flight duplicate suppression")
