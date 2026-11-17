--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.9.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false, MaxIncomingMessagesPerSecond = 1})
local T = NetStream.Types
local Dynamic = NetStream.Event("__NSRejectedDynamicHeap", {Id = 36111, Compression = false})
local Ack = NetStream.Event("__NSRejectedDynamicAck", {Id = 36112, Schema = {T.U8}, Compression = false})
local received = 0
Dynamic:Connect(function(player, first, second)
    received += 1
    assert(received == 1 and first == 123 and second == "initial", "Initial dynamic message corrupted")
    task.delay(2, function()
        assert(received == 1, "Globally rejected dynamic packet was dispatched")
        local stats = NetStream.GetStats()
        assert(stats.BitFrameRejectedDynamicArgsAvoided >= 1, "Dynamic reject path still allocated an argument array")
        assert(stats.DecodeErrors == 0, "Valid rejected dynamic packet failed framing")
        assert(Ack:FireClientNow(player, 1), "Dynamic reject ACK failed")
        print("NetStream 3.9.0 dynamic discard PASS", stats.BitFrameRejectedDynamicArgsAvoided)
    end)
end)
print("NetStream 3.9.0 dynamic reject server ready")
