--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.9.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, PackedSchemaRunEnabled = true, TransportFastFlushEnabled = false})
local T = NetStream.Types
local Numbers = NetStream.Event("__NSPackedScalarNumbers", {Id = 36201, Schema = {T.U16}, Compression = false})
local Bools = NetStream.Event("__NSPackedScalarBools", {Id = 36202, Schema = {T.Bool}, Compression = false})
local Ack = NetStream.Event("__NSPackedScalarAck", {Id = 36203, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(value)
    assert(value == 1, "Packed scalar ACK invalid")
    done = true
    print("NetStream v3.9.0 packed scalar run PASS")
end)
for i = 1, 40 do assert(Numbers:FireServer(60000 - i), "Packed U16 send failed") end
for i = 1, 40 do assert(Bools:FireServer(i % 2 == 1), "Packed Bool send failed") end
NetStream.Flush()
task.delay(20, function() assert(done, "Packed scalar run regression timed out") end)
