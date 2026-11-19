--!strict
-- ServerScriptService. Pair with MemoryRetentionRegression.client.lua in an isolated Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, PackedSchemaRunEnabled = false, TransportBatchWindowSeconds = 0, MaxBatchMessages = 32, MaxBatchesPerFlush = 1, QueueRetainMaxSlots = 16, MaxPooledDictionaryEntries = 16})
local T = NetStream.Types
local Ready = NetStream.Event("__NSMemReady43", {Id = 44360, Schema = {T.Bool}, Compression = false})
local Numeric = NetStream.Event("__NSMemNumber43", {Id = 44361, Schema = {T.U16}, Compression = false})
local Text = NetStream.Event("__NSMemText43", {Id = 44362, Schema = {T.String}, Compression = false})
local Done = NetStream.Event("__NSMemDone43", {Id = 44363, Schema = {T.U16, T.U16}, Compression = false})
local started = {}
local NUMERIC_COUNT = 1200
local STRING_COUNT = 128
Ready:Connect(function(player, ready)
    assert(ready and not started[player], "Memory test started more than once")
    started[player] = true
    task.spawn(function()
        for i = 1, NUMERIC_COUNT do
            assert(Numeric:FireClient(player, i), "Numeric memory stress enqueue failed")
        end
        for i = 1, STRING_COUNT do
            assert(Text:FireClient(player, string.format("memory-unique-%04d", i)), "Dictionary stress enqueue failed")
        end
        local tries = 0
        while tries < 120 and NetStream.GetStats().QueuedReliable > 0 do
            NetStream.Flush()
            tries += 1
            task.wait()
        end
        assert(NetStream.GetStats().QueuedReliable == 0, "Outgoing reliable queue did not drain")
        local diag = NetStream.GetMemoryDiagnostics()
        assert(diag.QueueCompactions >= 1, "Persistent sparse queue was not compacted")
        assert(diag.QueueStorageRebuilds >= 1, "Large emptied queue storage was not released")
        assert(diag.DictionaryPoolRebuilds >= 1, "Large idle string dictionary was not rebuilt")
        assert(diag.QueueRetainMaxSlots == 16 and diag.MaxPooledDictionaryEntries == 16, "Memory caps not applied")
        assert(Done:FireClient(player, diag.QueueCompactions, diag.DictionaryPoolRebuilds), "Memory diagnostics ACK enqueue failed")
        NetStream.FlushTarget(player)
        print("NetStream memory regression SERVER PASS", diag.QueueCompactions, diag.QueueStorageRebuilds, diag.DictionaryPoolRebuilds, diag.LuaHeapKB)
    end)
end)
