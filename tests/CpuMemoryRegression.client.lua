--!strict
-- Dedicated StarterPlayerScripts LocalScript paired with CpuMemoryRegression.server.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0", "Expected NetStream 4.4.0")
NetStream.Configure({BandwidthGovernorEnabled = false, MaxBatchMessages = 8, TransportAdaptiveBatching = false, TransportFastFlushEnabled = false, CompressionCpuBudgetEnabled = true, CompressionMaxEstimatedSeconds = 0.0001, CompressionCpuProbeEvery = 2})
local data = NetStream.Event("__NSCpuMemoryProbe", {Id = 34210, Priority = "Normal"})
local ack = NetStream.Event("__NSCpuMemoryAck", {Id = 34211, Compression = false})
local completed = false
ack:Connect(function(count, readerHits, readerCreated)
	assert(count == 120 and readerHits > 0 and readerCreated >= 1, "Reader pooling or message delivery failed")
	local stats = NetStream.GetStats()
	assert(stats.CompressionCpuSamples > 0, "No compression CPU samples observed")
	assert(stats.CompressionCpuSampleSeconds >= 0, "Invalid compression timing")
	completed = true
	print(string.format("NetStream 4.4.0 CPU/memory PASS: %d messages, %d reader hits, %d readers created, %d CPU samples, %d CPU-budget skips", count, readerHits, readerCreated, stats.CompressionCpuSamples, stats.CompressionCpuBudgetSkips))
end)
local pattern = string.rep("repeated-dictionary-text", 12)
for i = 1, 120 do
	assert(data:FireServer({Index = i, Text = pattern, Tags = {"same", "same", "same", "same"}}), "Failed to queue CPU probe")
	if i % 8 == 0 then task.wait(0.06) end
end
task.delay(30, function() assert(completed, "CPU/memory probe did not finish") end)
