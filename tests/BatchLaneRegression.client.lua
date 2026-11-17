--!strict
-- StarterPlayerScripts; use Play Test with the paired ServerScript and an UnreliableRemoteEvent-capable Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.1", "Expected NetStream v4.0.1")
NetStream.Configure({BandwidthGovernorEnabled = true, BandwidthMaxPacketBytes = 1200, UnreliableMaxBytes = 900, TransportTargetMessagesPerPacket = 16})
local reliable = NetStream.Event("__NSBatchReliable", {Id = 34001, Compression = false})
local unreliable = NetStream.Unreliable("__NSBatchUnreliable", {Id = 34002, Compression = false})
local ack = NetStream.Event("__NSBatchAck", {Id = 34003, Compression = false})
local folder = ReplicatedStorage:WaitForChild("__NetStream_NetStream")
local lane = folder:FindFirstChild("U")
assert(lane and lane:IsA("UnreliableRemoteEvent"), "UnreliableRemoteEvent required to verify lane budget")
local done = false
ack:Connect(function(count, observedUnreliable)
	if done then return end
	done = true
	assert(count == 120, "Reliable batch lost messages")
	local stats = NetStream.GetStats()
	assert(stats.DecodeErrors == 0, "Client packet decoding failed")
	assert(stats.FallbackReliable == 0, "Unreliable batch fell back to reliable lane")
	print(string.format("NetStream 4.0.1: reliable %d, unreliable observed by ack %d, packets %d, splits %d, predicted caps %d, unintended fallbacks %d", count, observedUnreliable, stats.SentBatches, stats.BandwidthBatchSplits, stats.TransportPredictedBatchCaps, stats.FallbackReliable))
end)
NetStream.ResetStats()
for index = 1, 120 do
	assert(reliable:FireServer(index, string.rep("R", 72)), "Reliable queue rejected an event")
end
for index = 1, 120 do
	assert(unreliable:FireServer(index, string.rep("U", 52)), "Unreliable queue rejected an event")
end
task.delay(30, function()
	if not done then warn("NetStream batching regression did not complete; inspect queue and bandwidth governor") end
end)
