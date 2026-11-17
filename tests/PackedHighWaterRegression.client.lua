--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, PackedSchemaRunEnabled = true, TransportFastFlushEnabled = false, BandwidthGovernorEnabled = true, BandwidthMaxPacketBytes = 48, BandwidthLimitBytesPerSecond = 32768, BandwidthMaxPacketsPerSecond = 240, MaxPooledPackedValues = 16})
local T = NetStream.Types
local Packed = NetStream.Event("__NSPackedHighWaterData", {Id = 36211, Schema = {T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8}, Compression = false})
local Ack = NetStream.Event("__NSPackedHighWaterAck", {Id = 36212, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(value)
    assert(value == 1, "Packed high-water ACK invalid")
    local stats = NetStream.GetStats()
    assert(stats.PackedValueHighWaterDrops >= 1, "Oversized packed backing tables were retained")
    assert(stats.DecodeErrors == 0, "High-water ACK decode failed")
    done = true
    print("NetStream v4.0.0 packed high-water PASS", stats.PackedValueHighWaterDrops)
end)
NetStream.ResetStats()
for i = 1, 96 do assert(Packed:FireServer(i, 0, 255, 128, 7, 19, 31, 63), "High-water packed enqueue failed") end
NetStream.Flush()
task.delay(30, function() assert(done, "Packed high-water regression timed out") end)
