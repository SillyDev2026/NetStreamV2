--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.3")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local State = NetStream.State("__NSAtomicState", {Id = 35801, Schema = {T.U8}, Compression = false})
local Ack = NetStream.Event("__NSAtomicAck", {Id = 35802, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(code)
    assert(code == 1, "Atomic packet test returned an unexpected ACK")
    done = true
    print("NetStream v4.2.3 atomic packet PASS")
end)
local remote = ReplicatedStorage:WaitForChild("__NetStream_NetStream"):WaitForChild("R")
assert(remote:IsA("RemoteEvent"), "Reliable NetStream remote missing")
local malformed = buffer.create(5)
local position = 0
buffer.writebits(malformed, position, 1, 1)
position += 1
buffer.writebits(malformed, position, 2, 3)
position += 2
local routeId = 35801
repeat
    local byte = routeId % 128
    routeId = math.floor(routeId / 128)
    if routeId > 0 then byte += 128 end
    buffer.writebits(malformed, position, 8, byte)
    position += 8
until routeId == 0
buffer.writebits(malformed, position, 8, 99)
position += 8
buffer.writebits(malformed, position, 1, 0)
position += 1
buffer.writebits(malformed, position, 1, 1)
remote:FireServer(malformed)
task.wait(0.2)
assert(State:SetServerNow(25), "Valid state update failed after malformed packet")
task.delay(20, function() assert(done, "Atomic packet regression timed out") end)
