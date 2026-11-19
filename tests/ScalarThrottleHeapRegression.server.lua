--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local Limited = NetStream.Event("__NSScalarThrottleHeap", {Id = 36101, Schema = {T.U16}, MaxPerSecond = 1, Burst = 1, Compression = false})
local Ack = NetStream.Event("__NSScalarThrottleAck", {Id = 36102, Schema = {T.U8}, Compression = false})
local received = 0
Limited:Connect(function(player, value)
    received += 1
    assert(value == 33000 and received == 1, "Route-level scalar rate limit corrupted the accepted value")
    task.delay(2, function()
        assert(received == 1, "Route-level rate limit delivered an extra scalar")
        local stats = NetStream.GetStats()
        assert(stats.DecodeErrors == 0, "Dropped scalar triggered a decoder or releaseArgs error")
        assert(Ack:FireClientNow(player, 1), "Scalar route throttle ACK failed")
        print("NetStream 4.3.1 route scalar throttle PASS", stats.RouteRateLimited)
    end)
end)
print("NetStream 4.3.1 route scalar throttle server ready")
