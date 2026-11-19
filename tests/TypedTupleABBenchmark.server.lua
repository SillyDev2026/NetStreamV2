--!strict
-- ServerScriptService. Pair with TypedTupleABBenchmark.client.lua; run a fresh Play session for each A/B choice.
-- Optional ReplicatedStorage BoolValue "NSTypedTupleFastPath": true = optimized, false = previous fallback.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
local switch = ReplicatedStorage:FindFirstChild("NSTypedTupleFastPath")
local fast = if switch and switch:IsA("BoolValue") then switch.Value else true
NetStream.Configure({HandshakeEnabled = false, TypedTupleFastPathEnabled = fast, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0.03, TransportTargetMessagesPerPacket = 128, PackedSchemaRunEnabled = true, PackedSchemaRunMaxFields = 16, MaxBatchMessages = 256, PerformanceTelemetryEnabled = true, PerformanceTelemetrySampleEvery = 1, PerformanceTelemetryCapacity = 512})
local T = NetStream.Types
local schema16, schema32 = table.create(12), table.create(12)
for i = 1, 12 do schema16[i] = T.U16; schema32[i] = T.U32 end
local U16 = NetStream.Event("__ABU1643", {Id = 44340, Schema = schema16, Compression = false})
local U32 = NetStream.Event("__ABU3243", {Id = 44341, Schema = schema32, Compression = false})
local Ack = NetStream.Event("__ABAck43", {Id = 44342, Schema = {T.U16, T.U16}, Compression = false})
local counts = {}
local TARGET = 512
local function finish(player)
    local state = counts[player]
    if state.n16 ~= TARGET or state.n32 ~= TARGET or state.complete then return end
    state.complete = true
    local stats = NetStream.GetStats()
    local lat = NetStream.GetLatencyStats()
    local perMessage = if stats.ReceivedMessages > 0 then stats.ReceivedBytes / stats.ReceivedMessages else 0
    print("TypedTuple A/B server", "fast=" .. tostring(fast), "messages=" .. tostring(stats.ReceivedMessages), "bytes/message=" .. tostring(perMessage), "decodeP95ms=" .. tostring(lat.DecodeMs and lat.DecodeMs.P95), "fast16reads=" .. tostring(stats.U16SchemaFastReads), "fast32reads=" .. tostring(stats.U32SchemaFastReads))
    if fast then assert(stats.U16SchemaFastReads >= TARGET and stats.U32SchemaFastReads >= TARGET, "Fast U16/U32 reader missing")
    else assert(stats.U16SchemaFastReads == 0 and stats.U32SchemaFastReads == 0, "Fallback still using typed tuple decoder") end
    assert(Ack:FireClient(player, TARGET, TARGET), "Benchmark ACK failed")
end
U16:Connect(function(player, ...)
    local state = counts[player] or {n16 = 0, n32 = 0, complete = false}
    counts[player] = state
    state.n16 += 1
    assert(state.n16 <= TARGET and select("#", ...) == 12 and select(1, ...) == state.n16, "U16 benchmark payload corrupted")
    finish(player)
end)
U32:Connect(function(player, ...)
    local state = counts[player] or {n16 = 0, n32 = 0, complete = false}
    counts[player] = state
    state.n32 += 1
    assert(state.n32 <= TARGET and select("#", ...) == 12 and select(1, ...) == state.n32, "U32 benchmark payload corrupted")
    finish(player)
end)
Players.PlayerRemoving:Connect(function(player) counts[player] = nil end)
