--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, PackedSchemaRunEnabled = true, TransportFastFlushEnabled = false, BandwidthGovernorEnabled = false, MaxBatchMessages = 256, MaxBatchesPerFlush = 32, MaxReliableQueue = 32768, MaxDispatchBacklog = 65536, PerformanceTelemetryEnabled = true, PerformanceTelemetrySampleEvery = 1})
local T = NetStream.Types
local U16 = NetStream.Event("__NSBurstBenchU16", {Id = 36901, Schema = {T.U16}, Compression = false})
local Bool = NetStream.Event("__NSBurstBenchBool", {Id = 36902, Schema = {T.Bool}, Compression = false})
local U8x8 = NetStream.Event("__NSBurstBenchU8x8", {Id = 36903, Schema = {T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8}, Compression = false})
local Ack = NetStream.Event("__NSBurstBenchAck", {Id = 36904, Schema = {T.U16}, Compression = false})
local countPerShape = 10000
local perPlayer = {}
local function checkDone(player, state)
	if state.done or state.u16 ~= countPerShape or state.bool ~= countPerShape or state.u8 ~= countPerShape then return end
	state.done = true
	local stats = NetStream.GetStats()
	local timing = NetStream.GetLatencyStats()
	local memory = NetStream.GetMemoryDiagnostics()
	assert(stats.DecodeErrors == 0, "Server observed malformed packet")
	assert(stats.BitFramePackedScalarRunItems > 0, "No packed scalar receive path was exercised")
	print("NetStream v4.0.0 SERVER BURST PASS", "messages", countPerShape * 3, "decode_p95_ms", timing.DecodeMs.P95, "dispatch_p95_ms", timing.DispatchMs.P95, "received_bytes", stats.ReceivedBytes, "packed_scalar_reads", stats.BitFramePackedScalarRunItems, "luau_heap_kb", memory.LuaHeapKB)
	assert(Ack:FireClientNow(player, countPerShape * 3), "Burst benchmark ACK failed")
end
local function stateFor(player)
	local state = perPlayer[player]
	if not state then
		state = {u16 = 0, bool = 0, u8 = 0, done = false}
		perPlayer[player] = state
	end
	return state
end
U16:Connect(function(player, value)
	local state = stateFor(player)
	state.u16 += 1
	assert(state.u16 <= countPerShape and value == state.u16, "U16 burst order/payload mismatch")
	checkDone(player, state)
end)
Bool:Connect(function(player, value)
	local state = stateFor(player)
	state.bool += 1
	assert(state.bool <= countPerShape and value == (state.bool % 2 == 1), "Bool burst order/payload mismatch")
	checkDone(player, state)
end)
U8x8:Connect(function(player, a, b, c, d, e, f, g, h)
	local state = stateFor(player)
	state.u8 += 1
	local v = state.u8 % 256
	assert(state.u8 <= countPerShape and a == v and b == (v + 1) % 256 and c == (v + 2) % 256 and d == (v + 3) % 256 and e == (v + 4) % 256 and f == (v + 5) % 256 and g == (v + 6) % 256 and h == (v + 7) % 256, "U8x8 burst order/payload mismatch")
	checkDone(player, state)
end)
print("NetStream v4.0.0 burst benchmark server ready")
