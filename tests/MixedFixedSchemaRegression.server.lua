--!strict
-- Pair with MixedFixedSchemaRegression.client.lua; run alone in a Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0.05})
local T = NetStream.Types
local Mixed = NetStream.Event("__NSMixedFixed42", {Id = 36420, Compression = false, Schema = {T.Bool, T.U8, T.U16, T.I16, T.U32, T.I32, T.Bool, T.U8, T.U16, T.I16, T.U32, T.I32}})
local Ack = NetStream.Event("__NSMixedFixedAck42", {Id = 36421, Compression = false})
local received = {}
Mixed:Connect(function(player, a, b, c, d, e, f, g, h, j, k, l, m)
    local i = (received[player] or 0) + 1
    received[player] = i
    assert(i <= 40 and j == i, "Mixed schema FIFO or run count corrupted")
    assert(a == (i % 2 == 0) and b == 0 and c == 65535 and d == -32768, "Mixed prefix corrupted")
    assert(e == 4294967295 and f == -2147483648 and g == (i % 2 == 1) and h == 255, "Mixed signed values corrupted")
    assert(k == -i and l == 2147483648 and m == 2147483647, "Mixed suffix corrupted")
    assert(Mixed:FireClient(player, a, b, c, d, e, f, g, h, j, k, l, m), "Mixed echo enqueue failed")
    if i == 40 then
        local stats = NetStream.GetStats()
        assert(stats.BitFrameFixedSchemaRunReads > 0, "Mixed packed-run receive fast path missing")
        assert(stats.BitFrameFixedSchemaFastReads >= 40, "Mixed server fast decoder not exercised")
        assert(stats.DecodeErrors == 0, "Server mixed decode errors")
        assert(Ack:FireClient(player, stats.BitFrameFixedSchemaFastReads), "Mixed ACK enqueue failed")
    end
end)
Players.PlayerRemoving:Connect(function(player) received[player] = nil end)
print("NetStream v4.3.1 mixed schema server ready")
