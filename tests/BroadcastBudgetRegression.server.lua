--!strict
-- ServerScriptService; pair with BroadcastBudgetRegression.client.lua in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0.1, BroadcastFlushBudgetFraction = 0.25, MaxBatchesPerFlush = 2, MaxBatchMessages = 128})
local T = NetStream.Types
local Ready = NetStream.Event("__NSBroadcastReady43", {Id = 44311, Schema = {T.Bool}, Compression = false})
local Payload = NetStream.Event("__NSBroadcastPayload43", {Id = 44312, Schema = {T.U16}, Compression = false})
local Ack = NetStream.Event("__NSBroadcastAck43", {Id = 44313, Schema = {T.U16}, Compression = false})
local started = {}
Ready:Connect(function(player, ready)
    assert(ready and not started[player], "Broadcast test ready invalid")
    started[player] = true
    for index = 1, 80 do
        assert(Payload:FireAll(index), "Broadcast enqueue failed")
        assert(Payload:FireClient(player, index), "Individual-target enqueue failed")
    end
    NetStream.Flush()
    task.delay(2, function()
        if not player.Parent then return end
        local stats = NetStream.GetStats()
        assert(stats.BroadcastBudgetSlices > 0, "Broadcast consumed full budget without reserving targeted time")
        assert(Ack:FireClient(player, stats.BroadcastBudgetSlices), "Broadcast ACK enqueue failed")
        print("NetStream v4.4.0 broadcast scheduler PASS", stats.BroadcastBudgetSlices)
    end)
end)
