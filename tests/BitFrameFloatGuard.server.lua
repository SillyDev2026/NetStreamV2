--!strict
-- ServerScriptService Script; pair with BitFrameFloatGuard.client.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.2")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local F32 = NetStream.Event("__NSFloatGuard32", {Id = 35401, Schema = {T.F32}, Compression = false})
local UDim = NetStream.Event("__NSFloatGuardUDim", {Id = 35402, Schema = {T.UDim}, Compression = false})
local Good = NetStream.Event("__NSFloatGuardGood", {Id = 35403, Schema = {T.U8}, Compression = false})
local Ack = NetStream.Event("__NSFloatGuardAck", {Id = 35404, Schema = {T.U8}, Compression = false})
F32:Connect(function() error("Malformed non-finite F32 reached a callback") end)
UDim:Connect(function() error("Malformed non-finite UDim scale reached a callback") end)
Good:Connect(function(player, value)
    assert(value == 7, "Valid frame was corrupted")
    assert(NetStream.GetStats().DecodeErrors >= 2, "Two malformed float frames were not rejected")
    assert(Ack:FireClient(player, value), "Could not send float guard acknowledgement")
end)
print("NetStream v4.0.2 non-finite BitFrame guard server ready")
