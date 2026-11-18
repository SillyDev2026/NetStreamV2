--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, PackedSchemaRunEnabled = true, TransportFastFlushEnabled = false, BandwidthGovernorEnabled = true, BandwidthMaxPacketBytes = 48, BandwidthLimitBytesPerSecond = 32768, BandwidthMaxPacketsPerSecond = 240, MaxPooledPackedValues = 16})
local T = NetStream.Types
local Packed = NetStream.Event("__NSPackedHighWaterData", {Id = 36211, Schema = {T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8}, Compression = false})
local Ack = NetStream.Event("__NSPackedHighWaterAck", {Id = 36212, Schema = {T.U8}, Compression = false})
local count = 0
Packed:Connect(function(player, a, b, c, d, e, f, g, h)
    count += 1
    assert(a == count and b == 0 and c == 255 and d == 128 and e == 7 and f == 19 and g == 31 and h == 63, "High-water split corrupted FIFO")
    if count == 96 then
        assert(NetStream.GetStats().DecodeErrors == 0, "Packed high-water packet was malformed")
        assert(Ack:FireClientNow(player, 1), "High-water ACK failed")
    end
end)
print("NetStream v4.2.0 packed high-water server ready")
