--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local Limited = NetStream.Event("__NSScalarThrottleHeap", {Id = 36101, Schema = {T.U16}, MaxPerSecond = 1, Burst = 1, Compression = false})
local Ack = NetStream.Event("__NSScalarThrottleAck", {Id = 36102, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(value)
    assert(value == 1, "Unexpected scalar route throttle ACK")
    done = true
    print("NetStream 4.2.0 route scalar throttle PASS")
end)
assert(Limited:FireServerNow(33000), "First scalar send failed")
assert(Limited:FireServerNow(33001), "Second scalar send failed")
task.delay(15, function() assert(done, "Scalar route throttle test timed out") end)
