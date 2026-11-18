--!strict
-- StarterPlayerScripts; pair with HomogeneousIntegerRunRegression.server.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.0")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0.08, PackedSchemaRunEnabled = true, PackedSchemaRunMaxFields = 16, MaxBatchMessages = 128})
local T = NetStream.Types
local U16Fields = table.create(12)
local U32Fields = table.create(12)
for i = 1, 12 do U16Fields[i] = T.U16; U32Fields[i] = T.U32 end
local Word = NetStream.Event("__NSWordTuple43", {Id = 44330, Schema = U16Fields, Compression = false})
local Dword = NetStream.Event("__NSDwordTuple43", {Id = 44331, Schema = U32Fields, Compression = false})
local Ack = NetStream.Event("__NSWordAck43", {Id = 44332, Schema = {T.U16, T.U16}, Compression = false})
local seen16 = 0
local seen32 = 0
local acked = false
Word:Connect(function(...)
    seen16 += 1
    local values = {...}
    assert(select("#", ...) == 12 and values[1] == seen16 and values[2] == 0 and values[3] == 65535 and values[12] == 65535, "Client U16 echo corrupted")
end)
Dword:Connect(function(...)
    seen32 += 1
    local values = {...}
    assert(select("#", ...) == 12 and values[1] == seen32 and values[2] == 0 and values[3] == 4294967295 and values[12] == 4294967295, "Client U32 echo corrupted")
end)
Ack:Connect(function(n16, n32)
    assert(n16 == 32 and n32 == 32 and seen16 == 32 and seen32 == 32, "U16/U32 run lost replies")
    local stats = NetStream.GetStats()
    assert(stats.U16SchemaFastWrites >= 32 and stats.U16SchemaFastReads >= 32, "U16 homogeneous fast path not exercised")
    assert(stats.U32SchemaFastWrites >= 32 and stats.U32SchemaFastReads >= 32, "U32 homogeneous fast path not exercised")
    assert(stats.BitFrameHomogeneousRunFastWrites > 0 and stats.BitFrameHomogeneousRunFastReads > 0, "Homogeneous run fast paths not exercised in both directions")
    assert(stats.DecodeErrors == 0, "Homogeneous echo decode errors")
    acked = true
    print("NetStream 4.3.0 U16/U32 client PASS", stats.BitFrameHomogeneousRunFastWrites, stats.BitFrameHomogeneousRunFastReads)
end)
for i = 1, 32 do
    assert(Word:FireServer(i, 0, 65535, 8, 32768, 65535, 1, 2, 3, 4, 5, 65535), "U16 tuple enqueue failed")
    assert(Dword:FireServer(i, 0, 4294967295, 8, 2147483648, 4294967295, 1, 2, 3, 4, 5, 4294967295), "U32 tuple enqueue failed")
end
task.delay(40, function() assert(acked, "Homogeneous integer run regression timed out") end)
