--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, PackedSchemaRunEnabled = true, TransportFastFlushEnabled = false})
local T = NetStream.Types
local Numbers = NetStream.Event("__NSPackedScalarNumbers", {Id = 36201, Schema = {T.U16}, Compression = false})
local Bools = NetStream.Event("__NSPackedScalarBools", {Id = 36202, Schema = {T.Bool}, Compression = false})
local Ack = NetStream.Event("__NSPackedScalarAck", {Id = 36203, Schema = {T.U8}, Compression = false})
local numberCount = 0
local boolCount = 0
local finished = false
local function complete(player)
    if finished or numberCount ~= 40 or boolCount ~= 40 then return end
    finished = true
    local stats = NetStream.GetStats()
    assert(stats.BitFramePackedScalarRunItems >= 40, "Expected packed one-field scalar run decode")
    assert(stats.DecodeErrors == 0, "Packed scalar run must not corrupt framing")
    assert(Ack:FireClientNow(player, 1), "Packed scalar ACK failed")
    print("NetStream v4.2.0 packed scalar run PASS", stats.BitFramePackedScalarRunItems)
end
Numbers:Connect(function(player, value)
    numberCount += 1
    assert(value == 60000 - numberCount, "U16 packed scalar order changed")
    complete(player)
end)
Bools:Connect(function(player, value)
    boolCount += 1
    assert(value == (boolCount % 2 == 1), "Bool packed scalar order changed")
    complete(player)
end)
print("NetStream v4.2.0 packed scalar server ready")
