--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.9.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false})
local T = NetStream.Types
local Scalar = NetStream.Event("__NSStagePoolScalar", {Id = 35911, Schema = {T.U8}, Compression = false})
local Ack = NetStream.Event("__NSStagePoolAck", {Id = 35912, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(marker)
    assert(marker == 1, "Invalid stage memory test ACK")
    done = true
    print("NetStream 3.9.0 stage pool memory PASS")
end)
for i = 1, 16 do assert(Scalar:FireServer(i), "Scalar message enqueue failed") end
NetStream.Flush()
task.delay(15, function() assert(done, "Stage pool memory regression timed out") end)
