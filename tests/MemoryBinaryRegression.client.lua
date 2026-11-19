--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false})
local T = NetStream.Types
local Packed = NetStream.Event("__NSMemoryPacked", {Id = 35601, Schema = {T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8, T.U8}, Compression = false})
local String = NetStream.Event("__NSMemoryString", {Id = 35602, Schema = {T.String}, Compression = false})
local Ack = NetStream.Event("__NSMemoryAck", {Id = 35603, Schema = {T.U8}, Compression = false})
local completed = false
Ack:Connect(function(marker)
    assert(marker == 99, "Memory ACK value changed")
    local stats = NetStream.GetStats()
    assert(stats.PackedSchemaRunAppends > 0, "Packed schema run never formed")
    assert(stats.PackedValuePoolOversizeDrops > 0, "Large packed value list should not be retained")
    local before = NetStream.GetMemoryDiagnostics()
    assert(before.BitFrameInitialWriterBytes == 128 and before.BitFrameRetainWriterMaxBytes == 4096, "BitFrame pool defaults changed")
    assert(before.BitFrameWriterPooledBytes <= before.BitFrameRetainWriterMaxBytes * NetStream.GetConfig().MaxWriterPoolSize, "Large writer incorrectly retained")
    local cleared = NetStream.TrimPools()
    assert(cleared.BitFrameWriterPooledBytes == before.BitFrameWriterPooledBytes, "TrimPools did not report previous state")
    local after = NetStream.GetMemoryDiagnostics()
    assert(after.BitFrameWriterPoolSize == 0 and after.PackedValuePoolSize == 0 and after.PooledWriterBytes == 0, "Idle pools retained writer or packed values")
    completed = true
    print("NetStream v4.4.0 memory/binary regression PASS", before.BitFrameWriterPooledBytes, after.BitFrameWriterPooledBytes, before.LuaHeapKB, after.LuaHeapKB)
end)
for i = 1, 96 do assert(Packed:FireServer(i, 0, 255, 128, 7, 19, 31, 63), "Packed event enqueue rejected") end
for _, value in ipairs({string.rep("q", 16), string.rep("w", 32), string.rep("z", 63)}) do
    assert(String:FireServer(value), "String event enqueue rejected")
end
NetStream.Flush()
task.delay(20, function() assert(completed, "Memory/binary regression timed out") end)
