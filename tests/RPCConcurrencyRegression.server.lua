--!strict
-- ServerScriptService; pair with RPCConcurrencyRegression.client.lua in a fresh Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.0")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, MaxConcurrentIncomingCalls = 8, MaxConcurrentIncomingCallsPerPlayer = 2, MaxIncomingCallsPerSecond = 1000, MaxGlobalIncomingCallsPerSecond = 2000, CallTimeout = 3, TransportFastFlushEnabled = true})
local T = NetStream.Types
local Busy = NetStream.Function("__NSRPCBusy43", {Id = 44370, Schema = {T.U16}, Compression = false})
local Report = NetStream.Event("__NSRPCReport43", {Id = 44371, Schema = {T.U16, T.U16}, Compression = false})
local Ack = NetStream.Event("__NSRPCAck43", {Id = 44372, Schema = {T.Bool}, Compression = false})
local complete = {}
Busy:SetCallback(function(player, request)
    assert(request >= 1 and request <= 65535, "RPC request corrupted")
    local snapshot = NetStream.GetRPCStats(player)
    assert(snapshot.Active >= 1 and snapshot.Active <= 2, "In-flight RPC cap exceeded")
    assert(NetStream.GetRPCStats().Active <= 8, "Global in-flight RPC cap exceeded")
    task.wait(0.8)
    return request
end)
Report:Connect(function(player, successful, rejected)
    assert(not complete[player], "RPC report repeated")
    complete[player] = true
    assert(successful + rejected == 16 and successful >= 1 and rejected >= 1, "RPC concurrency probe did not exercise both acceptance and throttling")
    local stats = NetStream.GetRPCStats(player)
    assert(stats.Active == 0 and stats.ConcurrencyDrops >= 1 and stats.PeakActive <= 8 and stats.PerPlayerLimit == 2, "RPC capacity not released or cap was exceeded")
    assert(Ack:FireClient(player, true), "RPC concurrency ACK enqueue failed")
    print("NetStream v4.3.0 RPC concurrency PASS", successful, rejected, stats.ConcurrencyDrops, stats.PeakActive)
end)
Players.PlayerRemoving:Connect(function(player) complete[player] = nil end)
