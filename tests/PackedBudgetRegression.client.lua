--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false, BandwidthGovernorEnabled = true, BandwidthMaxPacketBytes = 48, BandwidthLimitBytesPerSecond = 32768, BandwidthMaxPacketsPerSecond = 240})
local T = NetStream.Types
local Packed = NetStream.Event("__NSPackedBudget", {Id = 35711, Schema = {T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8}, Compression = false})
local Ack = NetStream.Event("__NSPackedBudgetAck", {Id = 35712, Schema = {T.U16}, Compression = false})
local done = false
Ack:Connect(function(count)
    assert(count == 96, "Packed budget lost logical messages")
    local stats = NetStream.GetStats()
    assert(stats.BandwidthBatchSplits > 0, "Expected packet byte-budget splits")
    assert(stats.DecodeErrors == 0, "ACK decode failed")
    done = true
    print("NetStream 4.0.0 packed-budget PASS", count, stats.BandwidthBatchSplits, stats.PackedRunBatchSplits)
end)
NetStream.ResetStats()
for i = 1, 96 do assert(Packed:FireServer(i, 0, 255, 128, 7, 19, 31, 63), "Failed to queue packed event") end
NetStream.Flush()
task.delay(30, function() assert(done, "Packed budget regression timed out") end)
