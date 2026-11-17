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
local tinyCount = 0
local u8Count = 0
local boolCount = 0
local stateCount = 0
local tinyExpected = {[2] = true, [3] = false, [4] = 0, [5] = 127, [6] = 128, [7] = -1, [8] = "tiny"}
local function complete(player)
    if tinyCount ~= 8 or u8Count ~= 3 or boolCount ~= 2 or stateCount ~= 1 then return end
    assert(NetStream.GetStateSnapshot(player)[ScalarState.Id] == 173, "Scalar state corrupted")
    local stats = NetStream.GetStats()
    assert(stats.ScalarDispatches >= 14, "Atomic scalar fast dispatch was not exercised")
    assert(Ack:FireClientNow(player, 1), "Scalar fast path ACK failed")
end
Tiny:Connect(function(player, value)
    tinyCount += 1
    assert(value == tinyExpected[tinyCount], "Tiny dynamic scalar changed")
    complete(player)
end)
ScalarU8:Connect(function(player, value)
    u8Count += 1
    assert(value == ({0, 128, 255})[u8Count], "Single U8 schema changed")
    complete(player)
end)
ScalarBool:Connect(function(player, value)
    boolCount += 1
    assert(value == (boolCount == 1), "Single boolean schema changed")
    complete(player)
end)
ScalarState:Connect(function(player, value)
    stateCount += 1
    assert(value == 173, "Single U8 state value changed")
    complete(player)
end)
print("NetStream v4.0.0 scalar staging server ready")
