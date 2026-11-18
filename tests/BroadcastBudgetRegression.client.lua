--!strict
-- StarterPlayerScripts; pair with BroadcastBudgetRegression.server.lua in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.0")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0.1, BroadcastFlushBudgetFraction = 0.25, MaxBatchesPerFlush = 2, MaxBatchMessages = 128})
local T = NetStream.Types
local Ready = NetStream.Event("__NSBroadcastReady43", {Id = 44311, Schema = {T.Bool}, Compression = false})
local Payload = NetStream.Event("__NSBroadcastPayload43", {Id = 44312, Schema = {T.U16}, Compression = false})
local Ack = NetStream.Event("__NSBroadcastAck43", {Id = 44313, Schema = {T.U16}, Compression = false})
local seen = 0
local done = false
Payload:Connect(function(value)
    assert(value >= 1 and value <= 80, "Broadcast packet payload corrupted")
    seen += 1
end)
Ack:Connect(function(slices)
    assert(slices > 0 and seen > 0, "Broadcast processing did not reserve targeted time or transmit")
    done = true
    print("NetStream v4.3.0 broadcast CLIENT PASS", slices, seen)
end)
assert(Ready:FireServerNow(true), "Broadcast ready failed")
task.delay(12, function() assert(done, "Broadcast budget regression timed out") end)
