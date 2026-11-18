--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false, BandwidthGovernorEnabled = true, BandwidthMaxPacketBytes = 48, BandwidthLimitBytesPerSecond = 32768, BandwidthMaxPacketsPerSecond = 240})
local T = NetStream.Types
local Packed = NetStream.Event("__NSPackedBudget", {Id = 35711, Schema = {T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8}, Compression = false})
local Ack = NetStream.Event("__NSPackedBudgetAck", {Id = 35712, Schema = {T.U16}, Compression = false})
local counts = {}
Packed:Connect(function(player, a, b, c, d, e, f, g, h)
    local current = (counts[player] or 0) + 1
    counts[player] = current
    assert(a == current and b == 0 and c == 255 and d == 128 and e == 7 and f == 19 and g == 31 and h == 63, "Packed budget split broke message order")
    if current == 96 then
        assert(NetStream.GetStats().DecodeErrors == 0, "Budget split produced invalid packets")
        assert(Ack:FireClientNow(player, current), "Packed budget ACK failed")
    end
end)
game:GetService("Players").PlayerRemoving:Connect(function(player) counts[player] = nil end)
print("NetStream 4.2.0 packed-budget server ready")
