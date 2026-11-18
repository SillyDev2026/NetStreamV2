--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

NetStream.ConfigureLowTraffic({HandshakeEnabled = false, BandwidthGovernorEnabled = false, PacketSizeAuditEnabled = true, TransportFastFlushEnabled = false})
assert(NetStream.GetVersion() == "4.2.0")

local Ping32 = NetStream.Event("__PacketAuditU32", {Id = 1001, Schema = {T.U32}, Priority = "Normal", Compression = false})
local Ping16 = NetStream.Event("__PacketAuditU16", {Id = 1002, Schema = {T.U16}, Priority = "Normal", Compression = false})
local PingShort = NetStream.Event("__PacketAuditShort", {Id = 1, Schema = {T.U16}, Priority = "Normal", Compression = false})

local received = 0
Ping32:Connect(function(player, value)
	assert(value == 65538, "U32 payload corruption")
	received += 1
end)
Ping16:Connect(function(player, value)
	assert(value >= 17 and value <= 25, "U16 payload corruption")
	received += 1
end)
PingShort:Connect(function(player, value)
	assert(value == 19, "Short route payload corruption")
	received += 1
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	print("NetStream 4.2.0 Packet Audit server observed", received, "logical messages", player.UserId)
end)
