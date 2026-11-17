--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.5.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local SchemaState = NetStream.State("__NSRateSchemaState", {Id = 35701, Schema = {T.U8}, Compression = false})
local DynamicState = NetStream.State("__NSRateDynamicState", {Id = 35702, Compression = false})
local Ack = NetStream.Event("__NSRateStateAck", {Id = 35703, Schema = {T.U8}, Compression = false})
local done = false
Ack:Connect(function(code)
    assert(code == 1, "Unexpected state throttle result")
    done = true
    print("NetStream 3.5.0 state throttle PASS")
end)
assert(SchemaState:SetServer(11), "Failed to queue first schema state")
assert(SchemaState:SetServer(22), "Failed to queue second schema state")
assert(DynamicState:SetServer("first"), "Failed to queue first dynamic state")
assert(DynamicState:SetServer("blocked"), "Failed to queue second dynamic state")
NetStream.Flush()
task.delay(20, function() assert(done, "State throttle regression timed out") end)
