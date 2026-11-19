--!strict
-- ServerScriptService; pair with HomogeneousIntegerRunRegression.client.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0")
NetStream.Configure({HandshakeEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0.08, PackedSchemaRunEnabled = true, PackedSchemaRunMaxFields = 16, MaxBatchMessages = 128})
local T = NetStream.Types
local U16Fields = table.create(12)
local U32Fields = table.create(12)
for i = 1, 12 do U16Fields[i] = T.U16; U32Fields[i] = T.U32 end
local Word = NetStream.Event("__NSWordTuple43", {Id = 44330, Schema = U16Fields, Compression = false})
local Dword = NetStream.Event("__NSDwordTuple43", {Id = 44331, Schema = U32Fields, Compression = false})
local Ack = NetStream.Event("__NSWordAck43", {Id = 44332, Schema = {T.U16, T.U16}, Compression = false})
local seen = {}
local function done(player)
    local state = seen[player]
    if not state or state.word ~= 32 or state.dword ~= 32 or state.ack then return end
    state.ack = true
    local stats = NetStream.GetStats()
    assert(stats.U16SchemaFastReads >= 32 and stats.U32SchemaFastReads >= 32, "Server did not use U16/U32 tuple decoder")
    assert(stats.BitFrameHomogeneousRunFastReads > 0, "Server did not use homogeneous packed-run decoder")
    assert(stats.DecodeErrors == 0, "Homogeneous integer packet decode failed")
    assert(Ack:FireClient(player, state.word, state.dword), "Homogeneous ACK enqueue failed")
    print("NetStream 4.4.0 U16/U32 server PASS", stats.U16SchemaFastReads, stats.U32SchemaFastReads)
end
Word:Connect(function(player, ...)
    local state = seen[player] or {word = 0, dword = 0, ack = false}
    seen[player] = state
    state.word += 1
    assert(select("#", ...) == 12 and state.word <= 32, "U16 tuple arity/order invalid")
    local values = {...}
    assert(values[1] == state.word and values[2] == 0 and values[3] == 65535 and values[12] == 65535, "U16 tuple boundaries corrupted")
    assert(Word:FireClient(player, ...), "U16 echo failed")
    done(player)
end)
Dword:Connect(function(player, ...)
    local state = seen[player] or {word = 0, dword = 0, ack = false}
    seen[player] = state
    state.dword += 1
    assert(select("#", ...) == 12 and state.dword <= 32, "U32 tuple arity/order invalid")
    local values = {...}
    assert(values[1] == state.dword and values[2] == 0 and values[3] == 4294967295 and values[12] == 4294967295, "U32 tuple boundaries corrupted")
    assert(Dword:FireClient(player, ...), "U32 echo failed")
    done(player)
end)
Players.PlayerRemoving:Connect(function(player) seen[player] = nil end)
