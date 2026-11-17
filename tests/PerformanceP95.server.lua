--!strict
-- Use as a standalone Script in ServerScriptService. Netstream with child Compression in ReplicatedStorage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.2.0", "Expected NetStream 3.2.0")
NetStream.Configure({
	PerformanceTelemetryEnabled = true,
	PerformanceTelemetryCapacity = 512,
	PerformanceTelemetrySampleEvery = 1,
	BandwidthGovernorEnabled = false,
	TransportAdaptiveBatching = false,
	TransportFastFlushEnabled = true,
	HandshakeEnabled = true,
})
local ping = NetStream.Event("__NSP95Ping", {Id = 35180, Compression = false, Priority = "Critical"})
local pong = NetStream.Event("__NSP95Pong", {Id = 35181, Compression = false, Priority = "Critical"})
local requests = {}
ping:Connect(function(player, id)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Invalid sender")
	assert(type(id) == "number" and id % 1 == 0 and id >= 1 and id <= 128, "Invalid sequence")
	requests[player] = (requests[player] or 0) + 1
	assert(pong:FireClientNow(player, id), "Server failed to send pong")
	if requests[player] == 128 then
		local stats = NetStream.GetLatencyStats()
		local memory = NetStream.GetMemoryDiagnostics()
		print(string.format("NetStream %s SERVER: %d probes, decode p95 %.3f ms, dispatch p95 %.3f ms, packet p95 %s bytes, pooled writer bytes %d", NetStream.GetVersion(), requests[player], stats.DecodeMs.P95 or -1, stats.DispatchMs.P95 or -1, tostring(stats.PacketBytes.P95), memory.PooledWriterBytes))
	end
end)
Players.PlayerRemoving:Connect(function(player) requests[player] = nil end)
print("NetStream 3.2.0 server p95 benchmark ready")
