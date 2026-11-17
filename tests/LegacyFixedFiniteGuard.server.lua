--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.1")
NetStream.Configure({BitFrameEnabled = false, HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local Probe = NetStream.Event("__NSLegacyFiniteProbe", {Id = 35451, Schema = {T.UDim, T.U8}, Compression = false})
local Ack = NetStream.Event("__NSLegacyFiniteAck", {Id = 35452, Schema = {T.U8}, Compression = false})
local accepted = 0
Probe:Connect(function(player, udim, marker)
    accepted += 1
    assert(accepted == 1, "Malformed fixed-schema float reached callback")
    assert(udim.Scale == 0.5 and udim.Offset == 3 and marker == 7, "Good legacy payload corrupted")
    assert(NetStream.GetStats().DecodeErrors >= 3, "Expected three malformed floats to be rejected")
    assert(Ack:FireClientNow(player, marker), "Legacy guard ACK failed")
end)
print("NetStream v4.0.1 legacy fixed-schema finite guard ready")
