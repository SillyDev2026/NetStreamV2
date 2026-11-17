--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.1.0")
NetStream.Configure({BitFrameEnabled = false, HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local Probe = NetStream.Event("__NSLegacyFiniteProbe", {Id = 35451, Schema = {T.UDim, T.U8}, Compression = false})
local Ack = NetStream.Event("__NSLegacyFiniteAck", {Id = 35452, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(marker)
    assert(marker == 7, "Legacy float guard ACK corrupted")
    done = true
    print("NetStream v4.1.0 legacy fixed-schema finite guard PASS")
end)
local remote = ReplicatedStorage:WaitForChild("__NetStream_NetStream"):WaitForChild("R")
local function malformed(highBits)
    local routeTag = 35451 * 4
    local data = buffer.create(17)
    buffer.writeu8(data, 0, 0x33)
    local pos = 1
    repeat
        local byte = routeTag % 128
        routeTag = math.floor(routeTag / 128)
        if routeTag > 0 then byte += 128 end
        buffer.writeu8(data, pos, byte)
        pos += 1
    until routeTag == 0
    assert(pos == 4, "Unexpected legacy route-tag length")
    buffer.writeu32(data, pos, 0)
    buffer.writeu32(data, pos + 4, highBits)
    buffer.writei32(data, pos + 8, 3)
    buffer.writeu8(data, pos + 12, 7)
    return data
end
remote:FireServer(malformed(0x7FF00000))
remote:FireServer(malformed(0xFFF00000))
remote:FireServer(malformed(0x7FF80000))
assert(Probe:FireServerNow(UDim.new(0.5, 3), 7), "Valid legacy packet could not be queued")
task.delay(15, function() assert(done, "Legacy fixed-schema finite guard timed out") end)
