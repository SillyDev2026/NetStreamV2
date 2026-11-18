--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.3")
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
local expectedText = {"", "A", string.char(0, 255), string.rep("x", 7), string.rep("y", 15), string.rep("z", 16), string.rep("q", 31)}
local received = 0
local textCount = 0
local scalarCount = 0
local function complete(player)
    if received ~= 14 then return end
    assert(scalarCount == 7 and textCount == #expectedText, "Extended scalar/string test counts were incorrect")
    assert(NetStream.GetStateSnapshot(player)[State.Id] == 6.25, "Scalar F64 state was corrupted")
    local stats = NetStream.GetStats()
    assert(stats.BitFrameScalarSchemaReads >= 7, "Extended single-field scalar path was not executed")
    assert(stats.DecodeErrors == 0, "Extended scalar/string packets failed to decode")
    assert(Ack:FireClientNow(player, 1), "Extended scalar ACK failed")
    print("NetStream 4.2.3 scalar/string PASS", stats.BitFrameScalarSchemaReads)
end
local function scalarCheck(player, value, expected)
    assert(value == expected, "Single numeric schema value changed")
    received += 1
    scalarCount += 1
    complete(player)
end
U16:Connect(function(player, value) scalarCheck(player, value, 65000) end)
I16:Connect(function(player, value) scalarCheck(player, value, -12345) end)
U32:Connect(function(player, value) scalarCheck(player, value, 4000000000) end)
I32:Connect(function(player, value) scalarCheck(player, value, -2000000000) end)
F32:Connect(function(player, value) scalarCheck(player, value, 0.75) end)
F64:Connect(function(player, value) scalarCheck(player, value, -42.125) end)
State:Connect(function(player, value) scalarCheck(player, value, 6.25) end)
Text:Connect(function(player, value)
    textCount += 1
    received += 1
    assert(value == expectedText[textCount], "Short binary string data changed")
    complete(player)
end)
print("NetStream 4.2.3 scalar/string server ready")
