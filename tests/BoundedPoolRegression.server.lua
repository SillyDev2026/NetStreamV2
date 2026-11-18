--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.3")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, MaxArgsPoolSize = 0, MaxMessagePoolSize = 0, MaxPooledBatchItems = 0})
local T = NetStream.Types
local Pulse = NetStream.Event("__NSBoundedPoolPulse", {Id = 36121, Schema = {T.U8}, Compression = false})
local Ack = NetStream.Event("__NSBoundedPoolAck", {Id = 36122, Schema = {T.U8}, Compression = false})
local received = 0
Pulse:Connect(function(player, value)
    received += 1
    assert(value == received, "Bounded pool traffic changed event order")
    if received == 16 then
        local stats = NetStream.GetStats()
        local memory = NetStream.GetMemoryDiagnostics()
        assert(stats.DecodeErrors == 0, "Bounded pools caused a decoder error")
        assert(stats.ArgsPoolSize == 0 and stats.MessagePoolSize == 0 and stats.BatchPoolSize == 0, "Zero-size idle pool limits were ignored")
        assert(memory.MaxPooledBatchItems == 0 and memory.MaxArgsPoolSize == 0 and memory.MaxMessagePoolSize == 0, "Pool configuration diagnostics inaccurate")
        assert(Ack:FireClientNow(player, 1), "Bounded pool ACK failed")
        print("NetStream 4.2.3 zero-retention pool PASS", memory.MaxPooledBatchItems)
    end
end)
print("NetStream 4.2.3 zero-retention pool server ready")
