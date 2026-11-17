--!strict
-- StarterPlayerScripts LocalScript; pair with BitFrameFloatGuard.server.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.1.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
NetStream.Event("__NSFloatGuard32", {Id = 35401, Schema = {T.F32}, Compression = false})
NetStream.Event("__NSFloatGuardUDim", {Id = 35402, Schema = {T.UDim}, Compression = false})
local Good = NetStream.Event("__NSFloatGuardGood", {Id = 35403, Schema = {T.U8}, Compression = false})
local Ack = NetStream.Event("__NSFloatGuardAck", {Id = 35404, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(value)
    assert(value == 7, "Unexpected float guard acknowledgement")
    done = true
    print("NetStream v4.1.0 non-finite float rejection and recovery PASS")
end)
local remote = ReplicatedStorage:WaitForChild("__NetStream_NetStream"):WaitForChild("R")
local bits = NetStream.TransportCompression
local function malformed(routeId, valueBits, width)
    local size = math.ceil((1 + 2 + 24 + 1 + width + 1) / 8)
    local data = buffer.create(size)
    local pos = 0
    buffer.writebits(data, pos, 1, 1); pos += 1
    buffer.writebits(data, pos, 2, 0); pos += 2
    pos = bits.WriteAdaptiveUIntBits(data, pos, routeId)
    buffer.writebits(data, pos, 1, 0); pos += 1
    buffer.writebits(data, pos, 32, valueBits); pos += 32
    if width == 96 then
        buffer.writebits(data, pos, 32, 0x7FF00000); pos += 32
        buffer.writebits(data, pos, 32, 0); pos += 32
    end
    buffer.writebits(data, pos, 1, 0)
    return data
end
remote:FireServer(malformed(35401, 0x7F800000, 32))
remote:FireServer(malformed(35402, 0, 96))
assert(Good:FireServer(7), "Failed to send valid recovery frame")
task.delay(15, function() assert(done, "Float guard regression timed out") end)
