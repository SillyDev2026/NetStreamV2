--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local U16 = NetStream.Event("__NSScalarU16", {Id = 36011, Schema = {T.U16}, Compression = false})
local I16 = NetStream.Event("__NSScalarI16", {Id = 36012, Schema = {T.I16}, Compression = false})
local U32 = NetStream.Event("__NSScalarU32", {Id = 36013, Schema = {T.U32}, Compression = false})
local I32 = NetStream.Event("__NSScalarI32", {Id = 36014, Schema = {T.I32}, Compression = false})
local F32 = NetStream.Event("__NSScalarF32", {Id = 36015, Schema = {T.F32}, Compression = false})
local F64 = NetStream.Event("__NSScalarF64", {Id = 36016, Schema = {T.F64}, Compression = false})
local Text = NetStream.Event("__NSShortBinaryText", {Id = 36017, Schema = {T.String}, Compression = false})
local State = NetStream.State("__NSScalarStateF64", {Id = 36018, Schema = {T.F64}, Compression = false})
local Ack = NetStream.Event("__NSScalarExtendedAck", {Id = 36019, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(value)
    assert(value == 1, "Unexpected extended scalar ACK")
    done = true
    print("NetStream 4.4.0 scalar/string PASS")
end)
assert(U16:FireServer(65000), "U16 enqueue failed")
assert(I16:FireServer(-12345), "I16 enqueue failed")
assert(U32:FireServer(4000000000), "U32 enqueue failed")
assert(I32:FireServer(-2000000000), "I32 enqueue failed")
assert(F32:FireServer(0.75), "F32 enqueue failed")
assert(F64:FireServer(-42.125), "F64 enqueue failed")
assert(State:SetServer(6.25), "F64 state enqueue failed")
for _, value in ipairs({"", "A", string.char(0, 255), string.rep("x", 7), string.rep("y", 15), string.rep("z", 16), string.rep("q", 31)}) do
    assert(Text:FireServer(value), "Short binary string enqueue failed")
end
NetStream.Flush()
task.delay(20, function() assert(done, "Extended scalar/string regression timed out") end)
