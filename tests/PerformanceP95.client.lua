--!strict
-- Use as a standalone LocalScript in StarterPlayerScripts with PerformanceP95.server.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local count = 0
local sentAt = 0
local completed = false
local function report()
	local samples = NetStream.GetLatencyStats()
	local memory = NetStream.GetMemoryDiagnostics()
	assert(samples.RoundTripMs.Count == 128, "Expected 128 real RTT samples")
	assert(samples.RoundTripMs.P50 <= samples.RoundTripMs.P95 and samples.RoundTripMs.P95 <= samples.RoundTripMs.P99, "RTT percentiles are unsorted")
	print(string.format("NetStream %s RTT (application-level) samples=%d p50=%.3fms p95=%.3fms p99=%.3fms jitter_p95=%.3fms", NetStream.GetVersion(), samples.RoundTripMs.Count, samples.RoundTripMs.P50, samples.RoundTripMs.P95, samples.RoundTripMs.P99, samples.JitterMs.P95 or -1))
	print(string.format("CPU encode p95=%.3fms decode p95=%.3fms dispatch p95=%.3fms queue p95=%.3fms packet p95=%s bytes, pooled writer memory=%d bytes, Luau heap=%.1fKB", samples.EncodeMs.P95 or -1, samples.DecodeMs.P95 or -1, samples.DispatchMs.P95 or -1, samples.QueueMs.P95 or -1, tostring(samples.PacketBytes.P95), memory.PooledWriterBytes, memory.LuaHeapKB))
	completed = true
end
local function sendNext()
	if count >= 128 then report(); return end
	sentAt = os.clock()
	assert(ping:FireServerNow(count + 1), "Failed to send ping")
end
pong:Connect(function(id)
	assert(id == count + 1, "Out-of-order or duplicate benchmark pong")
	NetStream.RecordRoundTripSample((os.clock() - sentAt) * 1000)
	count += 1
	task.defer(sendNext)
end)
-- Validate nearest-rank quantile selection on deterministic data, then clear samples.
for i = 1, 100 do NetStream.RecordRoundTripSample(i) end
local predictable = NetStream.GetLatencyStats().RoundTripMs
assert(predictable.P50 == 50 and predictable.P95 == 95 and predictable.P99 == 99, "Quantile calculation incorrect")
NetStream.ResetPerformanceTelemetry()
task.defer(sendNext)
task.delay(45, function() assert(completed, "P95 benchmark timed out after 45 seconds") end)
