--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.2.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, MaxBitFrameStagePoolSize = 0, MaxPooledBitFrameActions = 2})
local T = NetStream.Types
local Scalar = NetStream.Event("__NSStagePoolScalar", {Id = 35911, Schema = {T.U8}, Compression = false})
local Ack = NetStream.Event("__NSStagePoolAck", {Id = 35912, Schema = {T.U8}, Compression = false})
local count = 0
Scalar:Connect(function(player, value)
    count += 1
    assert(value == count, "Scalar delivery sequence corrupted")
    local memory = NetStream.GetMemoryDiagnostics()
    assert(memory.BitFrameStagePoolSize == 0, "Stage objects must not be retained with pool cap zero")
    assert(memory.MaxBitFrameStagePoolSize == 0, "Stage pool cap not applied")
    if count == 16 then
        assert(Ack:FireClientNow(player, 1), "Stage pool memory ACK failed")
        print("NetStream 3.2.0 stage pool memory PASS", memory.BitFrameStagePoolSize)
    end
end)
