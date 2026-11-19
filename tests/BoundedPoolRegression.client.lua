--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, MaxArgsPoolSize = 0, MaxMessagePoolSize = 0, MaxPooledBatchItems = 0})
local T = NetStream.Types
local Pulse = NetStream.Event("__NSBoundedPoolPulse", {Id = 36121, Schema = {T.U8}, Compression = false})
local Ack = NetStream.Event("__NSBoundedPoolAck", {Id = 36122, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(value)
    assert(value == 1, "Unexpected bounded pool ACK")
    local stats = NetStream.GetStats()
    assert(stats.BatchPoolSize == 0 and stats.MessagePoolSize == 0 and stats.ArgsPoolSize == 0, "Idle pools retained objects with a zero cap")
    assert(stats.BatchPoolOversizeDrops >= 1, "Oversized batch discard path was not exercised")
    done = true
    print("NetStream 4.4.0 bounded pool PASS", stats.BatchPoolOversizeDrops)
end)
for i = 1, 16 do assert(Pulse:FireServer(i), "Bounded pool enqueue failed") end
NetStream.Flush()
task.delay(20, function() assert(done, "Bounded pool regression timed out") end)
