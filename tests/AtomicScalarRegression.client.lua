--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local Tiny = NetStream.Event("__NSAtomicTiny", {Id = 35811, Compression = false})
local ScalarU8 = NetStream.Event("__NSAtomicScalarU8", {Id = 35812, Schema = {T.U8}, Compression = false})
local ScalarBool = NetStream.Event("__NSAtomicScalarBool", {Id = 35813, Schema = {T.Bool}, Compression = false})
local ScalarState = NetStream.State("__NSAtomicScalarState", {Id = 35814, Schema = {T.U8}, Compression = false})
local Ack = NetStream.Event("__NSAtomicScalarAck", {Id = 35815, Schema = {T.U8}, Compression = false})
local completed = false
Ack:Connect(function(code)
    assert(code == 1, "Unexpected scalar staging ACK")
    completed = true
    print("NetStream v4.0.0 scalar staging PASS")
end)
assert(Tiny:FireServerNow(nil), "Nil scalar event failed")
for _, value in ipairs({true, false, 0, 127, 128, -1, "tiny"}) do
    assert(Tiny:FireServerNow(value), "Dynamic scalar event failed")
end
assert(ScalarU8:FireServerNow(0), "U8 zero failed")
assert(ScalarU8:FireServerNow(128), "U8 middle failed")
assert(ScalarU8:FireServerNow(255), "U8 max failed")
assert(ScalarBool:FireServerNow(true), "Boolean true failed")
assert(ScalarBool:FireServerNow(false), "Boolean false failed")
assert(ScalarState:SetServerNow(173), "Scalar state failed")
task.delay(20, function() assert(completed, "Scalar staging regression timed out") end)
