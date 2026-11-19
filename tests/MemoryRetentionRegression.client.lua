--!strict
-- StarterPlayerScripts. Pair with MemoryRetentionRegression.server.lua in an isolated Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, PackedSchemaRunEnabled = false, TransportBatchWindowSeconds = 0, MaxBatchMessages = 32, MaxBatchesPerFlush = 1, QueueRetainMaxSlots = 16, MaxPooledDictionaryEntries = 16})
local T = NetStream.Types
local Ready = NetStream.Event("__NSMemReady43", {Id = 44360, Schema = {T.Bool}, Compression = false})
local Numeric = NetStream.Event("__NSMemNumber43", {Id = 44361, Schema = {T.U16}, Compression = false})
local Text = NetStream.Event("__NSMemText43", {Id = 44362, Schema = {T.String}, Compression = false})
local Done = NetStream.Event("__NSMemDone43", {Id = 44363, Schema = {T.U16, T.U16}, Compression = false})
local received = 0
local strings = 0
local complete = false
Numeric:Connect(function(value)
    received += 1
    assert(value == received, "Memory queue compaction changed reliable message FIFO")
end)
Text:Connect(function(value)
    strings += 1
    assert(value == string.format("memory-unique-%04d", strings), "Pooled string dictionary changed payload")
end)
Done:Connect(function(queueCompactions, dictionaryTrims)
    assert(received == 1200 and strings == 128, "Memory regression dropped traffic")
    assert(queueCompactions >= 1 and dictionaryTrims >= 1, "Server failed queue/dictionary retention checks")
    complete = true
    print("NetStream memory regression CLIENT PASS", received, strings, queueCompactions, dictionaryTrims)
end)
assert(Ready:FireServerNow(true), "Memory regression ready failed")
task.delay(40, function() assert(complete, "Memory retention regression timed out") end)
