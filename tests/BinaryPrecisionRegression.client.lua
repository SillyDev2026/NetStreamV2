--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.9.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, HybridSmallPacketMaxBits = 512})
local T = NetStream.Types
local FloatPair = NetStream.Event("__NSBinaryF64", {Id = 35721, Schema = {T.F64, T.F64}, Compression = false})
local Text = NetStream.Event("__NSBinaryHybridText", {Id = 35722, Compression = false})
local Ack = NetStream.Event("__NSBinaryPrecisionAck", {Id = 35723, Schema = {T.U16}, Compression = false})
local done = false
Ack:Connect(function(count)
    assert(count == 80, "Binary precision packets were lost")
    done = true
    print("NetStream 2.9.0 binary precision PASS")
end)
for i = 1, 80 do
    assert(FloatPair:FireServer(i * 0.125 - 20, 1 / (i + 1)), "F64 enqueue failed")
end
for _, value in ipairs({"", "A", "ABCDEFG", string.rep("x", 15), string.rep("z", 31)}) do
    assert(Text:FireServer(value), "Hybrid text enqueue failed")
end
NetStream.Flush()
task.delay(20, function() assert(done, "Binary precision regression timed out") end)
