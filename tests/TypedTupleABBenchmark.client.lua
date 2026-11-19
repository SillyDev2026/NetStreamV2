--!strict
-- StarterPlayerScripts. Pair with TypedTupleABBenchmark.server.lua; run separate sessions with optional BoolValue "NSTypedTupleFastPath".
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local TARGET = 512
local start = os.clock()
local finished = false
Ack:Connect(function(n16, n32)
    assert(n16 == TARGET and n32 == TARGET, "A/B benchmark message loss")
    local stats = NetStream.GetStats()
    local lat = NetStream.GetLatencyStats()
    local elapsed = os.clock() - start
    local perMessage = if stats.SentMessages > 0 then stats.SentBytes / stats.SentMessages else 0
    print("TypedTuple A/B client", "fast=" .. tostring(fast), "elapsed=" .. tostring(elapsed), "sent=" .. tostring(stats.SentMessages), "encodedBytesPerMessage=" .. tostring(perMessage), "encodeP95ms=" .. tostring(lat.EncodeMs and lat.EncodeMs.P95), "fastRunWrites=" .. tostring(stats.BitFrameHomogeneousRunFastWrites))
    assert(stats.DecodeErrors == 0 and stats.SentMessages >= TARGET * 2, "A/B benchmark failed to send all messages")
    if fast then assert(stats.BitFrameHomogeneousRunFastWrites > 0, "Fast packed-run writer missing")
    else assert(stats.BitFrameHomogeneousRunFastWrites == 0, "Fallback unexpectedly used optimized packed-run writer") end
    finished = true
end)
for i = 1, TARGET do
    assert(U16:FireServer(i, 0, 65535, 8, 32768, 65535, 1, 2, 3, 4, 5, 65535), "U16 benchmark enqueue failed")
end
for i = 1, TARGET do
    assert(U32:FireServer(i, 0, 4294967295, 8, 2147483648, 4294967295, 1, 2, 3, 4, 5, 4294967295), "U32 benchmark enqueue failed")
end
NetStream.Flush()
task.delay(45, function() assert(finished, "A/B benchmark timed out") end)
