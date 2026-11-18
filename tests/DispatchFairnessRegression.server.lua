--!strict
-- ServerScriptService; pair with DispatchFairnessRegression.client.lua in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.0")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0.1, MaxBatchMessages = 256, MaxDispatchPerCycle = 1, MaxDispatchBacklog = 64, DispatchPerPlayerBacklogLimit = 12, DispatchBudgetCheckInterval = 1})
local T = NetStream.Types
local Ready = NetStream.Event("__NSDispatchReady43", {Id = 44301, Schema = {T.Bool}, Compression = false})
local Burst = NetStream.Event("__NSDispatchBurst43", {Id = 44302, Schema = {T.U16}, Compression = false})
local Ack = NetStream.Event("__NSDispatchAck43", {Id = 44303, Schema = {T.U16, T.U16}, Compression = false})
local seen = {}
local started = {}
Burst:Connect(function(player, sequence)
    assert(sequence >= 1 and sequence <= 160, "Dispatch corrupted incoming payload")
    seen[player] = (seen[player] or 0) + 1
end)
Ready:Connect(function(player, ready)
    assert(ready and not started[player], "Dispatch setup failed")
    started[player] = true
    task.delay(4, function()
        if not player.Parent then return end
        local stats = NetStream.GetStats()
        local pending = NetStream.GetDispatchStats(player)
        assert(stats.DispatchPerPlayerDrops > 0, "Per-player dispatch protection did not engage")
        assert(stats.DispatchPeakBacklog <= 12, "Noisy client exceeded per-player dispatch cap")
        assert(pending.Backlog == 0 and pending.PerPlayerLimit == 12 and pending.BudgetCheckInterval == 1, "Dispatch queue did not drain")
        assert((seen[player] or 0) > 0, "No valid messages were delivered")
        assert(Ack:FireClient(player, seen[player], stats.DispatchPerPlayerDrops), "Dispatch ACK failed")
        print("NetStream v4.3.0 dispatch server PASS", seen[player], stats.DispatchPerPlayerDrops)
    end)
end)
