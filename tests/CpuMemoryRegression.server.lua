--!strict
-- Dedicated ServerScriptService regression with Netstream + Compression in ReplicatedStorage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.25", "Expected NetStream 2.3.25")
NetStream.Configure({BandwidthGovernorEnabled = false, MaxBatchMessages = 8, TransportAdaptiveBatching = false, TransportFastFlushEnabled = false, CompressionCpuBudgetEnabled = true, CompressionMaxEstimatedSeconds = 0.0001, CompressionCpuProbeEvery = 2})
local data = NetStream.Event("__NSCpuMemoryProbe", {Id = 34210, Priority = "Normal"})
local ack = NetStream.Event("__NSCpuMemoryAck", {Id = 34211, Compression = false})
local seen = {}
data:Connect(function(player, packet)
	assert(type(packet) == "table" and type(packet.Index) == "number", "Malformed CPU probe")
	local index = packet.Index
	assert(index >= 1 and index <= 120 and index % 1 == 0, "Invalid CPU probe index")
	assert(packet.Text == string.rep("repeated-dictionary-text", 12), "CPU probe string changed")
	assert(packet.Tags[1] == "same" and packet.Tags[2] == "same", "CPU probe nested payload corrupted")
	local state = seen[player]
	if not state then state = {Hits = {}, Count = 0}; seen[player] = state end
	assert(not state.Hits[index], "Duplicate CPU probe packet")
	state.Hits[index] = true
	state.Count += 1
	if state.Count == 120 then
		local stats = NetStream.GetStats()
		assert(stats.BitFrameReadersCreated >= 1, "No BitFrame reader created")
		assert(stats.BitFrameReaderPoolHits > 0, "BitFrame reader not reused")
		ack:FireClient(player, state.Count, stats.BitFrameReaderPoolHits, stats.BitFrameReadersCreated)
	end
end)
game:GetService("Players").PlayerRemoving:Connect(function(player) seen[player] = nil end)
print("CPU/memory regression server ready")
