--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.2.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false})
local T = NetStream.Types
local Packed = NetStream.Event("__NSMemoryPacked", {Id = 35601, Schema = {T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8}, Compression = false})
local String = NetStream.Event("__NSMemoryString", {Id = 35602, Schema = {T.String}, Compression = false})
local Ack = NetStream.Event("__NSMemoryAck", {Id = 35603, Schema = {T.U8}, Compression = false})
local packedCount = 0
local stringCount = 0
local expected = {string.rep("q", 16), string.rep("w", 32), string.rep("z", 63)}
local function maybeFinish(player)
    if packedCount ~= 96 or stringCount ~= 3 then return end
    local stats = NetStream.GetStats()
    assert(stats.U8SchemaFastReads >= 96, "Expected packed U8 binary reader path")
    assert(Ack:FireClientNow(player, 99), "Memory bit-path ACK could not be sent")
end
Packed:Connect(function(player, a, b, c, d, e, f, g, h)
    packedCount += 1
    assert(a == packedCount and b == 0 and c == 255 and d == 128 and e == 7 and f == 19 and g == 31 and h == 63, "Packed U8 fields changed")
    maybeFinish(player)
end)
String:Connect(function(player, value)
    stringCount += 1
    assert(value == expected[stringCount], "Unaligned binary string did not round-trip")
    maybeFinish(player)
end)
print("NetStream v3.2.0 memory/binary regression server ready")
