--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false})
local T = NetStream.Types
local SchemaState = NetStream.State("__NSRateSchemaState", {Id = 35701, Schema = {T.U8}, MaxPerSecond = 1, Burst = 1, Compression = false})
local DynamicState = NetStream.State("__NSRateDynamicState", {Id = 35702, MaxPerSecond = 1, Burst = 1, Compression = false})
local Ack = NetStream.Event("__NSRateStateAck", {Id = 35703, Schema = {T.U8}, Compression = false})
local seen = {}
local function maybeAck(player)
    local state = seen[player]
    if not state or not state.schema or not state.dynamic then return end
    local snapshot = NetStream.GetStateSnapshot(player)
    assert(snapshot[SchemaState.Id] == 11, "Blocked schema update overwrote accepted state")
    assert(snapshot[DynamicState.Id] == "first", "Blocked dynamic update overwrote accepted state")
    assert(NetStream.GetStats().RouteRateLimited >= 2, "Expected state rate limits to apply")
    assert(Ack:FireClientNow(player, 1), "State-rate ACK failed")
end
SchemaState:Connect(function(player, value)
    assert(value == 11, "Rate-limited schema update was dispatched")
    local state = seen[player] or {schema = false, dynamic = false}
    seen[player] = state
    state.schema = true
    maybeAck(player)
end)
DynamicState:Connect(function(player, value)
    assert(value == "first", "Rate-limited dynamic update was dispatched")
    local state = seen[player] or {schema = false, dynamic = false}
    seen[player] = state
    state.dynamic = true
    maybeAck(player)
end)
Players.PlayerRemoving:Connect(function(player) seen[player] = nil end)
print("NetStream 4.2.0 state throttle server ready")
