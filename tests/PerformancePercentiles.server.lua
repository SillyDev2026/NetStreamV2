--!strict
-- Standalone ServerScriptService unit test for rolling nearest-rank p50/p95/p99.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.9.0")
NetStream.Configure({PerformanceTelemetryEnabled = true, PerformanceTelemetryCapacity = 16, PerformanceTelemetrySampleEvery = 2})
for i = 1, 100 do NetStream.RecordRoundTripSample(i) end
local result = NetStream.GetLatencyStats()
local rtt = result.RoundTripMs
assert(rtt.Count == 16 and rtt.Observed == 100 and rtt.TotalSamples == 50, "Rolling capacity / sampling counters wrong")
assert(rtt.Min == 69 and rtt.Max == 99, "Ring buffer eviction incorrect")
assert(rtt.P50 == 83 and rtt.P95 == 99 and rtt.P99 == 99, "Rolling percentiles incorrect")
assert(result.JitterMs.Count == 16 and result.JitterMs.P95 == 1, "Jitter recording incorrect")
local performance = NetStream.GetPerformanceStats()
assert(performance.Telemetry.RoundTripMs.P95 == 99, "Performance stats integration broken")
assert(not pcall(NetStream.RecordRoundTripSample, -1), "Negative RTT must fail")
assert(not pcall(NetStream.RecordRoundTripSample, math.huge), "Infinite RTT must fail")
NetStream.ResetPerformanceTelemetry()
local empty = NetStream.GetLatencyStats()
assert(empty.RoundTripMs.Count == 0 and empty.RoundTripMs.P95 == nil and empty.JitterMs.Count == 0, "Reset should clear metrics")
local memory = NetStream.GetMemoryDiagnostics()
assert(memory.PooledWriterBytes >= 0 and memory.LuaHeapKB >= 0, "Memory diagnostics invalid")
print("NetStream v3.9.0 rolling p50/p95/p99, sampling, jitter, reset and memory diagnostic test PASS")
