--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local First = NetStream.Event("__NSFixedDiscardFirst", {Id = 36001, Schema = {T.U8}, Compression = false})
local Mixed = NetStream.Event("__NSFixedDiscardMixed", {Id = 36002, Schema = {T.Bool, T.U8, T.U16, T.I16, T.U32, T.I32, T.Color3}, Compression = false})
local Float = NetStream.Event("__NSFixedDiscardFloat", {Id = 36003, Schema = {T.F32, T.U8}, Compression = false})
local Ack = NetStream.Event("__NSFixedDiscardAck", {Id = 36004, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(value)
    assert(value == 1, "Unexpected fixed discard ACK")
    done = true
    print("NetStream 4.4.0 fixed discard PASS")
end)
assert(First:FireServerNow(9), "Failed to send accepted first event")
assert(Mixed:FireServerNow(true, 3, 65000, -12345, 4000000000, -2000000000, Color3.fromRGB(12, 36, 250)), "Failed to send rejected mixed event")
assert(Float:FireServerNow(0.75, 23), "Failed to send rejected float event")
task.delay(15, function() assert(done, "Fixed discard regression timed out") end)
