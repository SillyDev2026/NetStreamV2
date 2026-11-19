local function scenario(disconnect)
    local net = loadNetStream()
    net.Configure({MaxConcurrentIncomingCalls = 2, MaxConcurrentIncomingCallsPerPlayer = 1})
    local hooks = net.__test
    local player = {Parent = hooks.players, __player = true, IsA = function(_, name) return name == "Player" end}
    hooks.register(123, function(_, value)
        assert(value == 7)
        coroutine.yield()
        return "complete"
    end)
    assert(hooks.charge(player))
    assert(not hooks.charge(player), "Per-player limit bypassed")
    local thread = coroutine.create(hooks.run)
    assert(coroutine.resume(thread, player, 123, 1, table.pack(7)))
    assert(net.GetRPCStats().Active == 1)
    net.ResetStats()
    assert(net.GetRPCStats().PeakActive == 1)
    if disconnect then player.Parent = nil else net.Destroy() end
    assert(coroutine.resume(thread))
    assert(coroutine.status(thread) == "dead")
    assert(net.GetRPCStats().Active == 0, "RPC capacity leaked")
    assert(net.GetRPCStats().ExecutionErrors == 0, "RPC completion raised an internal error")
    assert(net.GetStats().TransportLogicalMessagesQueued == 0, "Late response recreated an outbound queue")
end
local lifecycleFailures = 0
for _, disconnect in {true, false} do
    local ok, err = pcall(scenario, disconnect)
    if not ok then print("FAIL RPC", if disconnect then "disconnect" else "destroy", err); lifecycleFailures += 1 end
end
assert(lifecycleFailures == 0, "RPC lifecycle failures")
print("PASS RPC: yielding callback, concurrency cap, reset, disconnect/destroy, late response cleanup")
local net = loadNetStream()
net.Configure({MaxConcurrentIncomingCalls = 2, MaxConcurrentIncomingCallsPerPlayer = 1})
local hooks = net.__test
local function player() return {Parent = hooks.players, __player = true, IsA = function(_, name) return name == "Player" end} end
local a, b, c = player(), player(), player()
assert(hooks.charge(a) and hooks.charge(b))
assert(not hooks.charge(c), "Global concurrency cap bypassed")
hooks.register(1, function() error("intentional callback error") end)
hooks.run(a, 1, 1, table.pack())
assert(net.GetRPCStats().Active == 1 and net.GetRPCStats().ExecutionErrors == 0)
assert(hooks.charge(c), "Capacity not recovered after callback error")
b.Parent, c.Parent = nil, nil
hooks.run(b, 1, 2, table.pack())
hooks.run(c, 1, 3, table.pack())
assert(net.GetRPCStats().Active == 0)
assert(net.GetStats().TransportLogicalMessagesQueued == 1, "Error response was not queued exactly once")
print("PASS RPC: global cap, application errors, recovery, connected error response")
