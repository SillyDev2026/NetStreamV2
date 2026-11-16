--!strict
-- Standalone ServerScriptService with ReplicatedStorage.Netstream and its Compression child.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.22", "Expected NetStream v2.3.22")
NetStream.Configure({BandwidthGovernorEnabled = true, BandwidthLimitBytesPerSecond = 131072, BandwidthMaxPacketBytes = 500, BandwidthMaxPacketsPerSecond = 120, TransportBatchWindowSeconds = 0.2, TransportFastFlushEnabled = false, MaxBatchMessages = 128})
local T = NetStream.Types
local flag = NetStream.Event("__NSBooleanQueue", {Id = 35200, Compression = false, Schema = {T.Bool, T.Bool, T.Bool, T.Bool, T.Bool, T.Bool, T.Bool, T.Bool}})
local text = NetStream.Event("__NSTextQueue", {Id = 35201, Compression = false})
local ack = NetStream.Event("__NSQueueAck", {Id = 35202, Compression = false})
local active = {}
local function stateFor(player)
	local s = active[player]
	if not s then s = {Flags = 0, Texts = 0}; active[player] = s end
	return s
end
local function maybeAck(player, s)
	if s.Flags ~= 96 or s.Texts ~= 80 then return end
	local stat = NetStream.GetStats()
	assert(stat.BooleanBitPackReads >= 96, "Boolean schema did not use packed read path")
	assert(stat.DecodeErrors == 0, "Decoder rejected queue test")
	assert(ack:FireClient(player, stat.BooleanBitPackReads), "Failed to acknowledge")
end
flag:Connect(function(player, a, b, c, d, e, f, g, h)
	local index = (a and 1 or 0) + (b and 2 or 0) + (c and 4 or 0) + (d and 8 or 0) + (e and 16 or 0) + (f and 32 or 0) + (g and 64 or 0) + (h and 128 or 0)
	local s = stateFor(player)
	assert(index == s.Flags + 1, "Boolean stream lost FIFO order")
	s.Flags += 1
	maybeAck(player, s)
end)
text:Connect(function(player, index, payload)
	local s = stateFor(player)
	assert(index == s.Texts + 1, "Deferred text queue lost FIFO order")
	assert(payload == string.rep("P", 90), "Deferred payload corrupted")
	s.Texts += 1
	maybeAck(player, s)
end)
Players.PlayerRemoving:Connect(function(player) active[player] = nil end)
print("NetStream v2.3.22 boolean and deferred queue regression server ready")
