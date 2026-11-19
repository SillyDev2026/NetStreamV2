--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, PackedSchemaRunEnabled = true, TransportFastFlushEnabled = false, BandwidthGovernorEnabled = false, MaxBatchMessages = 256, MaxBatchesPerFlush = 32, MaxReliableQueue = 32768, MaxDispatchBacklog = 65536, PerformanceTelemetryEnabled = true, PerformanceTelemetrySampleEvery = 1})
local T = NetStream.Types
local U16 = NetStream.Event("__NSBurstBenchU16", {Id = 36901, Schema = {T.U16}, Compression = false})
local Bool = NetStream.Event("__NSBurstBenchBool", {Id = 36902, Schema = {T.Bool}, Compression = false})
local U8x8 = NetStream.Event("__NSBurstBenchU8x8", {Id = 36903, Schema = {T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8}, Compression = false})
local Ack = NetStream.Event("__NSBurstBenchAck", {Id = 36904, Schema = {T.U16}, Compression = false})
local countPerShape = 10000
local total = countPerShape * 3
local startedAt = 0
local sendEndedAt = 0
local done = false
Ack:Connect(function(received)
	assert(received == total, "Burst benchmark acknowledgment count mismatch")
	assert(not done, "Burst benchmark duplicate completion")
	done = true
	local stats = NetStream.GetStats()
	local timing = NetStream.GetLatencyStats()
	local memory = NetStream.GetMemoryDiagnostics()
	assert(stats.DecodeErrors == 0, "Client observed malformed packet")
	print("NetStream v4.3.1 CLIENT BURST PASS", "messages", total, "enqueue_seconds", sendEndedAt - startedAt, "end_to_end_seconds", os.clock() - startedAt, "encode_p95_ms", timing.EncodeMs.P95, "packet_p95_bytes", timing.PacketBytes.P95, "sent_bytes", stats.SentBytes, "packed_fast_writes", stats.BitFramePackedScalarRunWrites, "luau_heap_kb", memory.LuaHeapKB)
end)
task.wait(2)
startedAt = os.clock()
for i = 1, countPerShape do
	assert(U16:FireServer(i), "U16 burst send rejected")
	if i % 128 == 0 then RunService.Heartbeat:Wait() end
end
for i = 1, countPerShape do
	assert(Bool:FireServer(i % 2 == 1), "Bool burst send rejected")
	if i % 128 == 0 then RunService.Heartbeat:Wait() end
end
for i = 1, countPerShape do
	local v = i % 256
	assert(U8x8:FireServer(v, (v + 1) % 256, (v + 2) % 256, (v + 3) % 256, (v + 4) % 256, (v + 5) % 256, (v + 6) % 256, (v + 7) % 256), "U8x8 burst send rejected")
	if i % 128 == 0 then RunService.Heartbeat:Wait() end
end
sendEndedAt = os.clock()
NetStream.Flush()
task.delay(90, function() assert(done, "Burst benchmark timed out: inspect server Output, queue caps and RTT") end)
