--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.9.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local Dynamic = NetStream.Event("__NSRejectedDynamicHeap", {Id = 36111, Compression = false})
local Ack = NetStream.Event("__NSRejectedDynamicAck", {Id = 36112, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(value)
    assert(value == 1, "Unexpected dynamic reject ACK")
    done = true
    print("NetStream 3.9.0 dynamic reject PASS")
end)
assert(Dynamic:FireServerNow(123, "initial"), "Accepted dynamic message send failed")
assert(Dynamic:FireServerNow(999, "rejected"), "Rejected dynamic message send failed")
task.delay(15, function() assert(done, "Dynamic reject heap test timed out") end)
