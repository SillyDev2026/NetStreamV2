--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.8.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local Bytes = NetStream.Event("__NSHeapDiscardBytes", {Id = 35901, Schema = {T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8}, Compression = false})
local Bools = NetStream.Event("__NSHeapDiscardBools", {Id = 35902, Schema = {T.Bool, T.Bool, T.Bool}, Compression = false})
local Ack = NetStream.Event("__NSHeapDiscardAck", {Id = 35903, Schema = {T.U8}, Compression = false})
local completed = false
Ack:Connect(function(code)
    assert(code == 1, "Unexpected heap discard ACK")
    completed = true
    print("NetStream 3.8.0 heap discard PASS")
end)
assert(Bytes:FireServerNow(1, 2, 3, 4, 5, 6, 7, 8), "First U8 event failed")
assert(Bytes:FireServerNow(9, 10, 11, 12, 13, 14, 15, 16), "Second U8 event failed")
assert(Bools:FireServerNow(true, false, true), "Packed boolean event failed")
task.delay(15, function() assert(completed, "Heap discard test timed out") end)
