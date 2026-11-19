--!strict
-- StarterPlayerScripts; pair with DispatchFairnessRegression.server.lua in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0.1, MaxBatchMessages = 256, MaxDispatchPerCycle = 1, MaxDispatchBacklog = 64, DispatchPerPlayerBacklogLimit = 12, DispatchBudgetCheckInterval = 1})
local T = NetStream.Types
local Ready = NetStream.Event("__NSDispatchReady43", {Id = 44301, Schema = {T.Bool}, Compression = false})
local Burst = NetStream.Event("__NSDispatchBurst43", {Id = 44302, Schema = {T.U16}, Compression = false})
local Ack = NetStream.Event("__NSDispatchAck43", {Id = 44303, Schema = {T.U16, T.U16}, Compression = false})
local finished = false
Ack:Connect(function(delivered, dropped)
    assert(delivered >= 1 and delivered <= 160, "Invalid delivered count")
    assert(dropped > 0, "Per-player cap did not discard excess pending callbacks")
    finished = true
    print("NetStream v4.3.1 dispatch client PASS", delivered, dropped)
end)
assert(Ready:FireServerNow(true), "Dispatch ready handshake failed")
task.wait(1)
for index = 1, 160 do assert(Burst:FireServer(index), "Dispatch burst enqueue failed") end
NetStream.Flush()
task.delay(12, function() assert(finished, "Dispatch regression timed out") end)
