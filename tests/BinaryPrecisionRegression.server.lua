--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.5.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, HybridSmallPacketMaxBits = 512})
local T = NetStream.Types
local FloatPair = NetStream.Event("__NSBinaryF64", {Id = 35721, Schema = {T.F64, T.F64}, Compression = false})
local Text = NetStream.Event("__NSBinaryHybridText", {Id = 35722, Compression = false})
local Ack = NetStream.Event("__NSBinaryPrecisionAck", {Id = 35723, Schema = {T.U16}, Compression = false})
local floatCount = 0
local textCount = 0
local expected = {"", "A", "ABCDEFG", string.rep("x", 15), string.rep("z", 31)}
local function maybeFinish(player)
    if floatCount ~= 80 or textCount ~= #expected then return end
    assert(NetStream.GetStats().DecodeErrors == 0, "Binary precision frame decoded incorrectly")
    assert(Ack:FireClientNow(player, floatCount), "Binary precision ACK failed")
end
FloatPair:Connect(function(player, a, b)
    floatCount += 1
    assert(a == floatCount * 0.125 - 20 and b == 1 / (floatCount + 1), "F64 bit values changed")
    maybeFinish(player)
end)
Text:Connect(function(player, value)
    textCount += 1
    assert(value == expected[textCount], "Hybrid small string changed")
    maybeFinish(player)
end)
print("NetStream 3.5.0 binary precision server ready")
