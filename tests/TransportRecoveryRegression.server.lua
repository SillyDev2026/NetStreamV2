--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.2")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, PackedSchemaRunEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0, BandwidthGovernorEnabled = true, BandwidthLimitBytesPerSecond = 64000, BandwidthMaxPacketsPerSecond = 1, MaxBatchMessages = 64})
local T = NetStream.Types
local Event = NetStream.Event("__NSIsolatedRecovery", {Id = 37041, Schema = {T.U16}, Compression = false, Trusted = true})
local Ack = NetStream.Event("__NSIsolatedRecoveryAck", {Id = 37042, Schema = {T.U16}, Compression = false})
local counts = {}
Event:Connect(function(player, value)
	local count = (counts[player] or 0) + 1
	counts[player] = count
	assert(count <= 3 and value == count, "Recovery changed reliable FIFO order or payload")
	if count == 3 then
		assert(Ack:FireClientNow(player, count), "Recovery ACK failed")
		print("NetStream 4.0.2 isolated defer recovery SERVER PASS")
	end
end)
Players.PlayerRemoving:Connect(function(player) counts[player] = nil end)
print("NetStream 4.0.2 isolated recovery server ready")
