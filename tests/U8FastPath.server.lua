--!strict
-- Standalone ServerScriptService Script. Pair with U8FastPath.client.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.8.0")
local T = NetStream.Types
local schema32 = table.create(32)
local schema4 = table.create(4)
for i = 1, 32 do schema32[i] = T.U8 end
for i = 1, 4 do schema4[i] = T.U8 end
local Wide = NetStream.Event("__NSU8Wide", {Id = 35301, Compression = false, Schema = schema32})
local Short = NetStream.Event("__NSU8Short", {Id = 35302, Compression = false, Schema = schema4})
local Ack = NetStream.Event("__NSU8Ack", {Id = 35303, Compression = false})
local states = {}
local function checkDone(player)
    local state = states[player]
    if state.Wide ~= 16 or state.Short ~= 96 then return end
    local stats = NetStream.GetStats()
    assert(stats.U8SchemaFastReads >= 112, "U8 fast decoder did not run")
    assert(stats.DecodeErrors == 0, "U8 packets failed decoding")
    assert(Ack:FireClient(player, state.Wide, state.Short, stats.U8SchemaFastReads), "ACK could not be sent")
end
Wide:Connect(function(player, ...)
    assert(select("#", ...) == 32, "U8 wide schema arity invalid")
    local values = {...}
    local state = states[player] or {Wide = 0, Short = 0}
    states[player] = state
    state.Wide += 1
    assert(values[1] == state.Wide and values[32] == 255, "U8 boundary values corrupted")
    for i = 2, 31 do assert(values[i] == (i * 7) % 256, "U8 schema field corrupted") end
    checkDone(player)
end)
Short:Connect(function(player, a, b, c, d)
    local state = states[player] or {Wide = 0, Short = 0}
    states[player] = state
    state.Short += 1
    assert(a == state.Short and b == 0 and c == 128 and d == 255, "Short U8 schema corrupted or out of order")
    checkDone(player)
end)
Players.PlayerRemoving:Connect(function(player) states[player] = nil end)
print("NetStream v3.8.0 U8 schema regression server ready")
